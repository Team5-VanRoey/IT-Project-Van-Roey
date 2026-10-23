#!/bin/sh
# Disaster recovery TEST: proves that a backup can really be restored (docs/DISASTER_RECOVERY.md).
# A backup that was never restored is only a hope. Run monthly by .github/workflows/dr-test.yml
# on the latest production backup, and by hand after changing the backup or restore scripts.
#
#   1. starts a THROW-AWAY environment on this machine (project projectcontrol-drtest, own
#      volumes, random password; real servers and deploy/env files are never used)
#   2. uses the images of the application version that belongs to the backup (backup metadata),
#      or the images tagged with the source environment (e.g. 'prod')
#   3. restores the backup with 020_restore.sh, starts API + frontend, runs the smoke test
#   4. reports the measured recovery time (compare with the RTO) and removes everything
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/021_dr_test.sh <backup file | latest> [source env, default prod]
# Environment: BACKUP_KEY (for encrypted backups), BACKUP_DIR, REGISTRY (default
#   ghcr.io/team5-vanroey), DR_PORT (default 18099), KEEP=1 (do not remove the environment)

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository." >&2; exit 1; }
. scripts/dtap_common.sh

backup=$1; from=${2:-prod}
[ -n "$backup" ] || { echo "Usage: sh scripts/021_dr_test.sh <backup file | latest> [source env]" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "Docker is not installed." >&2; exit 1; }

dir=${BACKUP_DIR:-deploy/backups/$from}
if [ "$backup" = "latest" ]; then
  [ -f "$dir/LATEST" ] || { echo "No backups in $dir." >&2; exit 1; }
  backup="$dir/$(cat "$dir/LATEST")"
fi
[ -f "$backup" ] || { echo "Backup file not found: $backup" >&2; exit 1; }

# ---------- Throw-away environment: never a real server ----------
export DTAP_NO_ENV_FILE=1 COMPOSE_PROJECT=projectcontrol-drtest
unset DEPLOY_HOST DOCKER_HOST DEPLOY_TARGET
export ASPNETCORE_ENVIRONMENT=Test MSSQL_PID=Developer MIGRATE_ON_STARTUP=false
export WEB_PORT=${DR_PORT:-18099}
MSSQL_SA_PASSWORD="Dr-$(openssl rand -hex 12)-X1"; export MSSQL_SA_PASSWORD

# Images of the version that belongs to this backup
registry=${REGISTRY:-ghcr.io/team5-vanroey}
meta="$(dirname "$backup")/$(basename "$backup" | sed 's/\.bak\.gz.*$//').json"
api_version=$(sed -n 's/.*"api_version": *"\([^"]*\)".*/\1/p' "$meta" 2>/dev/null)
web_version=$(sed -n 's/.*"web_version": *"\([^"]*\)".*/\1/p' "$meta" 2>/dev/null)
case "$api_version" in ""|unknown|dev) api_version=$from ;; esac
case "$web_version" in ""|unknown|dev) web_version=$from ;; esac
export API_IMAGE="${API_IMAGE:-$registry/projectcontrol-api:$api_version}"
export WEB_IMAGE="${WEB_IMAGE:-$registry/projectcontrol-web:$web_version}"
export DEPLOY_ENV=drtest DEPLOY_COMMIT=drtest API_TAG="$api_version" WEB_TAG="$web_version"

cleanup() {
  if [ -n "$KEEP" ]; then
    echo "KEEP=1: the environment is still running on http://localhost:$WEB_PORT"
    echo "Remove it with: docker compose -p $COMPOSE_PROJECT -f deploy/compose.yml -f deploy/compose.test.yml down -v"
  else
    dtap_compose test down -v --remove-orphans >/dev/null 2>&1
  fi
}
trap cleanup EXIT

echo "=============== DR test: restore $(basename "$backup") into a throw-away environment"
echo "Images: $API_IMAGE"
echo "        $WEB_IMAGE"
start=$(date +%s)

dtap_compose test pull --quiet || { echo "FAILED: cannot pull the images." >&2; exit 1; }
dtap_compose test up -d --wait --wait-timeout 300 db || { echo "FAILED: database did not start." >&2; exit 1; }

SKIP_SAFETY_BACKUP=1 NO_SMOKE=1 sh scripts/020_restore.sh test "$backup" || { echo "FAILED: restore" >&2; exit 1; }

dtap_compose test up -d --wait --wait-timeout 300 api web || { echo "FAILED: API/frontend did not start." >&2; dtap_compose test logs --tail 50 api; exit 1; }
sh scripts/013_smoke_test.sh "http://localhost:$WEB_PORT" || { dtap_compose test logs --tail 50 api; exit 1; }

seconds=$(( $(date +%s) - start ))
result="DR test PASSED: $(basename "$backup") restored and working in $((seconds / 60)) min $((seconds % 60)) s"
echo ""
echo "$result"
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  {
    echo "### $result"
    echo "- Backup: \`$(basename "$backup")\` (from $from)"
    echo "- Images: \`$API_IMAGE\`, \`$WEB_IMAGE\`"
    echo "- Measured recovery time: ${seconds}s (RTO: see docs/DISASTER_RECOVERY.md)"
  } >> "$GITHUB_STEP_SUMMARY"
fi
