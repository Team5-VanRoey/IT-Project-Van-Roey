#!/bin/sh
# Sets up SonarQube for the CI. Run once by an admin of the SonarQube organization.
#
#   1. SonarQube projects: <key> (backend) and <key>_frontend
#   2. Quality gate "VanRoey way" (quality rule Q3, docs/QUALITY_AND_SECURITY.md):
#        coverage on new code >= 80%      overall coverage >= 80%
#        duplication on new code <= 3%    security hotspots on new code 100% reviewed
#        new code: reliability, security and maintainability rating A
#        overall: security rating A (no open vulnerabilities)
#      and assigns it to both projects (paid plans only, see below)
#   3. GitHub: secret SONAR_TOKEN + variables SONAR_HOST_URL, SONAR_ORGANIZATION, SONAR_PROJECT_KEY
#
# Works with SonarCloud (default) and a SonarQube server. On SonarCloud the "Automatic Analysis"
# is switched off, because the CI workflow does the analysis (with coverage).
# SonarQube Cloud Free: the custom gate can be created, but assigning it is refused (reported as
# SKIPPED), so both projects keep the built-in "Sonar way". That gate has the same six new-code
# conditions (incl. coverage on new code >= 80%); the overall 80% is enforced by the "Build & test"
# check (scripts/009_build_test.sh). On a paid plan, running this script again assigns the gate.
# The main branch is renamed to develop, because every PR targets develop.
#
# Requires: curl, GitHub CLI (gh auth login as repository admin).
#
# Environment:
#   SONAR_TOKEN          required: token of a SonarQube admin (My Account -> Security)
#   SONAR_CI_TOKEN       token stored as GitHub secret for the CI (default: SONAR_TOKEN)
#   SONAR_HOST_URL       default https://sonarcloud.io
#   SONAR_ORGANIZATION   SonarCloud organization (default team5-vanroey)
#   SONAR_PROJECT_KEY    default Team5-VanRoey_IT-Project-Van-Roey
#
# Usage (from inside the repo, on Windows use Git Bash):
#   SONAR_TOKEN=... sh scripts/007_setup_sonarqube.sh [owner/repo]
# Safe to run again.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

host=${SONAR_HOST_URL:-https://sonarcloud.io}
host=${host%/}
key=${SONAR_PROJECT_KEY:-Team5-VanRoey_IT-Project-Van-Roey}
org=${SONAR_ORGANIZATION:-team5-vanroey}
gate="VanRoey way"
main_branch=${SONAR_MAIN_BRANCH:-develop}

[ -n "$SONAR_TOKEN" ] || { echo "Set SONAR_TOKEN first (SonarQube: My Account -> Security -> Generate token)."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl not found."; exit 1; }
py=""
for p in python3 python; do
  if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then py=$p; break; fi
done
[ -n "$py" ] || { echo "Python 3 is required."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in first with: gh auth login"; exit 1; }

repo=${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}
[ -n "$repo" ] || { echo "Could not determine the repository. Pass it as: owner/repo"; exit 1; }

case "$host" in
  *sonarcloud.io*) cloud=1 ;;
  *)               cloud=0 ;;
esac

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# sonar <GET|POST> <api path> [name=value ...]
# Calls the SonarQube web API (response in $tmp/out); adds the organization on SonarCloud.
sonar() {
  method=$1; path=$2; shift 2
  [ "$cloud" -eq 1 ] && set -- "$@" "organization=$org"
  n=$#
  while [ "$n" -gt 0 ]; do
    kv=$1; shift
    set -- "$@" --data-urlencode "$kv"
    n=$((n - 1))
  done
  if [ "$method" = GET ]; then set -- -G "$@"; else set -- -X POST "$@"; fi
  code=$(curl -s -o "$tmp/out" -w '%{http_code}' -u "$SONAR_TOKEN:" "$@" "$host/api/$path")
  [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 300 ]
}

# json <python expression on 'd'>: evaluates against the last response
json() { "$py" -c "import json,sys; d=json.load(open(sys.argv[1])); print($1)" "$tmp/out" 2>/dev/null; }

step() { echo "OK       $1"; }
warn() { echo "SKIPPED  $1"; sed 's/^/         /' "$tmp/out"; echo ""; }

echo "SonarQube: $host$( [ "$cloud" -eq 1 ] && echo " (organization $org)")"
echo "GitHub:    $repo"
echo ""

sonar GET authentication/validate && [ "$(json "d.get('valid')")" = "True" ] || { echo "FAILED   SONAR_TOKEN is not valid for $host"; exit 1; }

# ---------- 1. Projects ----------
for k in "$key" "${key}_frontend"; do
  case "$k" in *_frontend) name="ProjectControl frontend" ;; *) name="ProjectControl backend" ;; esac
  if sonar GET projects/search "projects=$k" && [ "$(json "len(d.get('components', []))")" != "0" ]; then
    step "project $k (already present)"
  elif sonar POST projects/create "project=$k" "name=$name" "visibility=public"; then
    step "project $k"
  else
    echo "FAILED   project $k"; sed 's/^/         /' "$tmp/out"; exit 1
  fi
  # PRs target develop, so develop is the main branch in SonarQube (the reference for "new code";
  # on the Free plan only PRs into the main branch are analysed)
  sonar POST project_branches/rename "project=$k" "name=$main_branch" \
    && step "main branch of $k = $main_branch" \
    || warn "rename main branch of $k to $main_branch (Project Settings -> Branches)"
  if [ "$cloud" -eq 1 ]; then
    sonar POST autoscan/activation "projectKey=$k" "enable=false" \
      && step "automatic analysis off for $k (CI analyses)" \
      || warn "automatic analysis off for $k (switch it off under Administration -> Analysis Method)"
  fi
