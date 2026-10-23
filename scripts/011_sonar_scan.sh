#!/bin/sh
# SonarQube analysis + Quality Gate (quality rule Q3, docs/QUALITY_AND_SECURITY.md).
# Same analysis as the required check "SonarQube quality gate" in GitHub Actions
# (.github/workflows/ci-dev.yml) and Azure DevOps (azure-pipelines/ci.yml).
#
# Two SonarQube projects, because C# can only be analysed by the SonarScanner for .NET:
#   <SONAR_PROJECT_KEY>            backend  (dotnet-sonarscanner, wraps build + tests)
#   <SONAR_PROJECT_KEY>_frontend   frontend (@sonar/scan via npx)
# The script waits for the Quality Gate of both and fails when one of them is red.
#
# Works with SonarQube Cloud (default) and a SonarQube server (e.g. the local one from
# deploy/compose.sonarqube.yml, SONAR_HOST_URL=http://localhost:9000).
#
# Pull Requests and branches are detected for GitHub Actions and Azure Pipelines and passed
# to SonarQube explicitly. What the plan can analyse is set by SONAR_BRANCH_ANALYSIS:
#   main-only  (default for SonarQube Cloud Free) PRs that target the main branch
#              (SONAR_MAIN_BRANCH = develop) and pushes on that branch. Other runs are skipped:
#              release/* and main only contain code that was analysed on its way into develop.
#   all        (SonarQube Cloud Team, SonarQube Developer Edition) every PR and branch
#   none       (default for a SonarQube server = Community Build, which has no PR/branch
#              analysis) only pushes on the main branch and local runs
#
# Requires: .NET 10 SDK, Java 17+, Node.js + npm.
#
# Environment:
#   SONAR_TOKEN             required: analysis token (never commit it; CI uses a secret)
#   SONAR_HOST_URL          default https://sonarcloud.io
#   SONAR_ORGANIZATION      SonarQube Cloud organization (default team5-vanroey)
#   SONAR_PROJECT_KEY       default Team5-VanRoey_IT-Project-Van-Roey
#   SONAR_MAIN_BRANCH       default develop (set as main branch in SonarQube by 007)
#   SONAR_BRANCH_ANALYSIS   main-only | all | none (see above)
#
# Usage (from inside the repo, on Windows use Git Bash):
#   SONAR_TOKEN=... sh scripts/011_sonar_scan.sh [backend|frontend|all]

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

part=${1:-all}
host=${SONAR_HOST_URL:-https://sonarcloud.io}
key=${SONAR_PROJECT_KEY:-Team5-VanRoey_IT-Project-Van-Roey}
org=${SONAR_ORGANIZATION:-team5-vanroey}
main_branch=${SONAR_MAIN_BRANCH:-develop}
backend=deelproject1/backend
frontend=deelproject1/frontend
status=0

if [ -z "$SONAR_TOKEN" ]; then
  echo "SONAR_TOKEN is not set."
  echo "Locally:  create a token in SonarQube (My Account -> Security) and run"
  echo "          SONAR_TOKEN=<token> sh scripts/011_sonar_scan.sh"
  echo "In CI:    the SONAR_TOKEN secret is set by scripts/007_setup_sonarqube.sh (GitHub)"
  echo "          or in the variable group 'projectcontrol-ci' (Azure DevOps)."
  exit 1
fi

case "$host" in
  *sonarcloud.io*) cloud=1; mode=${SONAR_BRANCH_ANALYSIS:-main-only} ;;
  *)               cloud=0; mode=${SONAR_BRANCH_ANALYSIS:-none} ;;
esac

# ---------- Which change is this? ----------
pr_key=""; pr_branch=""; pr_base=""; branch=""; ci=""
strip() { printf '%s' "$1" | sed 's|^refs/heads/||'; }

if [ "$GITHUB_ACTIONS" = "true" ]; then
  ci=github
  if [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
    pr_key=$(printf '%s' "$GITHUB_REF" | sed -n 's|^refs/pull/\([0-9]*\)/.*|\1|p')
    pr_branch=$GITHUB_HEAD_REF
    pr_base=$GITHUB_BASE_REF
  else
    branch=$GITHUB_REF_NAME
  fi
elif [ -n "$TF_BUILD" ]; then
  ci=azure
  pr_key=${SYSTEM_PULLREQUEST_PULLREQUESTID:-}
  [ -n "$SYSTEM_PULLREQUEST_PULLREQUESTNUMBER" ] && pr_key=$SYSTEM_PULLREQUEST_PULLREQUESTNUMBER  # GitHub repo
  if [ -n "$pr_key" ]; then
    pr_branch=$(strip "$SYSTEM_PULLREQUEST_SOURCEBRANCH")
    pr_base=$(strip "$SYSTEM_PULLREQUEST_TARGETBRANCH")
  else
    branch=$(strip "$BUILD_SOURCEBRANCH")
  fi
else
  branch=$(git symbolic-ref --short HEAD 2>/dev/null)
fi

# props: one "key=value" per line, passed to both scanners
props=""
add() { props="$props$1
"; }
skip() {
  echo "SKIPPED: $1"
  if [ "$mode" = "none" ]; then
    echo "With this edition the Quality Gate is only checked on '$main_branch' after the merge (SONAR_BRANCH_ANALYSIS=none)."
  else
    echo "The Quality Gate is enforced on the Pull Requests into '$main_branch' (SONAR_BRANCH_ANALYSIS=$mode)."
  fi
  exit 0
}

if [ -n "$pr_key" ]; then
  case "$mode" in
    none)      skip "this SonarQube edition cannot analyse Pull Requests." ;;
    main-only) [ "$pr_base" = "$main_branch" ] || skip "PR into '$pr_base': the plan only analyses PRs into '$main_branch'." ;;
  esac
  echo "Pull Request #$pr_key: $pr_branch -> $pr_base"
  add "sonar.pullrequest.key=$pr_key"
  add "sonar.pullrequest.branch=$pr_branch"
  add "sonar.pullrequest.base=$pr_base"
  if [ "$ci" = "github" ]; then
    add "sonar.pullrequest.provider=github"
    add "sonar.pullrequest.github.repository=$GITHUB_REPOSITORY"
  elif [ "$ci" = "azure" ] && [ -z "$SYSTEM_PULLREQUEST_PULLREQUESTNUMBER" ]; then
    add "sonar.pullrequest.provider=vsts"
    add "sonar.pullrequest.vsts.instanceUrl=$SYSTEM_COLLECTIONURI"
    add "sonar.pullrequest.vsts.project=$SYSTEM_TEAMPROJECT"
    add "sonar.pullrequest.vsts.repository=$BUILD_REPOSITORY_NAME"
  fi
