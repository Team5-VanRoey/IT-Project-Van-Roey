#!/bin/sh
# Checks your current branch the same way GitHub will check the Pull Request,
# so you see problems before you open the PR.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/004_check_pr.sh                      branch name and commits
#   sh scripts/004_check_pr.sh ../pr-body.md        also the completed PR description
#   sh scripts/004_check_pr.sh ../pr-body.md main   with an explicit target branch
# Target defaults to develop; hotfix/*, release/* and develop default to main.
#
# pr-body.md = a completed copy of the PR template for your branch type, kept outside
# the repository. If the file does not exist yet, it is created from the right template:
#   feature/* -> pull_request_template.md, bugfix/* -> PULL_REQUEST_TEMPLATE/bugfix.md,
#   hotfix/*  -> PULL_REQUEST_TEMPLATE/hotfix.md, release/* -> PULL_REQUEST_TEMPLATE/release.md
# Paste the same text into the PR on GitHub afterwards.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }
. scripts/pr_template.sh

body_file=${1:-}

head=$(git symbolic-ref --short HEAD 2>/dev/null) || { echo "You are not on a branch."; exit 1; }
case "$head" in
  hotfix/*|release/*|develop) base=${2:-main} ;;
  *)                          base=${2:-develop} ;;
esac

git fetch -q origin "$base" 2>/dev/null
if git rev-parse -q --verify "origin/$base" >/dev/null; then
  ref="origin/$base"
elif git rev-parse -q --verify "$base" >/dev/null; then
  ref="$base"
else
  echo "Target branch '$base' not found."
  exit 1
fi

commits=$(git log --format=%s "$ref..HEAD")
if [ -z "$commits" ]; then
  echo "Note: '$head' has no commits compared to $ref."
fi

py=""
for p in python3 python; do
  if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then py=$p; break; fi
done
[ -z "$py" ] && { echo "Python 3 is required for this check."; exit 1; }

template=$(pr_template_for "$head")

echo "Branch:       $head"
echo "Target:       $base"
echo "Template:     $template"
echo "Commits:      $(printf '%s\n' "$commits" | grep -c .)"

if [ -n "$body_file" ]; then
  pr_body_create "$body_file" "$head" || exit 0
  echo "Description:  $body_file"
  echo ""
  PR_BODY=$(cat "$body_file") HEAD_REF="$head" BASE_REF="$base" COMMITS="$commits" "$py" scripts/check_pr.py
else
  echo "Description:  not checked (pass a file to check it too)"
  echo ""
  SKIP_BODY=1 HEAD_REF="$head" BASE_REF="$base" COMMITS="$commits" "$py" scripts/check_pr.py
fi