#!/bin/sh
# Deploys ProjectControl to one DTAP environment with Docker Compose.
# Used by the CD workflows (cd-test.yml, cd-acceptance.yml, cd-production.yml) and locally.
#
#   dev   your own computer, images built from source       deploy/compose.dev.yml
#   test  after every merge on develop                       deploy/compose.test.yml
#   acc   after every push on release/*                      deploy/compose.acc.yml
#   prod  after a merge on main + manual approval            deploy/compose.prod.yml
#
# Every environment = deploy/compose.yml + deploy/compose.<env>.yml + its settings.
# Build once, deploy everywhere: test, acceptance and production never build. They run the
# images CI built, given as API_IMAGE / WEB_IMAGE (digests). When those are not set, the images
# of the checked-out commit are looked up in the registry (scripts/014_images.sh resolve).
# Settings come from deploy/env/<env>.env (copy the .example, never commit it) or, in CI,
# from the environment variables of the GitHub environment.
#
# Where it runs:
#   DEPLOY_HOST not set  -> the local Docker (your computer, or the GitHub runner)
#   DEPLOY_HOST set      -> the Docker on that server over SSH (DEPLOY_USER, default 'deploy');
#                           the SSH key must already be loaded (the CD workflow does this)
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/012_deploy.sh <dev|test|acc|prod> [up|down|reset|ps|logs]
#     up     (default) pull or build, start, wait until healthy, run the smoke test
#     down   stop the environment, keep the database
#     reset  stop the environment AND delete its database (not allowed for prod)
#     ps     show the containers
#     logs   show the last log lines

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

env=$1
action=${2:-up}

case "$env" in
  dev|test|acc|prod) ;;
  *) echo "Usage: sh scripts/012_deploy.sh <dev|test|acc|prod> [up|down|reset|ps|logs]"; exit 2 ;;
esac

command -v docker >/dev/null 2>&1 || { echo "Docker is not installed."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 ('docker compose') is required."; exit 1; }

# ---------- Settings ----------
env_file="deploy/env/$env.env"
if [ -f "$env_file" ]; then
  echo "Settings:  $env_file"
  set -a
  # shellcheck disable=SC1090
  . "./$env_file"
  set +a
elif [ -z "$CI" ]; then
  echo "Settings file $env_file not found. Create it first:"
  echo "  cp $env_file.example $env_file    (and fill in a password)"
  exit 1
else
  echo "Settings:  environment variables of the GitHub environment"
fi

if [ "$action" = "up" ]; then
  case "$MSSQL_SA_PASSWORD" in
    ""|change-me) echo "MSSQL_SA_PASSWORD is not set (or still 'change-me')."; exit 1 ;;
  esac
fi

if [ "$env" != "dev" ] && [ -z "$API_IMAGE$WEB_IMAGE" ]; then
  if images=$(sh scripts/014_images.sh resolve); then
    eval "$(printf '%s\n' "$images" | grep -E '^(API|WEB)_(IMAGE|TAG)=')"
    export API_IMAGE WEB_IMAGE API_TAG WEB_TAG
  elif [ "$action" = "up" ]; then
    echo "No images found for this commit: CI builds them on the Pull Request / merge."
    exit 1
  else
    export API_IMAGE=unused WEB_IMAGE=unused   # down/ps/logs do not need the images
  fi
fi

# Traceability: shown on /version and checked by the smoke test
export DEPLOY_ENV="$env"
export DEPLOY_COMMIT="${DEPLOY_COMMIT:-$(git rev-parse HEAD)}"
if [ "$env" = "dev" ]; then
  export API_TAG="${API_TAG:-dev}" WEB_TAG="${WEB_TAG:-dev}"
fi
export EXPECT_COMMIT="$DEPLOY_COMMIT"

if [ -n "$DEPLOY_HOST" ]; then
  export DOCKER_HOST="ssh://${DEPLOY_USER:-deploy}@$DEPLOY_HOST"
  target=$DEPLOY_HOST
else
  target=localhost
fi
url=${APP_URL:-http://$target:${WEB_PORT}}

echo "Environment: $env    Action: $action    Docker: ${DOCKER_HOST:-local}"
echo "Commit:      $DEPLOY_COMMIT"
[ "$env" != "dev" ] && printf 'Images:      %s (%s)\n             %s (%s)\n' "$API_IMAGE" "$API_TAG" "$WEB_IMAGE" "$WEB_TAG"
echo ""

compose() {
  docker compose -f deploy/compose.yml -f "deploy/compose.$env.yml" "$@"
}

show_logs() {
  echo ""
  echo "=============== Last log lines"
  compose ps
  compose logs --tail 60 api web
}

case "$action" in
  up)
    if [ "$env" = "dev" ]; then
      compose build || exit 1      # only dev builds, from your working copy
    else
      compose pull --quiet || { echo "Could not pull the images (logged in to the registry?)."; exit 1; }
    fi

    # --wait: returns only when every container with a health check is healthy
    if ! compose up -d --remove-orphans --wait --wait-timeout 300; then
      echo "FAILED: the containers did not become healthy."
      show_logs
      exit 1
    fi

    if ! sh scripts/013_smoke_test.sh "$url"; then
      show_logs
      exit 1
    fi

    echo ""
    echo "Deployed $env: $url"
    ;;
  down)
    compose down --remove-orphans
    ;;
  reset)
    if [ "$env" = "prod" ]; then
      echo "Refused: 'reset' deletes the database and is never allowed for production."
      exit 1
    fi
    compose down --remove-orphans --volumes
    ;;
  ps)
    compose ps
    ;;
  logs)
    compose logs --tail 200
    ;;
  *)
    echo "Unknown action '$action'. Use up, down, reset, ps or logs."
    exit 2
    ;;
esac
