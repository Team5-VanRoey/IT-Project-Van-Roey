#!/bin/sh
# Checks your current branch the same way GitHub will check the Pull Request,
# so you see problems before you open the PR.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/004_check_pr.sh                      branch name and commits against develop
#   sh scripts/004_check_pr.sh ../pr-body.md        also the completed PR description
#   sh scripts/004_check_pr.sh ../pr-body.md main   with main as target (release/hotfix)
#
# pr-body.md = a completed copy of .github/pull_request_template.md, kept outside
# the repository. Paste the same text into the PR on GitHub afterwards.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

body_file=${1:-}
base=${2:-develop}

head=$(git symbolic-ref --short HEAD 2>/dev/null) || { echo "You are not on a branch."; exit 1; }

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

echo "Branch:       $head"
echo "Target:       $base"
echo "Commits:      $(printf '%s\n' "$commits" | grep -c .)"

if [ -n "$body_file" ]; then
  [ -f "$body_file" ] || { echo "File '$body_file' not found."; exit 1; }
  echo "Description:  $body_file"
  echo ""
  PR_BODY=$(cat "$body_file") HEAD_REF="$head" BASE_REF="$base" COMMITS="$commits" "$py" scripts/check_pr.py
else
  echo "Description:  not checked (pass a file to check it too)"
  echo ""
  SKIP_BODY=1 HEAD_REF="$head" BASE_REF="$base" COMMITS="$commits" "$py" scripts/check_pr.py
fi
