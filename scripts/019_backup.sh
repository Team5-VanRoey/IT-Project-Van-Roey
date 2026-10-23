#!/bin/sh
# Disaster recovery: backs up the database of one DTAP environment (docs/DISASTER_RECOVERY.md).
# Run daily by .github/workflows/backup.yml for acceptance and production, and by hand before
# risky work (e.g. a migration that drops data).
#
# Docker Compose environments:
#   1. full SQL Server backup inside the db container (WITH CHECKSUM, then RESTORE VERIFYONLY)
#   2. copied OFF the server to BACKUP_DIR (the machine running this script), compressed (gzip)
#   3. encrypted with AES-256 when BACKUP_KEY is set (always in CI), plus a SHA-256 checksum
#   4. metadata: environment, time and the application version that was running (commit +
#      image versions), so a restore knows which release matches this database schema
#   5. only the newest BACKUP_KEEP backups are kept (default 14)
# Azure environments (DEPLOY_TARGET=azure): Azure SQL makes automatic backups with
# point-in-time restore; this script shows the earliest restore point (needs 'az login').
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/019_backup.sh <dev|test|acc|prod>
# Environment: BACKUP_DIR (default deploy/backups/<env>), BACKUP_KEEP (default 14),
#   BACKUP_KEY (encryption key; required in CI), DEPLOY_HOST/DEPLOY_USER (remote Docker over SSH)
# Prints the path of the backup file on the last line.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository." >&2; exit 1; }
. scripts/dtap_common.sh

env=$1
case "$env" in
  dev|test|acc|prod) ;;
  *) echo "Usage: sh scripts/019_backup.sh <dev|test|acc|prod>" >&2; exit 2 ;;
esac

dtap_load "$env"

# ---------- Azure: automatic backups ----------
if dtap_is_azure; then
  rg=${AZURE_RESOURCE_GROUP:-rg-projectcontrol-$env}
  server=$(az sql server list -g "$rg" --query '[0].name' -o tsv 2>/dev/null) \
    || { echo "Cannot read the SQL server in $rg (az login?)." >&2; exit 1; }
  earliest=$(az sql db show -g "$rg" -s "$server" -n "$DB_NAME" --query earliestRestoreDate -o tsv) || exit 1
  echo "Azure SQL makes automatic backups of $DB_NAME ($server)."
  echo "Point-in-time restore is possible from $earliest until a few minutes ago:"
  echo "  sh scripts/020_restore.sh $env --time <yyyy-mm-ddThh:mm:ssZ>"
  exit 0
fi

# ---------- Docker Compose ----------
command -v docker >/dev/null 2>&1 || { echo "Docker is not installed." >&2; exit 1; }
if [ -n "$CI" ] && [ -z "$BACKUP_KEY" ]; then
  echo "BACKUP_KEY is not set: CI never stores unencrypted backups." >&2
  exit 1
fi

dir=${BACKUP_DIR:-deploy/backups/$env}
keep=${BACKUP_KEEP:-14}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
name="projectcontrol-$env-$stamp"
inside="/var/opt/mssql/backup/$name.bak"
mkdir -p "$dir" || exit 1

echo "=============== Backup $env ($DB_NAME) -> $dir"
dtap_compose "$env" ps --status running db 2>/dev/null | grep -q db \
  || { echo "The database container of '$env' is not running${DEPLOY_HOST:+ on $DEPLOY_HOST}." >&2; exit 1; }

dtap_compose "$env" exec -T db mkdir -p /var/opt/mssql/backup || exit 1
dtap_sql "$env" "BACKUP DATABASE [$DB_NAME] TO DISK = N'$inside' WITH FORMAT, INIT, CHECKSUM, NAME = N'$name'" \
  || { echo "FAILED: BACKUP DATABASE" >&2; exit 1; }
dtap_sql "$env" "RESTORE VERIFYONLY FROM DISK = N'$inside' WITH CHECKSUM" \
  || { echo "FAILED: the backup file did not verify" >&2; exit 1; }

# Copy it off the server, then remove it from the container (it would fill the data volume)
dtap_compose "$env" cp "db:$inside" "$dir/$name.bak" || { echo "FAILED: copy the backup off the server" >&2; exit 1; }
dtap_compose "$env" exec -T db rm -f "$inside"

gzip -9 "$dir/$name.bak" || exit 1
file="$dir/$name.bak.gz"

# Which application version belongs to this database (schema)?
version=$(dtap_compose "$env" exec -T web sh -c 'printf "%s %s %s" "$DEPLOY_COMMIT" "$API_VERSION" "$WEB_VERSION"' 2>/dev/null)
set -- $version
cat > "$dir/$name.json" <<EOF
{
  "environment": "$env",
  "database": "$DB_NAME",
  "created_utc": "$stamp",
  "commit": "${1:-unknown}",
  "api_version": "${2:-unknown}",
  "web_version": "${3:-unknown}"
}
EOF

if [ -n "$BACKUP_KEY" ]; then
  dtap_encrypt "$file" "$file.enc" || { echo "FAILED: encryption" >&2; exit 1; }
  rm -f "$file"
  file="$file.enc"
else
  echo "WARNING: BACKUP_KEY not set, the backup is NOT encrypted (fine for dev, never for acc/prod)."
fi

(cd "$dir" && sha256sum "$(basename "$file")" > "$(basename "$file").sha256") || exit 1
printf '%s\n' "$(basename "$file")" > "$dir/LATEST"

# Retention: keep the newest $keep backups
for f in "$dir"/projectcontrol-"$env"-*.bak.gz "$dir"/projectcontrol-"$env"-*.bak.gz.enc; do
  [ -f "$f" ] && basename "$f"
done | sort -r | tail -n +"$((keep + 1))" |
  while read -r old; do
    base=${old%.bak.gz*}
    rm -f "$dir/$old" "$dir/$old.sha256" "$dir/$base.json"
    echo "Removed old backup $old"
  done

size=$(du -h "$file" | cut -f1)
echo "OK: $file ($size), version ${1:-unknown}"
echo "$file"
