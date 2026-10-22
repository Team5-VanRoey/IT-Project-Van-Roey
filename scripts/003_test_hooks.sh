#!/bin/sh
# Tests the Git hooks and the PR check.
# Runs in a temporary test repository: your own repository and the remote are not touched.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/003_test_hooks.sh

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Run this inside the repository."; exit 1; }
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

# expect <ok|fail> <description> <command...>
expect() {
  want=$1; desc=$2; shift 2
  if "$@" >"$tmp/out" 2>&1; then got=ok; else got=fail; fi
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1)); echo "  PASS  $desc"
  else
    fail=$((fail + 1)); echo "  FAIL  $desc (expected: $want, got: $got)"
    sed 's/^/        /' "$tmp/out"
  fi
}

# Stages a change so there is something to commit
change() { echo "$(date +%s)-$pass-$fail" >> change.txt; git add change.txt; }

# ---------- Set up the test repository ----------
git init -q --bare "$tmp/remote.git"
git init -q "$tmp/work"
cd "$tmp/work" || exit 1
git symbolic-ref HEAD refs/heads/main
git config user.name "Hook test"
git config user.email "hooktest@example.com"
git config commit.gpgsign false
git config push.negotiate false
git remote add origin "$tmp/remote.git"

echo "test" > README.md
git add README.md
git commit -qm "init" --no-verify
git push -q origin main --no-verify
git branch develop
git push -q origin develop --no-verify

# Use the hooks from your repository in the test repository
git config core.hooksPath "$root/.githooks"

echo ""
echo "== Commits (pre-commit and commit-msg)"
git checkout -q develop
change; expect fail "commit directly on develop"                git commit -qm "IT2627T05-1: test"
git checkout -q main
expect fail "commit directly on main"                           git commit -qm "IT2627T05-1: test"
git checkout -q -b my-branch develop
expect fail "commit on branch with wrong name (my-branch)"      git commit -qm "IT2627T05-1: test"
git checkout -q -b feature/181 develop
expect fail "commit on branch without ticket prefix (feature/181)" git commit -qm "IT2627T05-181: test"
git checkout -q -b feature/it2627t05-999 develop
expect fail "commit on branch with lowercase ticket"            git commit -qm "IT2627T05-999: test"

git checkout -q -b feature/IT2627T05-181 develop
expect fail "commit message without ticket"                     git commit -qm "add template"
expect fail "commit message without colon"                      git commit -qm "IT2627T05-181 add template"
expect ok   "valid commit on feature/IT2627T05-181"             git commit -qm "IT2627T05-181: add template"

git checkout -q -b bugfix/IT2627T05-200-login develop
change; expect ok "valid commit on bugfix/IT2627T05-200-login"  git commit -qm "IT2627T05-200: fix login"
git checkout -q -b release/1.0.0 develop
change; expect ok "valid commit on release/1.0.0"               git commit -qm "IT2627T05-210: version 1.0.0"

echo ""
echo "== Pushes (pre-push)"
git checkout -q feature/IT2627T05-181
expect ok   "push feature/IT2627T05-181"                        git push -q origin feature/IT2627T05-181
expect fail "push to develop"                                   git push -q origin HEAD:develop
expect fail "push to main"                                      git push -q origin HEAD:main
expect fail "push to branch with wrong name"                    git push -q origin HEAD:test
expect fail "delete remote branch"                              git push -q origin --delete feature/IT2627T05-181

# ---------- PR check ----------
py=""
for p in python3 python; do
  if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then py=$p; break; fi
done

if [ -z "$py" ]; then
  echo ""
  echo "== PR check skipped: Python 3 not found."
else
  tpl=$(cat "$root/.github/pull_request_template.md")
  filled=$(printf '%s\n' "$tpl" | sed \
    -e 's/IT2627T05-XX$/IT2627T05-181/' \
    -e 's/- \[ \]/- [x]/' \
    -e 's/^- Tests performed:/- Tests performed: hooks tested with 003_test_hooks.sh/' \
    -e 's/^<!-- What changed.*-->/Added the PR template, Git hooks and GitHub Actions for the Gitflow process./')

  # pr <body> <head> <base> <commits>
  pr() { PR_BODY="$1" HEAD_REF="$2" BASE_REF="$3" COMMITS="$4" "$py" "$root/scripts/check_pr.py"; }

  echo ""
  echo "== PR check (scripts/check_pr.py)"
  expect fail "empty PR template"                   pr "$tpl"    feature/IT2627T05-181 develop "IT2627T05-181: x"
  expect ok   "fully completed PR template"         pr "$filled" feature/IT2627T05-181 develop "IT2627T05-181: x"
  expect fail "PR with commit without ticket"       pr "$filled" feature/IT2627T05-181 develop "quick fix"
  expect fail "feature branch targeting main"       pr "$filled" feature/IT2627T05-181 main    "IT2627T05-181: x"
  expect fail "PR from branch with wrong name"      pr "$filled" my-branch             develop "IT2627T05-181: x"
  expect ok   "release branch targeting main"       pr "$filled" release/1.0.0         main    "IT2627T05-210: x"
  expect ok   "develop targeting main"              pr "$filled" develop               main    "IT2627T05-181: x"
  expect fail "develop targeting develop"           pr "$filled" develop               develop "IT2627T05-181: x"
fi

echo ""
echo "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
