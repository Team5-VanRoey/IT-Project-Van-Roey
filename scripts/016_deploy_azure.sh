#!/bin/sh
# Deploys a release to one DTAP environment on Azure Container Apps (created by 015_setup_azure.sh).
# Used by GitHub Actions (_deploy.yml, DEPLOY_TARGET=azure) and Azure DevOps
# (azure-pipelines/templates/deploy.yml). The caller must already be signed in to Azure:
# in CI through OIDC / workload identity federation, locally with 'az login'.
#
# Build once, deploy everywhere: this script never builds. It points the container apps to the
# images CI built (API_IMAGE / WEB_IMAGE digests, or looked up for the checked-out commit).
#
#   1. remembers the images that run now (for the rollback)
#   2. points pc-<env>-api and pc-<env>-web to the new images, ingress on port 8080
#   3. smoke test on the public URL (013_smoke_test.sh)
#   4. smoke test fails -> rolls back to the previous images and fails
#
# Environment:
#   API_IMAGE, WEB_IMAGE   images to deploy (repo@sha256:...); default: the ones CI built for
#                          the checked-out commit (scripts/014_images.sh resolve)
#   AZURE_RESOURCE_GROUP   default rg-projectcontrol-<env>
#   APP_URL                default: the URL of pc-<env>-web
#
# Usage: sh scripts/016_deploy_azure.sh <test|acc|prod>

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

env=$1
case "$env" in
  test|acc|prod) ;;
  *) echo "Usage: sh scripts/016_deploy_azure.sh <test|acc|prod>"; exit 2 ;;
esac
if [ -z "$API_IMAGE" ] || [ -z "$WEB_IMAGE" ]; then
  images=$(sh scripts/014_images.sh resolve) || { echo "No images found for this commit: CI builds them."; exit 1; }
  eval "$(printf '%s\n' "$images" | grep -E '^(API|WEB)_(IMAGE|TAG)=')"
fi
commit=${DEPLOY_COMMIT:-$(git rev-parse HEAD)}
command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found."; exit 1; }
az account show >/dev/null 2>&1 || { echo "Not signed in to Azure (az login, or azure/login in CI)."; exit 1; }

az config set extension.use_dynamic_install=yes_without_prompt >/dev/null 2>&1
az config set core.only_show_errors=true >/dev/null 2>&1

rg=${AZURE_RESOURCE_GROUP:-rg-projectcontrol-$env}
api="pc-$env-api"
web="pc-$env-web"

image_of() { az containerapp show -g "$rg" -n "$1" --query 'properties.template.containers[0].image' -o tsv; }
env_of() {  # env_of <app> <variable>
  az containerapp show -g "$rg" -n "$1" --query "properties.template.containers[0].env[?name=='$2'].value | [0]" -o tsv 2>/dev/null
}

prev_api=$(image_of "$api") || { echo "Container app $api not found in $rg. Run scripts/015_setup_azure.sh $env first."; exit 1; }
prev_web=$(image_of "$web") || { echo "Container app $web not found in $rg."; exit 1; }
prev_commit=$(env_of "$web" DEPLOY_COMMIT); prev_api_version=$(env_of "$web" API_VERSION); prev_web_version=$(env_of "$web" WEB_VERSION)
url=${APP_URL:-https://$(az containerapp show -g "$rg" -n "$web" --query properties.configuration.ingress.fqdn -o tsv)}

echo "Environment: $env ($rg)"
echo "Now:         $prev_api"
echo "             $prev_web"
echo "New:         $API_IMAGE (${API_TAG:-?})"
echo "             $WEB_IMAGE (${WEB_TAG:-?})"
echo "Commit:      $commit"
echo ""

# deploy <api image> <web image> <commit> <api version> <web version>
deploy() {
  echo "=============== API -> $1"
  az containerapp update -g "$rg" -n "$api" --image "$1" >/dev/null || return 1
  az containerapp ingress enable -g "$rg" -n "$api" --type internal --target-port 8080 \
    --transport http --allow-insecure >/dev/null || return 1

  echo "=============== Frontend -> $2"
  az containerapp update -g "$rg" -n "$web" --image "$2" --set-env-vars "API_UPSTREAM=http://$api" \
    "DEPLOY_ENV=$env" "DEPLOY_COMMIT=$3" "API_VERSION=$4" "WEB_VERSION=$5" >/dev/null || return 1
  az containerapp ingress enable -g "$rg" -n "$web" --type external --target-port 8080 >/dev/null || return 1
}

# Scale-to-zero + a paused free database: the first request can take a minute
export RETRIES=${RETRIES:-60}

if deploy "$API_IMAGE" "$WEB_IMAGE" "$commit" "${API_TAG:-unknown}" "${WEB_TAG:-unknown}" \
   && EXPECT_COMMIT="$commit" sh scripts/013_smoke_test.sh "$url"; then
  echo ""
  echo "Deployed to $env: $url"
  exit 0
fi

echo ""
echo "FAILED: rolling back to the previous version."
case "$prev_api" in
  */k8se/quickstart*) echo "No previous release (first deployment): nothing to roll back to." ;;
  *) deploy "$prev_api" "$prev_web" "${prev_commit:-unknown}" "${prev_api_version:-unknown}" "${prev_web_version:-unknown}" && echo "Rolled back to $prev_api / $prev_web." \
       || echo "ROLLBACK FAILED: check the apps in the Azure portal." ;;
esac
echo "Logs: az containerapp logs show -g $rg -n $api --tail 100"
exit 1
