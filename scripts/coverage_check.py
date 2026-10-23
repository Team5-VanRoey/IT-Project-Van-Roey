"""Merges Cobertura coverage reports and fails when line coverage is below the minimum.

Quality rule Q2 (docs/QUALITY_AND_SECURITY.md): at least 80% line coverage.
Used by scripts/009_build_test.sh, locally and in the CI workflow.

Every .NET test project writes its own report, and a report also contains the projects it
references (e.g. ProjectControl.Api.Tests also reports on AppLogic). Adding those reports up
would count the same line several times, so the reports are merged per file and line:
a line is covered when at least one test project covers it.

Usage:
  python3 scripts/coverage_check.py <minimum %> <report.xml> [<report.xml> ...]
"""
import os
import re
import sys
import xml.etree.ElementTree as ET


def source_path(sources, filename):
    if os.path.isabs(filename) or not sources:
        return os.path.normpath(filename)
    for src in sources:
        candidate = os.path.join(src, filename)
        if os.path.exists(candidate):
            return os.path.normpath(candidate)
    return os.path.normpath(os.path.join(sources[0], filename))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    minimum = float(sys.argv[1])
    reports = sys.argv[2:]

    lines = {}      # (file, line) -> covered
    branches = {}   # (file, line) -> (covered, total)

    for report in reports:
        root = ET.parse(report).getroot()
        sources = [s.text.strip() for s in root.iter("source") if s.text]
        for cls in root.iter("class"):
            path = source_path(sources, cls.get("filename", ""))
            for line in cls.iter("line"):
                key = (path, int(line.get("number")))
                lines[key] = lines.get(key, False) or int(line.get("hits", "0")) > 0
                m = re.search(r"\((\d+)/(\d+)\)", line.get("condition-coverage", ""))
                if m:
                    covered, total = int(m.group(1)), int(m.group(2))
                    old = branches.get(key, (0, total))
                    branches[key] = (max(old[0], covered), total)

    if not lines:
        print("No coverable lines found in the coverage reports.")
        return 1

    covered = sum(1 for v in lines.values() if v)
    line_rate = 100.0 * covered / len(lines)

    files = {}
    for (path, _), hit in lines.items():
        c, t = files.get(path, (0, 0))
        files[path] = (c + (1 if hit else 0), t + 1)

    print(f"{'File':<70} {'Lines':>12} {'%':>7}")
    for path in sorted(files):
        c, t = files[path]
        print(f"{os.path.relpath(path)[-70:]:<70} {f'{c}/{t}':>12} {100.0 * c / t:6.1f}%")

    print("")
    print(f"Line coverage:   {line_rate:.1f}% ({covered}/{len(lines)} lines)")
    if branches:
        bc = sum(c for c, _ in branches.values())
        bt = sum(t for _, t in branches.values())
        print(f"Branch coverage: {100.0 * bc / bt:.1f}% ({bc}/{bt} branches)")
    print(f"Minimum:         {minimum:.0f}%")

    if line_rate + 1e-9 < minimum:
        print(f"\nFAILED: line coverage {line_rate:.1f}% is below the minimum of {minimum:.0f}%.")
        print("Add tests for the files with the lowest percentage above.")
        return 1

    print("\nOK: coverage meets the minimum.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
