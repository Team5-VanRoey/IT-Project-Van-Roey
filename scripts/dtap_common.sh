# Shared helpers for the disaster recovery scripts (019_backup.sh, 020_restore.sh, 021_dr_test.sh).
# Sourced, not run. Same conventions as 012_deploy.sh: one DTAP environment = deploy/compose.yml +
# deploy/compose.<env>.yml, settings from deploy/env/<env>.env or (in CI) the environment variables.

# dtap_load <env>: loads the settings and points Docker to DEPLOY_HOST when set.
# DTAP_NO_ENV_FILE=1 (used by 021_dr_test.sh): ignore deploy/env/<env>.env and DEPLOY_HOST, so a
# throw-away environment on this machine can never touch a real server.
dtap_load() {
  _env_file="deploy/env/$1.env"
  if [ -n "$DTAP_NO_ENV_FILE" ]; then
    unset DEPLOY_HOST DOCKER_HOST
  elif [ -f "$_env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "./$_env_file"
    set +a
  fi
  if [ -n "$DEPLOY_HOST" ] && [ -z "$DTAP_NO_ENV_FILE" ]; then
    export DOCKER_HOST="ssh://${DEPLOY_USER:-deploy}@$DEPLOY_HOST"
  fi
  # The compose files require these for interpolation. Backup and restore only talk to the
  # running containers (which keep their own values), so placeholders are enough here.
  export API_IMAGE="${API_IMAGE:-unused}" WEB_IMAGE="${WEB_IMAGE:-unused}"
  export WEB_PORT="${WEB_PORT:-8080}" MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:-unused-by-backup}"
  DB_NAME=${DB_NAME:-ProjectControl}
}

# dtap_compose <env> <compose arguments...>; COMPOSE_PROJECT overrides the project name
dtap_compose() {
  _e=$1; shift
  if [ -n "$COMPOSE_PROJECT" ]; then
    docker compose -p "$COMPOSE_PROJECT" -f deploy/compose.yml -f "deploy/compose.$_e.yml" "$@"
  else
    docker compose -f deploy/compose.yml -f "deploy/compose.$_e.yml" "$@"
  fi
}

# dtap_sql <env> <T-SQL>: runs T-SQL in the db container with the container's own sa password
dtap_sql() {
  _e=$1; shift
  # shellcheck disable=SC2016  # $MSSQL_SA_PASSWORD is expanded inside the container
  dtap_compose "$_e" exec -T -e "SQL=$*" db sh -c \
    '/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b -h -1 -W -Q "$SQL"'
}

# dtap_is_azure: true when this environment runs on Azure (DEPLOY_TARGET=azure)
dtap_is_azure() { [ "$DEPLOY_TARGET" = "azure" ]; }

# Backup encryption: AES-256 with a key from BACKUP_KEY (GitHub secret, never in the repo)
dtap_encrypt() { openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_KEY -in "$1" -out "$2"; }
dtap_decrypt() { openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_KEY -in "$1" -out "$2"; }
