#!/bin/sh
# Scans the repository for secrets (Definition of Done, item 2).
#   1. Full Git history with gitleaks (same scan as the "Secret scan" workflow).
#   2. Open GitHub secret scanning alerts (if the GitHub CLI is available).
#
# gitleaks is used when installed (https://github.com/gitleaks/gitleaks#installing),
# otherwise through Docker. Without either, a basic pattern search is used.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/005_scan_secrets.sh

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

status=0

echo "== 1. Git history scan"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --redact --no-banner || status=1
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.21.2 \
    detect --source /repo --redact --no-banner || status=1
else
  echo "gitleaks and Docker not found: basic pattern search instead."
  echo "(Install gitleaks for a complete scan; the 'Secret scan' check on GitHub always runs it.)"
  # Our own Gitflow files mention words like 'secret' and 'token' on purpose
  hits=$(git log -p --all -- . ':!docs' ':!scripts' ':!.github' ':!.githooks' \
    | grep -inE "(password|passwd|api[_-]?key|secret|token)[A-Za-z_]* *[=:]|BEGIN .*PRIVATE KEY" \
    | head -20)
  if [ -n "$hits" ]; then
    echo "Possible secrets found:"
    echo "$hits"
    status=1
  else
    echo "No leaks found."
  fi
fi

echo ""
echo "== 2. GitHub secret scanning alerts"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if alerts=$(gh api "repos/{owner}/{repo}/secret-scanning/alerts?state=open" --jq length 2>/dev/null); then
    echo "Open alerts: $alerts"
    [ "$alerts" -eq 0 ] || status=1
  else
    echo "Could not read alerts (secret scanning off, or no admin rights)."
    echo "Turn it on with: sh scripts/001_setup_github.sh"
  fi
else
  echo "Skipped: GitHub CLI not installed or not signed in."
fi

echo ""
if [ "$status" -eq 0 ]; then
  echo "RESULT: no secrets found."
else
  echo "RESULT: possible secrets found. Revoke them first: removing the commit is not enough."
fi
exit $status
