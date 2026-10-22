#!/bin/sh
# Applies the GitHub settings for the Gitflow and PR process of team IT2627T05.
# Run once by the repository admin.
#
# Requires: GitHub CLI (https://cli.github.com), signed in with `gh auth login`
# as an admin of the repository, and the 'develop' branch must exist on GitHub.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/001_setup_github.sh                 repository derived from the remote
#   sh scripts/001_setup_github.sh owner/repo      repository given explicitly
#
# Works on every plan. Features that a private repository on GitHub Free does not
# support (rulesets, autolinks, secret scanning) are reported as SKIPPED; the local
# hooks (002) and the Branch guard workflow still cover those.
# Safe to run again: existing rulesets are updated instead of duplicated.

command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in first with: gh auth login"; exit 1; }

repo=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}
[ -n "$repo" ] || { echo "Could not determine the repository. Pass it as: owner/repo"; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

visibility=$(gh api "repos/$repo" --jq .visibility) || exit 1
echo "Repository: $repo ($visibility)"
echo ""

skipped=0

# api_step <description> <gh api arguments...>
# Runs one call; a plan limitation (HTTP 403/404 "upgrade") is reported as SKIPPED.
api_step() {
  desc=$1; shift
  if gh api "$@" >"$tmp/out" 2>&1; then
    echo "OK       $desc"
  elif grep -qiE "upgrade|not available|advanced security|HTTP 403" "$tmp/out"; then
    echo "SKIPPED  $desc (not available for this repository/plan)"
    skipped=$((skipped + 1))
  else
    echo "FAILED   $desc"
    sed 's/^/         /' "$tmp/out"
    exit 1
  fi
}

# ---------- 1. develop must exist ----------
if ! gh api "repos/$repo/branches/develop" >/dev/null 2>&1; then
  echo "ERROR: the branch 'develop' does not exist on GitHub yet. Create it first:"
  echo "  git checkout main && git pull"
  echo "  git checkout -b develop"
  echo "  git push -u origin develop --no-verify"
  exit 1
fi

# ---------- 2. General settings (every plan) ----------
api_step "default branch = develop, keep branches after merge" \
  -X PATCH "repos/$repo" -f default_branch=develop -F delete_branch_on_merge=false

# ---------- 3. Secret scanning ----------
cat > "$tmp/security.json" <<'EOF'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
EOF
api_step "secret scanning + push protection" -X PATCH "repos/$repo" --input "$tmp/security.json"

# ---------- 4. Jira autolink ----------
if gh api "repos/$repo/autolinks" --jq '.[].key_prefix' 2>/dev/null | grep -qx 'IT2627T05-'; then
  echo "OK       Jira autolink IT2627T05-XX (already present)"
else
  api_step "Jira autolink IT2627T05-XX" -X POST "repos/$repo/autolinks" \
    -f key_prefix='IT2627T05-' \
    -f url_template='https://jiradigi.pxl.be/browse/IT2627T05-<num>' \
    -F is_alphanumeric=false
fi

# ---------- 5. Rulesets ----------
# upsert_ruleset <name> <json file>
upsert_ruleset() {
  id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$1\") | .id" 2>/dev/null)
  if [ -n "$id" ]; then
    api_step "ruleset '$1' (updated)" -X PUT "repos/$repo/rulesets/$id" --input "$2"
  else
    api_step "ruleset '$1'" -X POST "repos/$repo/rulesets" --input "$2"
  fi
}

cat > "$tmp/main-develop.json" <<'EOF'
{
  "name": "Protect main and develop",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": { "include": ["refs/heads/main", "refs/heads/develop"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": true,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "Gitflow & PR template" },
          { "context": "Secret scan" }
        ]
      }
    }
  ]
}
EOF
upsert_ruleset "Protect main and develop" "$tmp/main-develop.json"

cat > "$tmp/work-branches.json" <<'EOF'
{
  "name": "Keep work branches",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/feature/**", "refs/heads/bugfix/**", "refs/heads/hotfix/**", "refs/heads/release/**"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" }
  ]
}
EOF
upsert_ruleset "Keep work branches" "$tmp/work-branches.json"

# Only branch names that follow the Gitflow convention can be created
cat > "$tmp/branch-naming.json" <<'EOF'
{
  "name": "Branch naming",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["~ALL"],
      "exclude": [
        "refs/heads/main",
        "refs/heads/develop",
        "refs/heads/feature/IT2627T05-*",
        "refs/heads/bugfix/IT2627T05-*",
        "refs/heads/hotfix/IT2627T05-*",
        "refs/heads/release/*"
      ]
    }
  },
  "rules": [
    { "type": "creation" }
  ]
}
EOF
upsert_ruleset "Branch naming" "$tmp/branch-naming.json"

echo ""
if [ "$skipped" -gt 0 ]; then
  echo "Done, with $skipped step(s) skipped."
  echo "Rulesets, autolinks and secret scanning need a public repository or a paid plan"
  echo "(e.g. GitHub Pro on the owner's personal account) for private repositories."
  echo "Protection then relies on the local hooks (sh scripts/002_setup_hooks.sh)"
  echo "and the 'Branch guard' workflow."
else
  echo "Done. Check on GitHub: Settings -> Rules -> Rulesets."
fi