done

# ---------- 2. Quality gate ----------
gate_ok=1
if sonar GET qualitygates/show "name=$gate"; then
  gate_id=$(json "d.get('id', '')")
  step "quality gate '$gate' (already present, conditions refreshed)"
  # Remove the old conditions so the list below is the only truth
  for id in $(json "' '.join(str(c['id']) for c in d.get('conditions', []))"); do
    sonar POST qualitygates/delete_condition "id=$id" >/dev/null || true
  done
elif sonar POST qualitygates/create "name=$gate"; then
  gate_id=$(json "d.get('id', '')")
  step "quality gate '$gate'"
else
  warn "custom quality gate (not allowed on this plan?): the built-in 'Sonar way' stays active"
  gate_ok=0
fi

# SonarQube Cloud identifies the gate by its id (gateId), a SonarQube server by its name (gateName)
if [ "$cloud" -eq 1 ]; then
  [ -n "$gate_id" ] || { warn "quality gate id not found"; gate_ok=0; }
  gate_ref="gateId=$gate_id"
else
  gate_ref="gateName=$gate"
fi

if [ "$gate_ok" -eq 1 ]; then
  # metric  operator  threshold  description
  while read -r metric op error desc; do
    [ -n "$metric" ] || continue
    if sonar POST qualitygates/create_condition "$gate_ref" "metric=$metric" "op=$op" "error=$error"; then
      step "  condition $desc"
    else
      warn "  condition $desc ($metric)"
    fi
  done <<'EOF'
new_coverage                    LT 80  coverage-on-new-code>=80%
coverage                        LT 80  overall-coverage>=80%
new_duplicated_lines_density    GT 3   duplication-on-new-code<=3%
new_security_hotspots_reviewed  LT 100 hotspots-on-new-code-100%-reviewed
new_reliability_rating          GT 1   new-code-reliability-rating-A
new_security_rating             GT 1   new-code-security-rating-A
new_maintainability_rating      GT 1   new-code-maintainability-rating-A
security_rating                 GT 1   overall-security-rating-A
EOF

  for k in "$key" "${key}_frontend"; do
    sonar POST qualitygates/select "$gate_ref" "projectKey=$k" \
      && step "quality gate '$gate' assigned to $k" \
      || warn "assign quality gate to $k (Free plan: 'Sonar way' stays active, see QUALITY_AND_SECURITY.md Q3)"
  done
fi

# ---------- 3. GitHub secret and variables ----------
echo ""
printf '%s' "${SONAR_CI_TOKEN:-$SONAR_TOKEN}" | gh secret set SONAR_TOKEN --repo "$repo" >/dev/null \
  && step "GitHub secret SONAR_TOKEN" || { echo "FAILED   GitHub secret SONAR_TOKEN"; exit 1; }
gh variable set SONAR_HOST_URL --repo "$repo" --body "$host" >/dev/null && step "GitHub variable SONAR_HOST_URL=$host"
gh variable set SONAR_PROJECT_KEY --repo "$repo" --body "$key" >/dev/null && step "GitHub variable SONAR_PROJECT_KEY=$key"
if [ "$cloud" -eq 1 ]; then
  gh variable set SONAR_ORGANIZATION --repo "$repo" --body "$org" >/dev/null && step "GitHub variable SONAR_ORGANIZATION=$org"
fi

echo ""
echo "Done. Check the gate in SonarQube: $host -> Quality Gates."
echo "Next: sh scripts/001_setup_github.sh (makes 'SonarQube backend (C#)' and 'SonarQube frontend (React)' required checks)."
