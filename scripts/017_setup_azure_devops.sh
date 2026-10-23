#!/bin/sh
# Sets up an Azure DevOps project for ProjectControl, for when the team moves from GitHub to
# Azure DevOps (docs/AZURE.md, "Moving to Azure DevOps"). Run once by the project admin,
# after the repository was imported into Azure Repos.
#
#   1. variable group 'projectcontrol-ci'  SONAR_TOKEN (secret), SONAR_HOST_URL,
#                                          SONAR_ORGANIZATION, SONAR_PROJECT_KEY
#   2. pipelines  projectcontrol-ci (azure-pipelines/ci.yml), projectcontrol-cd (azure-pipelines/cd.yml)
#   3. environments  projectcontrol-test, projectcontrol-acceptance, projectcontrol-production
#   4. branch policies on develop and main (= the GitHub ruleset "Protect main and develop"):
#        at least 1 reviewer (not the author), votes reset on new pushes,
#        all comments resolved, build validation with projectcontrol-ci, merge commits only
#   5. PR templates copied to .azuredevops/ (Azure DevOps does not read .github/)
#
# Not automated (needs a person in the portal, takes a few minutes; listed at the end):
#   service connections (Azure per environment + GHCR), the approval on production,
#   SonarQube Cloud binding to Azure DevOps.
#
# Requires: Azure CLI with the azure-devops extension (az extension add -n azure-devops),
# signed in with 'az login' as project administrator.
#
# Usage (from inside the repo):
#   SONAR_TOKEN=... sh scripts/017_setup_azure_devops.sh <https://dev.azure.com/org> <project> [repository]
# Safe to run again (existing items are kept).

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

org=$1; project=$2; repo_name=${3:-$2}
if [ -z "$org" ] || [ -z "$project" ]; then
  echo "Usage: SONAR_TOKEN=... sh scripts/017_setup_azure_devops.sh <https://dev.azure.com/org> <project> [repository]"
  exit 2
fi
command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found."; exit 1; }
az extension show -n azure-devops >/dev/null 2>&1 || az extension add -n azure-devops >/dev/null || { echo "Could not add the azure-devops extension."; exit 1; }
az config set core.only_show_errors=true >/dev/null 2>&1
az devops configure --defaults organization="$org" project="$project" >/dev/null || exit 1

ok()   { echo "OK       $1"; }
fail() { echo "FAILED   $1"; exit 1; }

repo_id=$(az repos show -r "$repo_name" --query id -o tsv) || fail "repository '$repo_name' not found in $project"
echo "Azure DevOps: $org / $project / $repo_name"
echo ""

# ---------- 1. Variable group ----------
group="projectcontrol-ci"
group_id=$(az pipelines variable-group list --group-name "$group" --query '[0].id' -o tsv)
if [ -z "$group_id" ]; then
  group_id=$(az pipelines variable-group create --name "$group" --authorize true \
    --variables "SONAR_HOST_URL=${SONAR_HOST_URL:-https://sonarcloud.io}" \
                "SONAR_ORGANIZATION=${SONAR_ORGANIZATION:-team5-vanroey}" \
                "SONAR_PROJECT_KEY=${SONAR_PROJECT_KEY:-Team5-VanRoey_IT-Project-Van-Roey}" \
    --query id -o tsv) || fail "variable group $group"
  ok "variable group $group"
else
  ok "variable group $group (already present)"
fi
if [ -n "$SONAR_TOKEN" ]; then
  az pipelines variable-group variable update --group-id "$group_id" --name SONAR_TOKEN --secret true --value "$SONAR_TOKEN" >/dev/null 2>&1 \
    || az pipelines variable-group variable create --group-id "$group_id" --name SONAR_TOKEN --secret true --value "$SONAR_TOKEN" >/dev/null \
    || fail "secret SONAR_TOKEN"
  ok "secret SONAR_TOKEN"
else
  echo "SKIPPED  SONAR_TOKEN not given: add it later as secret variable in '$group'"
fi

