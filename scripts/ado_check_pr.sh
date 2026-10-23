#!/bin/sh
# Azure DevOps version of the "Gitflow & PR template" check (the GitHub version is
# .github/workflows/pr-checks.yml). Reads the Pull Request from the Azure Repos REST API and runs
# the same rules: scripts/check_pr.py (branch name, target branch, commit messages, PR template).
#
# Run by azure-pipelines/ci.yml in PR builds; needs SYSTEM_ACCESSTOKEN and the predefined
# variables of Azure Pipelines. Not meant to be run by hand.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

[ -n "$SYSTEM_PULLREQUEST_PULLREQUESTID" ] || { echo "Not a Pull Request build: nothing to check."; exit 0; }
[ -n "$SYSTEM_ACCESSTOKEN" ] || { echo "SYSTEM_ACCESSTOKEN is not mapped into the step."; exit 1; }

py=""
for p in python3 python; do
  if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then py=$p; break; fi
done
[ -n "$py" ] || { echo "Python 3 is required."; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# URL of the PR in the REST API (project names may contain spaces)
base=$("$py" -c '
import os, urllib.parse as u
print("{}{}/_apis/git/repositories/{}/pullRequests/{}".format(
    os.environ["SYSTEM_COLLECTIONURI"], u.quote(os.environ["SYSTEM_TEAMPROJECT"]),
    os.environ["BUILD_REPOSITORY_ID"], os.environ["SYSTEM_PULLREQUEST_PULLREQUESTID"]))')

get() {
  curl -fsS -H "Authorization: Bearer $SYSTEM_ACCESSTOKEN" "$base$1" -o "$2" \
    || { echo "Could not read the Pull Request from the Azure DevOps API ($1)."; exit 1; }
}
get "?api-version=7.1" "$tmp/pr.json"
get "/commits?api-version=7.1&\$top=500" "$tmp/commits.json"

# Export the PR fields in the format check_pr.py expects
"$py" - "$tmp" <<'EOF' || exit 1
import json, sys
tmp = sys.argv[1]
pr = json.load(open(f"{tmp}/pr.json", encoding="utf-8"))
commits = json.load(open(f"{tmp}/commits.json", encoding="utf-8")).get("value", [])
strip = lambda ref: ref.replace("refs/heads/", "", 1)
open(f"{tmp}/head", "w").write(strip(pr["sourceRefName"]))
open(f"{tmp}/base", "w").write(strip(pr["targetRefName"]))
open(f"{tmp}/body", "w", encoding="utf-8").write(pr.get("description") or "")
open(f"{tmp}/commits", "w", encoding="utf-8").write(
    "\n".join((c.get("comment") or "").split("\n")[0] for c in commits))
EOF

echo "PR #$SYSTEM_PULLREQUEST_PULLREQUESTID: $(cat "$tmp/head") -> $(cat "$tmp/base")"
PR_BODY=$(cat "$tmp/body") HEAD_REF=$(cat "$tmp/head") BASE_REF=$(cat "$tmp/base") \
  COMMITS=$(cat "$tmp/commits") "$py" scripts/check_pr.py
