#!/bin/sh
# Runs all checks and opens the Pull Request for the current branch, in DoD order:
#   1. Secret scan            (DoD 2)  -> scripts/005_scan_secrets.sh
#   2. PR check               (DoD 4)  -> scripts/004_check_pr.sh
#   3. Push the branch
#   4. Open the PR, or show the existing one
#   5. Wait for the GitHub checks (DoD 3) and show which ones are required
#
# Requires the GitHub CLI (https://cli.github.com), signed in with `gh auth login`.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/006_open_pr.sh <pr-body.md> "<title>" [target]
# Example:
#   sh scripts/006_open_pr.sh ../pr-body-IT2627T05-181.md "Set up Gitflow and PR process"
#   -> PR title "IT2627T05-181: Set up Gitflow and PR process", target develop

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

body_file=$1
title=$2
base=${3:-develop}

if [ -z "$body_file" ] || [ -z "$title" ]; then
  echo "Usage: sh scripts/006_open_pr.sh <pr-body.md> \"<title>\" [target]"
  exit 1
fi
[ -f "$body_file" ] || { echo "File '$body_file' not found."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in first with: gh auth login"; exit 1; }

head=$(git symbolic-ref --short HEAD 2>/dev/null) || { echo "You are not on a branch."; exit 1; }
ticket=$(echo "$head" | grep -oE 'IT2627T05-[0-9]+')
if [ -n "$ticket" ]; then
  full_title="$ticket: $title"
else
  full_title="$title"          # e.g. develop -> main
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "You have uncommitted changes. Commit them first:"
  git status --short
  exit 1
fi

echo "=============== 1. Secret scan (DoD 2)"
sh scripts/005_scan_secrets.sh || { echo ""; echo "Stopped: fix the secret scan first."; exit 1; }

echo ""
echo "=============== 2. PR check (DoD 4)"
sh scripts/004_check_pr.sh "$body_file" "$base" || { echo ""; echo "Stopped: fix the PR check first."; exit 1; }

echo ""
echo "=============== 3. Push $head"
git push -u origin "$head" || exit 1

echo ""
echo "=============== 4. Pull Request"
if gh pr view "$head" >/dev/null 2>&1; then
  echo "A PR for $head already exists; updating its description."
  gh pr edit "$head" --body-file "$body_file" >/dev/null || exit 1
else
  gh pr create --base "$base" --head "$head" --title "$full_title" --body-file "$body_file" || exit 1
fi
gh pr view "$head" --json number,title,url --jq '"PR #\(.number): \(.title)\n\(.url)"'

echo ""
echo "=============== 5. GitHub checks (DoD 3)"
sleep 5   # give GitHub a moment to start the workflows
gh pr checks "$head" --watch
echo ""
echo "Required checks:"
gh pr checks "$head" --required || true

echo ""
echo "Next: ask a team member to review (DoD 4). Merge only after approval, without deleting the branch:"
echo "  gh pr merge $head --merge"
