#!/bin/sh
# Scans all dependencies for known vulnerabilities (security rule S2, docs/QUALITY_AND_SECURITY.md).
# Same scan as the required check "Dependency scan" in .github/workflows/ci-dev.yml.
#
#   backend:  dotnet list package --vulnerable --include-transitive (NuGet advisory database)
#   frontend: npm audit (GitHub advisory database)
#
# Fails on HIGH or CRITICAL vulnerabilities. MODERATE and LOW are reported but do not block.
# Runs on every PR and weekly on develop (CI workflow, schedule), so vulnerabilities published
# after a package was added are also found. Updates are done by the team through a normal PR.
#
# Requires: .NET 10 SDK, Node.js + npm, Python 3.
#
# Usage (from inside the repo, on Windows use Git Bash):
#   sh scripts/010_scan_dependencies.sh [backend|frontend|all]

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Run this inside the repository."; exit 1; }

part=${1:-all}
backend=deelproject1/backend
frontend=deelproject1/frontend
status=0
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

py=""
for p in python3 python; do
  if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then py=$p; break; fi
done

scan_backend() {
  echo "=============== Backend: NuGet packages (incl. transitive)"
  command -v dotnet >/dev/null 2>&1 || { echo "FAILED: .NET SDK not installed."; status=1; return; }
  [ -n "$py" ] || { echo "FAILED: Python 3 is required."; status=1; return; }

  dotnet restore "$backend/ProjectControl.slnx" >/dev/null || { echo "FAILED: dotnet restore"; status=1; return; }
  dotnet list "$backend/ProjectControl.slnx" package --vulnerable --include-transitive --format json \
    > "$tmp/nuget.json" || { echo "FAILED: dotnet list package"; status=1; return; }

  "$py" - "$tmp/nuget.json" <<'EOF' || status=1
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8-sig"))
blocking, other = [], []
for project in data.get("projects", []):
    for fw in project.get("frameworks", []):
        for kind in ("topLevelPackages", "transitivePackages"):
            for pkg in fw.get(kind, []):
                for v in pkg.get("vulnerabilities", []):
                    row = f"{v.get('severity','?'):<9} {pkg['id']} {pkg.get('resolvedVersion','')}  {v.get('advisoryurl','')}"
                    (blocking if v.get("severity", "").lower() in ("high", "critical") else other).append(row)
for row in sorted(set(other)):
    print("  report  " + row)
for row in sorted(set(blocking)):
    print("  BLOCK   " + row)
if blocking:
    print(f"\n{len(set(blocking))} HIGH/CRITICAL vulnerable NuGet package(s): update them (see the advisory links).")
    sys.exit(1)
print("No HIGH/CRITICAL vulnerabilities in NuGet packages.")
EOF
}

scan_frontend() {
  echo ""
  echo "=============== Frontend: npm packages"
  command -v npm >/dev/null 2>&1 || { echo "FAILED: npm not installed."; status=1; return; }
  (cd "$frontend" && npm audit --audit-level=high) || {
    echo "HIGH/CRITICAL vulnerable npm package(s): run 'npm audit fix' in $frontend or update the package."
    status=1
  }
}

case "$part" in
  backend)  scan_backend ;;
  frontend) scan_frontend ;;
  all)      scan_backend; scan_frontend ;;
  *)        echo "Usage: sh scripts/010_scan_dependencies.sh [backend|frontend|all]"; exit 2 ;;
esac

echo ""
if [ "$status" -eq 0 ]; then
  echo "RESULT: no HIGH/CRITICAL vulnerabilities in dependencies."
else
  echo "RESULT: dependency scan FAILED."
fi
exit $status
