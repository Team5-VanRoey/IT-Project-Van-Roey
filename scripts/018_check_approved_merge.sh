#!/bin/sh
# Checks that a commit reached its branch through a MERGED Pull Request that another team member
# APPROVED. The CD workflow runs it before deploying develop (test) or main (production), so only
# approved merges are ever deployed - even if a ruleset was switched off.
# Same rule as the Branch guard workflow (.github/workflows/branch-guard.yml).
#
# Requires the GitHub CLI with a token that can read pull requests (GH_TOKEN in CI).
#
# Usage: sh scripts/018_check_approved_merge.sh <commit sha> <branch> [owner/repo]

sha=$1
branch=$2
repo=${3:-$GITHUB_REPOSITORY}

if [ -z "$sha" ] || [ -z "$branch" ] || [ -z "$repo" ]; then
  echo "Usage: sh scripts/018_check_approved_merge.sh <commit sha> <branch> [owner/repo]"
  exit 2
fi
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found."; exit 1; }

pr=$(gh api "repos/$repo/commits/$sha/pulls" \
  --jq "[.[] | select(.merged_at != null and .base.ref == \"$branch\")][0].number // empty") \
  || { echo "Could not read the pull requests of $sha."; exit 1; }

if [ -z "$pr" ]; then
  echo "REFUSED: $sha did not reach '$branch' through a merged Pull Request."
  exit 1
fi

author=$(gh api "repos/$repo/pulls/$pr" --jq '.user.login') || exit 1
approvals=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate \
  --jq "[.[] | select(.state == \"APPROVED\" and .user.login != \"$author\")] | length" \
  | awk '{ s += $1 } END { print s + 0 }')

if [ "$approvals" -lt 1 ]; then
  echo "REFUSED: PR #$pr was merged into '$branch' without approval from another team member."
  exit 1
fi

echo "OK: $sha came into '$branch' through PR #$pr, approved by $approvals other team member(s)."
