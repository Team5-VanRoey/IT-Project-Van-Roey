#!/bin/sh
# Creates one DTAP environment on Azure. Run once per environment by the admin.
# Architecture and costs: docs/AZURE.md.
#
#   resource group       rg-projectcontrol-<env>
#   Azure SQL            sql-projectcontrol-<env>-<id> + database ProjectControl on the free offer
#                        (serverless, auto-pause when the monthly free amount is used up)
#   Container Apps env   cae-projectcontrol-<env> (Consumption, scales to zero)
#   container apps       pc-<env>-api (internal, only reachable from the frontend)
#                        pc-<env>-web (public HTTPS URL)
#   deploy identity      app registration github-projectcontrol-<env>, Contributor on this resource
#                        group only, with a federated credential (OIDC) for the GitHub environment:
#                        no password or key is stored anywhere
#   GitHub environment   variables AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID,
#                        AZURE_RESOURCE_GROUP, APP_URL and DEPLOY_TARGET=azure
#
# The database password is generated, stored only as a secret of the API container app and never
# printed. The apps start with a placeholder image; the first CD run deploys the real images.
#
# Requires: Azure CLI (az login, Owner or Contributor + User Access Administrator on the
# subscription), GitHub CLI (gh auth login as repository admin), openssl.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/015_setup_azure.sh <test|acc|prod>
# Environment (optional):
#   AZURE_LOCATION      default westeurope
#   AZURE_MIN_REPLICAS  default 0 (scale to zero; 1 = no cold start, costs more)
#   GHCR_USERNAME + GHCR_TOKEN  only when the GHCR packages are private (token: read:packages)
#   SKIP_GITHUB=1       do not touch GitHub (e.g. when the project moved to Azure DevOps)
# Safe to run again: existing resources are kept.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

env=$1
case "$env" in
  test) gh_env="test";     aspnet=Test ;;
  acc)  gh_env=acceptance; aspnet=Staging ;;
  prod) gh_env=production; aspnet=Production ;;
  *)    echo "Usage: sh scripts/015_setup_azure.sh <test|acc|prod>"; exit 2 ;;
esac

command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found: https://aka.ms/azure-cli"; exit 1; }
az account show >/dev/null 2>&1 || { echo "Sign in first with: az login"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl not found."; exit 1; }
if [ -z "$SKIP_GITHUB" ]; then
  command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found (or set SKIP_GITHUB=1)."; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Sign in first with: gh auth login"; exit 1; }
  repo=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}
  [ -n "$repo" ] || { echo "Could not determine the repository. Set REPO=owner/repo"; exit 1; }
fi

az config set extension.use_dynamic_install=yes_without_prompt >/dev/null 2>&1
az config set core.only_show_errors=true >/dev/null 2>&1

location=${AZURE_LOCATION:-westeurope}
min_replicas=${AZURE_MIN_REPLICAS:-0}
subscription=$(az account show --query id -o tsv)
tenant=$(az account show --query tenantId -o tsv)
suffix=$(printf '%s' "$subscription" | cut -c1-6)

rg="rg-projectcontrol-$env"
sql_server="sql-projectcontrol-$env-$suffix"
db=ProjectControl
cae="cae-projectcontrol-$env"
api="pc-$env-api"
web="pc-$env-web"
identity="github-projectcontrol-$env"
placeholder=mcr.microsoft.com/k8se/quickstart:latest

ok()   { echo "OK       $1"; }
fail() { echo "FAILED   $1"; exit 1; }

echo "Subscription: $(az account show --query name -o tsv) ($subscription)"
echo "Environment:  $env -> $rg in $location"
echo ""

for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.Sql; do
  az provider register --namespace "$ns" >/dev/null || fail "register provider $ns"
done
ok "resource providers registered"

az group create -n "$rg" -l "$location" --tags app=projectcontrol dtap="$env" >/dev/null || fail "resource group $rg"
ok "resource group $rg"

# ---------- Azure SQL (free offer) ----------
if az sql server show -g "$rg" -n "$sql_server" >/dev/null 2>&1; then
  ok "SQL server $sql_server (already present)"
  new_password=""
else
  # Upper, lower, digit and symbol; no ';' or quotes (connection string)
  new_password="Pc-$(openssl rand -hex 16)-$(openssl rand -hex 3 | tr 'a-f' 'A-F')"
  az sql server create -g "$rg" -n "$sql_server" -l "$location" \
    --admin-user pcadmin --admin-password "$new_password" --minimal-tls-version 1.2 >/dev/null \
    || fail "SQL server $sql_server"
  ok "SQL server $sql_server"
fi

# Container Apps on the Consumption plan have no fixed outbound IP: allow Azure services only
az sql server firewall-rule create -g "$rg" -s "$sql_server" -n AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 >/dev/null || fail "SQL firewall rule"
ok "SQL firewall: only Azure services"

if az sql db show -g "$rg" -s "$sql_server" -n "$db" >/dev/null 2>&1; then
  ok "database $db (already present)"
else
  az sql db create -g "$rg" -s "$sql_server" -n "$db" \
    --edition GeneralPurpose --family Gen5 --capacity 2 --compute-model Serverless \
    --use-free-limit true --free-limit-exhaustion-behavior AutoPause \
    --backup-storage-redundancy Local >/dev/null \
    || fail "database $db (the free offer allows 10 databases per subscription; see docs/AZURE.md)"
  ok "database $db (free offer, auto-pause when the free amount is used)"
fi

