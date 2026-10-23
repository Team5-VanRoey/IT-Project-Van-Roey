#!/bin/sh
# Creates the DTAP environments on GitHub. Run once by the repository admin.
#
#   environment  branch that may deploy  protection                    WEB_PORT
#   test         develop                 none (automatic after merge)  8081
#   acceptance   release/*               none (automatic after push)   8082
#   production   main                    manual approval by a reviewer 8083
#   backup       develop                 none (nightly backup + monthly DR test must not wait)
#
# Per environment it also sets:
#   secret   MSSQL_SA_PASSWORD   random, strong; only when it does not exist yet (never printed)
#   variable WEB_PORT
# Disaster recovery (docs/DISASTER_RECOVERY.md):
#   secret   BACKUP_KEY   random AES key for the encrypted backups, the SAME key in backup,
#                         acceptance and production. Created once; also written to a file in your
#                         home folder so you can put it in the team's password manager - without
#                         that offline copy, backups cannot be decrypted if GitHub is unavailable.
# Optional, to deploy to a real server instead of the GitHub runner (see docs/CI_CD.md):
#   variables DEPLOY_HOST, DEPLOY_USER, DEPLOY_KNOWN_HOSTS, APP_URL and secret DEPLOY_SSH_KEY,
#   e.g. gh variable set DEPLOY_HOST --env test --body test.vanroey.example
#
# Requires: GitHub CLI (gh auth login as repository admin), openssl.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/008_setup_environments.sh <reviewer> [<reviewer> ...]
#   e.g. sh scripts/008_setup_environments.sh alice bob     (GitHub usernames, max 6)
# Reviewers approve production deployments; nobody can approve their own deployment.
# Environment: REPO=owner/repo to override the repository. Safe to run again.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in first with: gh auth login"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl not found."; exit 1; }

[ $# -ge 1 ] || { echo "Usage: sh scripts/008_setup_environments.sh <reviewer> [<reviewer> ...]"; exit 1; }

repo=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}
[ -n "$repo" ] || { echo "Could not determine the repository. Set REPO=owner/repo"; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------- Reviewers for production ----------
reviewers=""
for login in "$@"; do
  id=$(gh api "users/$login" --jq .id 2>/dev/null) || { echo "Unknown GitHub user: $login"; exit 1; }
  reviewers="$reviewers{\"type\":\"User\",\"id\":$id},"
done
reviewers="[${reviewers%,}]"

echo "Repository: $repo"
echo "Production reviewers: $*"
echo ""

# setup_env <environment> <branch pattern> <web port> <reviewers json or empty>
setup_env() {
  name=$1; branch=$2; port=$3; rev=$4

  if [ -n "$rev" ]; then
    protection="\"reviewers\": $rev, \"prevent_self_review\": true,"
  else
    protection=""
  fi
  cat > "$tmp/env.json" <<EOF
{
  $protection
  "wait_timer": 0,
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
EOF
  gh api -X PUT "repos/$repo/environments/$name" --input "$tmp/env.json" >/dev/null \
    || { echo "FAILED   environment $name"; exit 1; }
  echo "OK       environment $name$( [ -n "$rev" ] && echo " (manual approval)")"

  # Only this branch may deploy to the environment (also blocks a manual run from another branch)
  existing=$(gh api "repos/$repo/environments/$name/deployment-branch-policies" --jq '.branch_policies[].name' 2>/dev/null)
  if printf '%s\n' "$existing" | grep -qxF "$branch"; then
    echo "OK         only branch '$branch' may deploy (already present)"
  else
    gh api -X POST "repos/$repo/environments/$name/deployment-branch-policies" \
      -f name="$branch" -f type=branch >/dev/null \
      && echo "OK         only branch '$branch' may deploy" \
      || { echo "FAILED     branch policy $branch"; exit 1; }
  fi

  gh variable set WEB_PORT --env "$name" --repo "$repo" --body "$port" >/dev/null \
    && echo "OK         variable WEB_PORT=$port"

  if gh secret list --env "$name" --repo "$repo" 2>/dev/null | grep -q '^MSSQL_SA_PASSWORD'; then
    echo "OK         secret MSSQL_SA_PASSWORD (already present, unchanged)"
  else
    # Upper, lower, digit and symbol for the SQL Server password policy; no ';' or quotes
    pw="Vr-$(openssl rand -hex 12)-$(openssl rand -hex 4 | tr 'a-f' 'A-F')"
    printf '%s' "$pw" | gh secret set MSSQL_SA_PASSWORD --env "$name" --repo "$repo" >/dev/null \
      && echo "OK         secret MSSQL_SA_PASSWORD (random, not shown)"
  fi
}

setup_env test       develop    8081 ""
setup_env acceptance 'release/*' 8082 ""
setup_env production main       8083 "$reviewers"

# ---------- Disaster recovery: 'backup' environment + BACKUP_KEY ----------
printf '%s' '{ "wait_timer": 0, "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }' > "$tmp/env.json"
gh api -X PUT "repos/$repo/environments/backup" --input "$tmp/env.json" >/dev/null || { echo "FAILED   environment backup"; exit 1; }
if ! gh api "repos/$repo/environments/backup/deployment-branch-policies" --jq '.branch_policies[].name' 2>/dev/null | grep -qx develop; then
  gh api -X POST "repos/$repo/environments/backup/deployment-branch-policies" -f name=develop -f type=branch >/dev/null \
    || { echo "FAILED   branch policy backup"; exit 1; }
fi
echo "OK       environment backup (backups and DR test, only from develop, no approval)"

has_key() { gh secret list --env "$1" --repo "$repo" 2>/dev/null | grep -q '^BACKUP_KEY'; }
if has_key backup; then
  echo "OK         secret BACKUP_KEY (already present, unchanged)"
  for e in acceptance production; do
    has_key "$e" || echo "WARNING    $e has no BACKUP_KEY: set the same key from the password manager:
             gh secret set BACKUP_KEY --env $e --repo $repo"
  done
else
  key_file="$HOME/projectcontrol-backup-key.txt"
  key=$(openssl rand -base64 48 | tr -d '\n')
  for e in backup acceptance production; do
    printf '%s' "$key" | gh secret set BACKUP_KEY --env "$e" --repo "$repo" >/dev/null \
      || { echo "FAILED     secret BACKUP_KEY in $e"; exit 1; }
  done
  ( umask 077; printf '%s\n' "$key" > "$key_file" )
  unset key
  echo "OK         secret BACKUP_KEY in backup, acceptance and production (random, not shown)"
  echo ""
  echo "IMPORTANT  The key was also written to $key_file"
  echo "           Store it in the team's password manager NOW, then delete the file."
  echo "           Without it, the backups cannot be decrypted when GitHub itself is the disaster."
fi
echo "           For backups also set in 'backup': DEPLOY_SSH_KEY (secret), DEPLOY_HOST (or DEPLOY_HOST_ACC /"
echo "           DEPLOY_HOST_PROD), DEPLOY_KNOWN_HOSTS and DEPLOY_USER (variables) - see DISASTER_RECOVERY.md."

echo ""
echo "Done. Check on GitHub: Settings -> Environments."
echo "Without DEPLOY_HOST the CD workflows deploy on the GitHub runner (temporary environment)."
