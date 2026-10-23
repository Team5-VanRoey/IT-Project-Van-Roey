#!/bin/sh
# Disaster recovery: restores the database of one DTAP environment (docs/DISASTER_RECOVERY.md).
# Normally started through .github/workflows/restore.yml (production needs a reviewer's approval).
#
# Docker Compose environments - from a backup made by 019_backup.sh:
#   sh scripts/020_restore.sh <env> <backup file | latest>
#   1. checks the SHA-256 checksum, decrypts (BACKUP_KEY) and unpacks the backup
#   2. makes a SAFETY BACKUP of the current database first (so the restore itself can be undone)
#   3. stops the API, restores the database (WITH REPLACE, CHECKSUM), starts the API again
#   4. shows the row counts, the application version that belongs to the backup, and runs the
#      smoke test
# Azure environments (DEPLOY_TARGET=azure) - point-in-time restore of Azure SQL:
#   sh scripts/020_restore.sh <env> --time 2026-10-23T08:00:00Z
#   restores to a new database, swaps it in under the original name (the old one is kept as
#   <db>-replaced-<time>), restarts the API and runs the smoke test
#
# acceptance and production: the restore must be confirmed, interactively or with CONFIRM=<env>.
# Environment: BACKUP_DIR (default deploy/backups/<env>), BACKUP_KEY, SKIP_SAFETY_BACKUP=1,
#   NO_SMOKE=1, DEPLOY_HOST/DEPLOY_USER (remote Docker over SSH)

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository." >&2; exit 1; }
. scripts/dtap_common.sh

env=$1; source=$2; when=$3
case "$env" in
  dev|test|acc|prod) ;;
  *) echo "Usage: sh scripts/020_restore.sh <env> <backup file | latest>  or  <env> --time <ISO-8601 UTC>" >&2; exit 2 ;;
esac
[ -n "$source" ] || { echo "Which backup? Give a file, 'latest', or --time <time> (Azure)." >&2; exit 2; }

dtap_load "$env"

# ---------- Confirmation for acceptance and production ----------
case "$env" in
  acc|prod)
    if [ "$CONFIRM" != "$env" ]; then
      if [ -t 0 ]; then
        printf 'This REPLACES the %s database. Type "%s" to continue: ' "$env" "$env"
        read -r answer
        [ "$answer" = "$env" ] || { echo "Cancelled."; exit 1; }
      else
        echo "Refused: set CONFIRM=$env to restore the $env database." >&2
        exit 1
      fi
    fi ;;
esac

smoke() {  # smoke <url>
  [ -n "$NO_SMOKE" ] && return 0
  sh scripts/013_smoke_test.sh "$1"
}

# ---------- Azure: point-in-time restore ----------
if dtap_is_azure; then
  [ "$source" = "--time" ] && [ -n "$when" ] || { echo "Azure: use --time <yyyy-mm-ddThh:mm:ssZ>." >&2; exit 2; }
  command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) not found." >&2; exit 1; }
  rg=${AZURE_RESOURCE_GROUP:-rg-projectcontrol-$env}
  server=$(az sql server list -g "$rg" --query '[0].name' -o tsv) || exit 1
  [ -n "$server" ] || { echo "No SQL server in $rg." >&2; exit 1; }
  stamp=$(date -u +%Y%m%d%H%M%S)
  restored="$DB_NAME-restored-$stamp"
  replaced="$DB_NAME-replaced-$stamp"

  echo "=============== Point-in-time restore of $DB_NAME to $when"
  az sql db restore -g "$rg" -s "$server" -n "$DB_NAME" --dest-name "$restored" --time "$when" \
    --edition GeneralPurpose --family Gen5 --capacity 2 --compute-model Serverless >/dev/null \
    || { echo "FAILED: restore (is $when within the retention period? see 019_backup.sh $env)" >&2; exit 1; }
  echo "=============== Swap: $DB_NAME -> $replaced, $restored -> $DB_NAME"
  az sql db rename -g "$rg" -s "$server" -n "$DB_NAME" --new-name "$replaced" >/dev/null || exit 1
  az sql db rename -g "$rg" -s "$server" -n "$restored" --new-name "$DB_NAME" >/dev/null \
    || { echo "FAILED: rename; putting the original back" >&2
         az sql db rename -g "$rg" -s "$server" -n "$replaced" --new-name "$DB_NAME" >/dev/null; exit 1; }

  api="pc-$env-api"
  for rev in $(az containerapp revision list -g "$rg" -n "$api" --query "[?properties.active].name" -o tsv); do
    az containerapp revision restart -g "$rg" -n "$api" --revision "$rev" >/dev/null
  done
  url=${APP_URL:-https://$(az containerapp show -g "$rg" -n "pc-$env-web" --query properties.configuration.ingress.fqdn -o tsv)}
  RETRIES=${RETRIES:-60} smoke "$url" || exit 1
  echo ""
  echo "Restored $env to $when. The previous database is kept as $replaced:"
  echo "  check the data, then delete it (costs money):  az sql db delete -g $rg -s $server -n $replaced --yes"
  echo "Note: a restored database is billed (the free offer only applies to newly created databases)."
  exit 0
fi

# ---------- Docker Compose: restore from a backup file ----------
command -v docker >/dev/null 2>&1 || { echo "Docker is not installed." >&2; exit 1; }
dir=${BACKUP_DIR:-deploy/backups/$env}
if [ "$source" = "latest" ]; then
  [ -f "$dir/LATEST" ] || { echo "No backups in $dir." >&2; exit 1; }
  source="$dir/$(cat "$dir/LATEST")"
fi
[ -f "$source" ] || { echo "Backup file not found: $source" >&2; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
src_dir=$(dirname "$source"); src_name=$(basename "$source")

echo "=============== Check and unpack $src_name"
if [ -f "$source.sha256" ]; then
  (cd "$src_dir" && sha256sum -c "$src_name.sha256" >/dev/null) || { echo "FAILED: checksum does not match, the file is damaged." >&2; exit 1; }
  echo "Checksum OK"
else
  echo "WARNING: no checksum file next to the backup."
fi
case "$src_name" in
  *.enc)
    [ -n "$BACKUP_KEY" ] || { echo "The backup is encrypted: set BACKUP_KEY." >&2; exit 1; }
    dtap_decrypt "$source" "$tmp/backup.bak.gz" || { echo "FAILED: decryption (wrong BACKUP_KEY?)" >&2; exit 1; } ;;
  *.gz) cp "$source" "$tmp/backup.bak.gz" ;;
  *.bak) gzip -c "$source" > "$tmp/backup.bak.gz" ;;
  *) echo "Unknown backup format: $src_name" >&2; exit 1 ;;
