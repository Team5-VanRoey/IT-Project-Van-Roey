# Picks the PR template per branch type.
# Shared by scripts/004_check_pr.sh, scripts/006_open_pr.sh and .github/workflows/pr-template.yml.
#
#   feature/*            -> .github/pull_request_template.md (default)
#   bugfix/*             -> .github/PULL_REQUEST_TEMPLATE/bugfix.md
#   hotfix/*             -> .github/PULL_REQUEST_TEMPLATE/hotfix.md
#   release/*, develop   -> .github/PULL_REQUEST_TEMPLATE/release.md

# pr_template_for <branch>
pr_template_for() {
  case "$1" in
    bugfix/*)          echo ".github/PULL_REQUEST_TEMPLATE/bugfix.md" ;;
    hotfix/*)          echo ".github/PULL_REQUEST_TEMPLATE/hotfix.md" ;;
    release/*|develop) echo ".github/PULL_REQUEST_TEMPLATE/release.md" ;;
    *)                 echo ".github/pull_request_template.md" ;;
  esac
}

# pr_body_create <body file> <branch>
# Returns 0 when the file already exists. Otherwise creates it from the right template,
# tells you to fill it in and returns 1, so the calling script stops.
pr_body_create() {
  [ -f "$1" ] && return 0
  _template=$(pr_template_for "$2")
  cp "$_template" "$1" || { echo "Could not create $1"; return 1; }
  echo "Created $1 from $_template."
  echo "Fill it in and run the same command again."
  return 1
}