# ---------- Container Apps ----------
if az containerapp env show -g "$rg" -n "$cae" >/dev/null 2>&1; then
  ok "Container Apps environment $cae (already present)"
else
  # Logs only in the Container Apps console stream: a Log Analytics workspace costs per GB
  az containerapp env create -g "$rg" -n "$cae" -l "$location" --logs-destination none >/dev/null \
    || fail "Container Apps environment $cae"
  ok "Container Apps environment $cae"
fi

registry_args=""
if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
  registry_args="--registry-server ghcr.io --registry-username $GHCR_USERNAME --registry-password $GHCR_TOKEN"
fi

if az containerapp show -g "$rg" -n "$api" >/dev/null 2>&1; then
  ok "container app $api (already present)"
  if [ -n "$new_password" ]; then
    echo "WARNING  the SQL server was recreated: update the db-connection secret of $api by hand."
  fi
else
  [ -n "$new_password" ] || fail "$api is missing but the SQL server exists: reset its password (az sql server update -p) and delete the server or the app first"
  conn="Server=tcp:$sql_server.database.windows.net,1433;Database=$db;User ID=pcadmin;Password=$new_password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60"
  # shellcheck disable=SC2086  # registry_args is empty or several arguments
  az containerapp create -g "$rg" -n "$api" --environment "$cae" \
    --image "$placeholder" \
    --cpu 0.5 --memory 1.0Gi --min-replicas "$min_replicas" --max-replicas 2 \
    --secrets "db-connection=$conn" \
    --env-vars "ASPNETCORE_ENVIRONMENT=$aspnet" "ConnectionStrings__ProjectControl=secretref:db-connection" \
               "Database__MigrateOnStartup=true" "HealthChecks__Enabled=true" "BehindReverseProxy=true" \
    $registry_args >/dev/null || fail "container app $api"
  # Internal only; plain HTTP is allowed because the traffic never leaves the environment
  az containerapp ingress enable -g "$rg" -n "$api" --type internal --target-port 80 \
    --transport http --allow-insecure >/dev/null || fail "ingress $api"
  ok "container app $api (internal; connection string stored as app secret)"
fi
unset new_password conn

if az containerapp show -g "$rg" -n "$web" >/dev/null 2>&1; then
  ok "container app $web (already present)"
else
  # shellcheck disable=SC2086
  az containerapp create -g "$rg" -n "$web" --environment "$cae" \
    --image "$placeholder" --target-port 80 --ingress external \
    --cpu 0.25 --memory 0.5Gi --min-replicas "$min_replicas" --max-replicas 3 \
    --env-vars "API_UPSTREAM=http://$api" \
    $registry_args >/dev/null || fail "container app $web"
  ok "container app $web (public)"
fi
fqdn=$(az containerapp show -g "$rg" -n "$web" --query properties.configuration.ingress.fqdn -o tsv)
[ -n "$fqdn" ] || fail "could not read the public URL of $web"
app_url="https://$fqdn"
ok "URL: $app_url"

# ---------- Deploy identity (OIDC, no secrets) ----------
app_id=$(az ad app list --display-name "$identity" --query '[0].appId' -o tsv)
if [ -z "$app_id" ]; then
  app_id=$(az ad app create --display-name "$identity" --query appId -o tsv) || fail "app registration $identity"
  ok "app registration $identity"
else
  ok "app registration $identity (already present)"
fi
az ad sp show --id "$app_id" >/dev/null 2>&1 || az ad sp create --id "$app_id" >/dev/null || fail "service principal"

scope="/subscriptions/$subscription/resourceGroups/$rg"
if [ -z "$(az role assignment list --assignee "$app_id" --scope "$scope" --role Contributor --query '[0].id' -o tsv)" ]; then
  az role assignment create --assignee "$app_id" --role Contributor --scope "$scope" >/dev/null \
    || fail "role assignment (you need Owner or User Access Administrator)"
fi
ok "deploy identity is Contributor on $rg only"

if [ -z "$SKIP_GITHUB" ]; then
  subject="repo:$repo:environment:$gh_env"
  if az ad app federated-credential list --id "$app_id" --query "[?subject=='$subject'].name" -o tsv | grep -q .; then
    ok "federated credential for GitHub environment '$gh_env' (already present)"
  else
    cat > "${TMPDIR:-/tmp}/fic-$env.json" <<EOF
{
  "name": "github-$gh_env",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$subject",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
    az ad app federated-credential create --id "$app_id" --parameters "@${TMPDIR:-/tmp}/fic-$env.json" >/dev/null \
      || fail "federated credential"
    rm -f "${TMPDIR:-/tmp}/fic-$env.json"
    ok "federated credential: only GitHub environment '$gh_env' of $repo can log in"
  fi

  for kv in "AZURE_CLIENT_ID=$app_id" "AZURE_TENANT_ID=$tenant" "AZURE_SUBSCRIPTION_ID=$subscription" \
            "AZURE_RESOURCE_GROUP=$rg" "APP_URL=$app_url" "DEPLOY_TARGET=azure"; do
    gh variable set "${kv%%=*}" --env "$gh_env" --repo "$repo" --body "${kv#*=}" >/dev/null \
      || fail "GitHub variable ${kv%%=*} (run scripts/008_setup_environments.sh first)"
  done
  ok "GitHub environment '$gh_env': DEPLOY_TARGET=azure + Azure variables"
fi

echo ""
echo "Done. The next CD run deploys to $app_url"
echo "Azure DevOps: create a service connection to $rg (docs/AZURE.md, 'Moving to Azure DevOps')."