elif [ -n "$ci" ] && [ "$branch" != "$main_branch" ]; then
  case "$mode" in
    none|main-only) skip "branch '$branch' is not the main branch '$main_branch'." ;;
  esac
  echo "Branch: $branch"
  add "sonar.branch.name=$branch"
elif [ -z "$ci" ] && [ "$cloud" -eq 1 ] && [ "$branch" != "$main_branch" ]; then
  echo "SKIPPED: a local run on '$branch' would overwrite the '$main_branch' results in SonarQube Cloud."
  echo "Use the local server instead: docker compose -f deploy/compose.sonarqube.yml up -d"
  echo "  SONAR_HOST_URL=http://localhost:9000 SONAR_TOKEN=<token> sh scripts/011_sonar_scan.sh"
  exit 0
else
  echo "Main branch analysis ($main_branch)"
fi

[ "$cloud" -eq 1 ] && add "sonar.organization=$org"

if [ -n "$SONAR_DRY_RUN" ]; then   # used by the tests: show what would be passed
  printf '%s' "$props"
  exit 0
fi

scan_backend() {
  echo "=============== Backend analysis ($key)"
  export PATH="$PATH:$HOME/.dotnet/tools"
  if ! command -v dotnet-sonarscanner >/dev/null 2>&1; then
    dotnet tool install --global dotnet-sonarscanner || { echo "FAILED: install dotnet-sonarscanner"; status=1; return; }
  fi

  results="$PWD/$backend/TestResults"
  rm -rf "$results"

  set -- /k:"$key" /n:"ProjectControl backend" \
    /d:sonar.host.url="$host" \
    /d:sonar.token="$SONAR_TOKEN" \
    /d:sonar.cs.opencover.reportsPaths="$results/**/coverage.opencover.xml" \
    /d:sonar.cs.vstest.reportsPaths="$results/*.trx" \
    /d:sonar.scanner.scanAll=false \
    /d:sonar.exclusions="**/Migrations/**,**/obj/**,**/bin/**" \
    /d:sonar.coverage.exclusions="**/ProjectControl.ServiceDefaults/**,**/ProjectControl.AppHost/**,**/Program.cs,**/Migrations/**" \
    /d:sonar.qualitygate.wait=true \
    /d:sonar.qualitygate.timeout=300
  while IFS= read -r p; do
    case "$p" in
      "") ;;
      # The scanner for .NET refuses sonar.organization as /d: property: it must be /o:
      sonar.organization=*) set -- "$@" "/o:${p#sonar.organization=}" ;;
      *) set -- "$@" "/d:$p" ;;
    esac
  done <<EOF
$props
EOF

  dotnet-sonarscanner begin "$@" || { echo "FAILED: sonarscanner begin"; status=1; return; }

  if dotnet build "$backend/ProjectControl.slnx" -c Release; then
    dotnet test "$backend/ProjectControl.slnx" -c Release --no-build \
      --settings "$backend/coverage.runsettings" --collect "XPlat Code Coverage" \
      --results-directory "$results" --logger "trx" || { echo "FAILED: tests (see above)"; status=1; }
  else
    echo "FAILED: build (see above)"; status=1
  fi

  # 'end' uploads the analysis and waits for the Quality Gate; it fails when the gate is red
  dotnet-sonarscanner end /d:sonar.token="$SONAR_TOKEN" || {
    echo "FAILED: the backend Quality Gate is red. Open $host/dashboard?id=$key"
    status=1
  }
}

scan_frontend() {
  echo ""
  echo "=============== Frontend analysis (${key}_frontend)"
  set -- -Dsonar.host.url="$host" -Dsonar.token="$SONAR_TOKEN" -Dsonar.projectKey="${key}_frontend"
  while IFS= read -r p; do
    [ -n "$p" ] && set -- "$@" "-D$p"
  done <<EOF
$props
EOF
  (
    cd "$frontend" || exit 1
    { npm ci --no-audit --no-fund >/dev/null && npm run test:coverage >/dev/null; } || {
      echo "FAILED: frontend tests (run sh scripts/009_build_test.sh frontend for details)"; exit 1; }
    npx --yes @sonar/scan "$@"
  ) || {
    echo "FAILED: the frontend Quality Gate is red. Open $host/dashboard?id=${key}_frontend"
    status=1
  }
}

case "$part" in
  backend)  scan_backend ;;
  frontend) scan_frontend ;;
  all)      scan_backend; scan_frontend ;;
  *)        echo "Usage: sh scripts/011_sonar_scan.sh [backend|frontend|all]"; exit 2 ;;
esac

echo ""
if [ "$status" -eq 0 ]; then
  echo "RESULT: SonarQube Quality Gate passed ($part)."
else
  echo "RESULT: SonarQube Quality Gate FAILED ($part)."
fi
exit $status
