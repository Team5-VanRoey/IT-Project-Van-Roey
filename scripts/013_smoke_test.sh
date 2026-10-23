#!/bin/sh
# Smoke test after a deployment: does the release really work end to end?
# Run by scripts/012_deploy.sh after every 'up', and usable on its own.
#
#   1. the frontend returns the app            GET /               -> 200 + <div id="root">
#   2. the API process is healthy              GET /health         -> "Healthy"
#   3. API + database answer through the proxy GET /api/projects   -> 200 + JSON list
#   4. the NEW version is the one serving      GET /version        -> contains EXPECT_COMMIT
#      (only when EXPECT_COMMIT is set; 012_deploy.sh and 016_deploy_azure.sh set it)
#
# Retries for up to RETRIES x 3 seconds (default 40 = 2 minutes), because the API migrates
# the database at startup.
#
# Usage:
#   sh scripts/013_smoke_test.sh http://localhost:8081

url=${1%/}
retries=${RETRIES:-40}

[ -n "$url" ] || { echo "Usage: sh scripts/013_smoke_test.sh <url>"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required."; exit 1; }

echo "=============== Smoke test $url"

# check <description> <path> <expected text>
check() {
  i=1
  while [ "$i" -le "$retries" ]; do
    body=$(curl -fsS --max-time 5 "$url$2" 2>/dev/null) && \
      printf '%s' "$body" | grep -q "$3" && { echo "  OK    $1"; return 0; }
    i=$((i + 1))
    sleep 3
  done
  echo "  FAIL  $1 ($url$2 did not return '$3')"
  return 1
}

status=0
check "frontend serves the app"        "/"             '<div id="root">' || status=1
check "API healthy"                    "/health"       'Healthy'          || status=1
check "API + database through the proxy" "/api/projects" '\['               || status=1
if [ -n "$EXPECT_COMMIT" ]; then
  check "deployed version is live ($(printf '%s' "$EXPECT_COMMIT" | cut -c1-7))" "/version" "\"commit\":\"$EXPECT_COMMIT\"" || status=1
  curl -fsS --max-time 5 "$url/version" 2>/dev/null && echo ""
fi

if [ "$status" -eq 0 ]; then
  echo "Smoke test passed."
else
  echo "Smoke test FAILED."
fi
exit $status
