#!/bin/sh
# Build + tests + coverage check (quality rules Q1 and Q2, docs/QUALITY_AND_SECURITY.md).
# This is exactly what the required check "Build & test" in .github/workflows/ci-dev.yml runs,
# so if it passes here it passes on the Pull Request.
#
#   backend:  dotnet restore/build (warnings shown), dotnet test with coverage,
#             merged line coverage >= MIN_COVERAGE (scripts/coverage_check.py)
#   frontend: npm ci, oxlint, tsc + vite build, vitest with coverage thresholds (vite.config.ts)
#
# Requires: .NET 10 SDK, Node.js 22 + npm, Python 3.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/009_build_test.sh              backend and frontend
#   sh scripts/009_build_test.sh backend      only the backend
#   sh scripts/009_build_test.sh frontend     only the frontend
#
# Environment: MIN_COVERAGE (default 80).

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

part=${1:-all}
min=${MIN_COVERAGE:-80}
root=$PWD
backend=deelproject1/backend
frontend=deelproject1/frontend
status=0

py=""
for p in python3 python; do
  if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then py=$p; break; fi
done

step() { echo ""; echo "=============== $1"; }
fail() { echo ""; echo "FAILED: $1"; status=1; }

run_backend() {
  command -v dotnet >/dev/null 2>&1 || { fail "the .NET SDK (dotnet) is not installed"; return; }
  [ -n "$py" ] || { fail "Python 3 is required for the coverage check"; return; }

  results="$root/$backend/TestResults"
  rm -rf "$results"

  step "Backend: restore"
  dotnet restore "$backend/ProjectControl.slnx" || { fail "dotnet restore"; return; }

  step "Backend: build (Release)"
  dotnet build "$backend/ProjectControl.slnx" -c Release --no-restore || { fail "dotnet build"; return; }

  step "Backend: tests with coverage"
  dotnet test "$backend/ProjectControl.slnx" -c Release --no-build \
    --settings "$backend/coverage.runsettings" \
    --collect "XPlat Code Coverage" \
    --results-directory "$results" \
    --logger "trx" || { fail "one or more backend tests failed"; return; }

  step "Backend: coverage >= $min%"
  reports=$(find "$results" -name 'coverage.cobertura.xml')
  [ -n "$reports" ] || { fail "no coverage reports found in $results"; return; }
  # shellcheck disable=SC2086  # one argument per report
  "$py" scripts/coverage_check.py "$min" $reports || fail "backend coverage below $min%"
}

run_frontend() {
  command -v npm >/dev/null 2>&1 || { fail "Node.js/npm is not installed"; return; }

  step "Frontend: npm ci"
  (cd "$frontend" && npm ci --no-audit --no-fund) || { fail "npm ci"; return; }

  step "Frontend: lint (oxlint)"
  (cd "$frontend" && npm run lint) || fail "lint errors in the frontend"

  step "Frontend: build (tsc + vite)"
  (cd "$frontend" && npm run build) || { fail "frontend build"; return; }

  step "Frontend: tests with coverage >= 80% (thresholds in vite.config.ts)"
  (cd "$frontend" && npm run test:coverage) || fail "frontend tests failed or coverage below the thresholds"
}

case "$part" in
  backend)  run_backend ;;
  frontend) run_frontend ;;
  all)      run_backend; run_frontend ;;
  *)        echo "Usage: sh scripts/009_build_test.sh [backend|frontend|all]"; exit 2 ;;
esac

echo ""
if [ "$status" -eq 0 ]; then
  echo "RESULT: build, tests and coverage OK ($part)."
else
  echo "RESULT: build & test FAILED ($part). See the messages above."
fi
exit $status
