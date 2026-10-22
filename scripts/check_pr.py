"""Checks a Pull Request against the Gitflow and Definition of Done rules of team IT2627T05.

Run by .github/workflows/pr-checks.yml and locally by scripts/004_check_pr.sh.
Input through environment variables: PR_BODY, HEAD_REF, BASE_REF, COMMITS (one message per line).
With SKIP_BODY=1 the PR description is not checked (only branch, target and commits).
"""
import os
import re
import sys

TICKET = r"IT2627T05-\d+"

body = os.environ.get("PR_BODY", "") or ""
head = os.environ.get("HEAD_REF", "")
base = os.environ.get("BASE_REF", "")
commits = [c for c in os.environ.get("COMMITS", "").splitlines() if c.strip()]

errors = []

# develop -> main is the normal way to deliver a new version
develop_to_main = head == "develop" and base == "main"

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
if base == "main" and not (develop_to_main or head.startswith(("release/", "hotfix/"))):
    errors.append("Only develop, release/ and hotfix/ branches may target 'main'.")

# 3. Commit messages
for msg in commits:
    if msg.startswith(("Merge", "Revert")):
        continue
    if not re.match(rf"^{TICKET}: .+", msg):
        errors.append(f"Commit without ticket reference: '{msg}' (expected 'IT2627T05-XX: description').")


def section(title):
    """Returns the text below a '## title' heading up to the next '## ' heading."""
    m = re.search(rf"^##\s*{re.escape(title)}.*?$(.*?)(?=^##\s|\Z)", body, re.M | re.S)
    return m.group(1) if m else ""


def strip_comments(text):
    return re.sub(r"<!--.*?-->", "", text or "", flags=re.S).strip()


# 4. PR template filled in
if os.environ.get("SKIP_BODY") == "1":
    pass
elif not body.strip():
    errors.append("The PR description is empty: use the PR template.")
else:
    if not re.search(TICKET, strip_comments(section("Jira ticket"))):
        errors.append("Section 'Jira ticket' has no valid ticket (replace IT2627T05-XX with the number).")

    if not re.search(r"- \[[xX]\]", section("Type of change")):
        errors.append("Tick at least one 'Type of change'.")

    if len(strip_comments(section("Description"))) < 20:
        errors.append("Section 'Description' is empty or too short.")

    if not re.search(r"Tests performed:[ \t]*\S", strip_comments(section("Test results"))):
        errors.append("Section 'Test results': fill in at least 'Tests performed'.")

    checklist = body[body.find("## Checklist"):] if "## Checklist" in body else ""
    if not checklist:
        errors.append("The Definition of Done checklist is missing.")
    # Logging time happens after the merge, so that item may still be open
    open_items = [i for i in re.findall(r"- \[ \] (.+)", checklist) if "will be logged" not in i]
    for item in open_items:
        errors.append(f"Checklist item not ticked: {item.strip()}")

if errors:
    print("The Pull Request does not meet the agreements yet:\n")
    for e in errors:
        print(f"  - {e}")
    print("\nUpdate the PR; this check runs again automatically.")
    sys.exit(1)

print("All Gitflow and PR checks passed.")