esac
gunzip "$tmp/backup.bak.gz" || exit 1

meta="$src_dir/$(printf '%s' "$src_name" | sed 's/\.bak\.gz.*$//').json"

dtap_compose "$env" ps --status running db 2>/dev/null | grep -q db \
  || { echo "The database container of '$env' is not running${DEPLOY_HOST:+ on $DEPLOY_HOST}." >&2; exit 1; }

# 2. Safety backup of what is there now
exists=$(dtap_sql "$env" "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'$DB_NAME') IS NULL THEN 0 ELSE 1 END" | tr -d '[:space:]')
if [ "$exists" = "1" ] && [ -z "$SKIP_SAFETY_BACKUP" ]; then
  echo "=============== Safety backup of the current database"
  BACKUP_DIR="$dir/pre-restore" BACKUP_KEEP=5 sh scripts/019_backup.sh "$env" >/dev/null \
    || { echo "FAILED: safety backup; nothing was changed." >&2; exit 1; }
  echo "Saved in $dir/pre-restore"
fi

# 3. Restore
inside=/var/opt/mssql/backup/restore.bak
echo "=============== Restore into $env ($DB_NAME)"
api_running=$(dtap_compose "$env" ps --status running api 2>/dev/null | grep -c api)
[ "$api_running" -gt 0 ] && dtap_compose "$env" stop api >/dev/null
dtap_compose "$env" exec -T db mkdir -p /var/opt/mssql/backup || exit 1
dtap_compose "$env" cp "$tmp/backup.bak" "db:$inside" || exit 1

dtap_sql "$env" "IF DB_ID(N'$DB_NAME') IS NOT NULL ALTER DATABASE [$DB_NAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [$DB_NAME] FROM DISK = N'$inside' WITH REPLACE, CHECKSUM, RECOVERY;
ALTER DATABASE [$DB_NAME] SET MULTI_USER;"
status=$?
dtap_compose "$env" exec -T db rm -f "$inside"
[ "$api_running" -gt 0 ] && dtap_compose "$env" start api >/dev/null
[ "$status" -eq 0 ] || { echo "FAILED: RESTORE DATABASE (the safety backup is in $dir/pre-restore)." >&2; exit 1; }

# 4. Result
echo "=============== Restored"
dtap_sql "$env" "SET NOCOUNT ON; SELECT 'Projects: ' + CAST(COUNT(*) AS varchar) FROM [$DB_NAME].dbo.Projects;
SELECT 'Milestones: ' + CAST(COUNT(*) AS varchar) FROM [$DB_NAME].dbo.Milestones;" || true
if [ -f "$meta" ]; then
  echo "This backup belongs to application version:"
  sed -n 's/^ *"\(commit\|api_version\|web_version\)": */  \1: /p' "$meta" | tr -d '",'
  echo "If another version runs now, redeploy that commit: Actions -> Redeploy."
fi

if [ "$api_running" -gt 0 ]; then
  target=${DEPLOY_HOST:-localhost}
  RETRIES=${RETRIES:-40} smoke "${APP_URL:-http://$target:$WEB_PORT}" || exit 1
fi
echo "OK: $env restored from $src_name"
