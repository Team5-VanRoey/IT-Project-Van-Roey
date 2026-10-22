"""Checks a Pull Request against the Gitflow and Definition of Done rules of team IT2627T05.

Run by .github/workflows/pr-checks.yml and locally by scripts/004_check_pr.sh.
Input through environment variables: PR_BODY, HEAD_REF, BASE_REF, COMMITS (one message per line).
With SKIP_BODY=1 the PR description is not checked (only branch, target and commits).

The PR description is checked against the template of the branch type:
  feature/*          -> .github/pull_request_template.md
  bugfix/*           -> .github/PULL_REQUEST_TEMPLATE/bugfix.md
  hotfix/*           -> .github/PULL_REQUEST_TEMPLATE/hotfix.md
  release/*, develop -> .github/PULL_REQUEST_TEMPLATE/release.md
"""
import os
import re
import sys

TICKET = r"IT2627T05-\d+"

# Checklist items that can only be ticked after this check has run. GitHub enforces them itself:
# the rulesets require the green checks (incl. Secret scan), at least 1 approval and resolved
# conversations before merging. Logging time in Jira happens after the merge.
ENFORCED_ELSEWHERE = (
    "the pipeline passed",
    "secret scan in the pipeline",
    "approved this pr",
    "conversations are resolved",
    "will be logged",
)

body = (os.environ.get("PR_BODY", "") or "").replace("\r\n", "\n")
head = os.environ.get("HEAD_REF", "")
base = os.environ.get("BASE_REF", "")
commits = [c for c in os.environ.get("COMMITS", "").splitlines() if c.strip()]

errors = []

# develop -> main is the normal way to deliver a new version
develop_to_main = head == "develop" and base == "main"

if head.startswith("bugfix/"):
    kind = "bugfix"
elif head.startswith("hotfix/"):
    kind = "hotfix"
elif head.startswith("release/") or develop_to_main:
    kind = "release"
else:
    kind = "feature"

# 1. Branch name
if not develop_to_main and not re.fullmatch(
        rf"(feature|bugfix|hotfix)/{TICKET}(-[\w-]+)?|release/[\w.\-]+", head
):
    errors.append(
        f"Branch name '{head}' does not follow the convention "
        "(feature/IT2627T05-XX, bugfix/IT2627T05-XX, hotfix/IT2627T05-XX or release/x.y.z)."
    )

# 2. Target branch
if head.startswith(("feature/", "bugfix/")) and base != "develop":
    errors.append(f"A {head.split('/')[0]} branch must target 'develop', not '{base}'.")
if head.startswith("release/") and base != "main":
    errors.append(f"A release branch must target 'main', not '{base}'.")
if head.startswith("hotfix/") and base not in ("main", "develop"):
    errors.append(f"A hotfix branch must target 'main' (and afterwards 'develop'), not '{base}'.")
if base == "main" and not (develop_to_main or head.startswith(("release/", "hotfix/"))):
    errors.append("Only develop, release/ and hotfix/ branches may target 'main'.")

# 3. Commit messages
for msg in commits:
    if msg.startswith(("Merge", "Revert")):
        continue
    if not re.match(rf"^{TICKET}: .+", msg):
        errors.append(f"Commit without ticket reference: '{msg}' (expected 'IT2627T05-XX: description').")


def section(title):
    """Returns the text below a '## title' heading up to the next '## ' heading, without comments."""
    m = re.search(rf"^##\s*{re.escape(title)}[^\n]*$(.*?)(?=^##\s|\Z)", body, re.M | re.S)
    return re.sub(r"<!--.*?-->", "", m.group(1), flags=re.S).strip() if m else ""


def require_text(title, minimum=20):
    if len(section(title)) < minimum:
        errors.append(f"Section '{title}' is empty or too short.")


def require_field(title, field):
    """A line '- <field>: <something>' in the section must be filled in."""
    if not re.search(rf"{re.escape(field)}[^\n]*?:[ \t]*\S", section(title)):
        errors.append(f"Section '{title}': fill in '{field}'.")


def require_yes(title, field, why):
    if not re.search(rf"{re.escape(field)}[^\n]*\(yes\s*/\s*no\):[ \t]*yes\b", section(title), re.I):
        errors.append(f"Section '{title}': answer '{field}' with 'yes' ({why}).")


# 4. PR template filled in
if os.environ.get("SKIP_BODY") == "1":
    pass
elif not body.strip():
    errors.append("The PR description is empty: use the PR template.")
else:
    if kind == "release":
        if not re.search(TICKET, section("Included tickets")):
            errors.append("Section 'Included tickets' lists no ticket (IT2627T05-XX).")
        require_yes("Acceptance", "Deployed to the acceptance environment",
                    "the release must be on acceptance first")
        require_field("Acceptance", "Accepted by")
    elif not re.search(TICKET, section("Jira ticket")):
        errors.append("Section 'Jira ticket' has no valid ticket (replace IT2627T05-XX with the number).")

    require_text("Description")

    if kind == "feature":
        if not re.search(r"- \[[xX]\]", section("Type of change")):
            errors.append("Tick at least one 'Type of change'.")
        tests = "Test results"
    else:
        tests = "Testing"

    if kind == "bugfix":
        require_field("Bug", "Steps to reproduce")
        require_field("Bug", "Expected / actual")
    if kind == "hotfix":
        require_field("Production impact", "Severity")
        require_field("Production impact", "What do users experience")
        require_text("Rollback plan", 10)
    if kind in ("bugfix", "hotfix"):
        require_text("Root cause", 10)
        if not re.search(r"Regression test added[^\n]*\(yes\s*/\s*no\):[ \t]*(yes|no)\b",
                         section(tests), re.I):
            errors.append(f"Section '{tests}': answer 'Regression test added' with yes or no.")

    require_field(tests, "Tests performed")
    # Definition of Done: pre-commit hooks passed and --no-verify was never used
    require_yes(tests, "Pre-commit hooks", "passed on every commit, --no-verify not used")

    require_text("Security analysis")

    checklist = body[body.find("## Checklist"):] if "## Checklist" in body else ""
    if not checklist:
        errors.append("The checklist is missing.")
    for item in re.findall(r"- \[ \] (.+)", checklist):
        if not any(p in item.lower() for p in ENFORCED_ELSEWHERE):
            errors.append(f"Checklist item not ticked: {item.strip()}")

if errors:
    print(f"The Pull Request ({kind}) does not meet the agreements yet:\n")
    for e in errors:
        print(f"  - {e}")
    print("\nUpdate the PR; this check runs again automatically.")
    sys.exit(1)

print(f"All Gitflow and PR checks passed ({kind}).")