# ---------- 2. Pipelines ----------
pipeline() {
  id=$(az pipelines show --name "$1" --query id -o tsv 2>/dev/null)
  if [ -z "$id" ]; then
    id=$(az pipelines create --name "$1" --yml-path "$2" --repository "$repo_name" --repository-type tfsgit \
      --branch develop --skip-first-run true --query id -o tsv) || fail "pipeline $1"
    echo "OK       pipeline $1 ($2)" >&2
  else
    echo "OK       pipeline $1 (already present)" >&2
  fi
  echo "$id"
}
ci_id=$(pipeline projectcontrol-ci azure-pipelines/ci.yml) || exit 1
pipeline projectcontrol-cd azure-pipelines/cd.yml >/dev/null || exit 1

# ---------- 3. Environments ----------
existing_envs=$(az devops invoke --area distributedtask --resource environments \
  --route-parameters project="$project" --api-version 7.1 --query 'value[].name' -o tsv 2>/dev/null)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
for e in test acceptance production; do
  name="projectcontrol-$e"
  if printf '%s\n' "$existing_envs" | grep -qx "$name"; then
    ok "environment $name (already present)"
  else
    printf '{"name":"%s","description":"ProjectControl DTAP - %s"}' "$name" "$e" > "$tmp/env.json"
    az devops invoke --area distributedtask --resource environments --route-parameters project="$project" \
      --http-method POST --in-file "$tmp/env.json" --api-version 7.1 >/dev/null || fail "environment $name"
    ok "environment $name"
  fi
done

# ---------- 4. Branch policies ----------
for branch in develop main; do
  existing=$(az repos policy list --repository-id "$repo_id" --branch "$branch" --query '[].type.displayName' -o tsv)
  has() { printf '%s\n' "$existing" | grep -qx "$1"; }

  has "Minimum number of reviewers" || az repos policy approver-count create --repository-id "$repo_id" \
    --branch "$branch" --blocking true --enabled true --minimum-approver-count 1 \
    --creator-vote-counts false --allow-downvotes false --reset-on-source-push true >/dev/null \
    || fail "reviewer policy on $branch"
  has "Comment requirements" || az repos policy comment-required create --repository-id "$repo_id" \
    --branch "$branch" --blocking true --enabled true >/dev/null || fail "comment policy on $branch"
  has "Build" || az repos policy build create --repository-id "$repo_id" --branch "$branch" \
    --blocking true --enabled true --build-definition-id "$ci_id" --display-name "CI (all checks)" \
    --manual-queue-only false --queue-on-source-update-only false --valid-duration 0 >/dev/null \
    || fail "build validation on $branch"
  has "Require a merge strategy" || az repos policy merge-strategy create --repository-id "$repo_id" \
    --branch "$branch" --blocking true --enabled true --allow-no-fast-forward true >/dev/null \
    || fail "merge strategy on $branch"
  ok "branch policies on $branch: 1 reviewer, comments resolved, CI green, merge commit"
done

# ---------- 5. PR templates ----------
mkdir -p .azuredevops/pull_request_template
cp .github/pull_request_template.md .azuredevops/pull_request_template.md
cp .github/PULL_REQUEST_TEMPLATE/*.md .azuredevops/pull_request_template/
ok "PR templates copied to .azuredevops/ (commit them through a normal PR)"

cat <<EOF

Done. Still to do in the portal (Project settings / Pipelines):
  1. Service connections (Project settings -> Service connections -> New):
     - Azure Resource Manager -> Workload identity federation (automatic), scope: resource group
         azure-projectcontrol-test -> rg-projectcontrol-test
         azure-projectcontrol-acc  -> rg-projectcontrol-acc
         azure-projectcontrol-prod -> rg-projectcontrol-prod
     - Docker Registry -> Others: ghcr-projectcontrol (https://ghcr.io, GitHub token with write:packages)
       or set a pipeline variable REGISTRY to an Azure Container Registry (used by scripts/014_images.sh).
  2. Pipelines -> Environments -> projectcontrol-production -> Approvals and checks -> Approvals:
     add the reviewers, untick "Allow approvers to approve their own runs".
  3. SonarQube Cloud: bind the organization to Azure DevOps (Administration -> Organization
     settings) for PR decoration.
  4. Run projectcontrol-ci once on develop, and approve the pipeline permissions it asks for.
EOF
