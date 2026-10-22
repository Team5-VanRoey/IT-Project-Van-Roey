# Gitflow & PR process – Team IT2627T05

## Branches
| Branch | Purpose | How is it updated? |
|---|---|---|
| `main` | Delivered, stable version | Only through a PR from `develop` (normal delivery), `release/*` or `hotfix/*` |
| `develop` | Integration of finished features | Only through a PR from `feature/*` or `bugfix/*` |
| `feature/IT2627T05-XX` | One Jira ticket | Your commits; **not** deleted after merging |
| `bugfix/IT2627T05-XX` | Bug on `develop` | Same as feature |
| `hotfix/IT2627T05-XX` | Urgent bug on `main` | PR to `main` and to `develop` |
| `release/x.y.z` | Preparing a delivery | PR to `main` |

### Naming
- The ticket number is always uppercase: `feature/IT2627T05-181`.
- A short description at the end is allowed: `feature/IT2627T05-181-pr-template`.
- Not allowed: `feature/181`, `feature/it2627t05-181`, `my-branch`, `Feature/...`.

Wrong name? Rename your branch before pushing:
```bash
git branch -m feature/IT2627T05-XX
```

### Commit messages
Every commit starts with the ticket, a colon and a space:
```
IT2627T05-181: add PR template
```

## Scripts
All scripts are in `scripts/` and are numbered in the order you use them.
On Windows, run them in **Git Bash**.

| Script | Who | When | What it does |
|---|---|---|---|
| `001_setup_github.sh` | Admin | Once | Applies the GitHub settings (see below) |
| `002_setup_hooks.sh` | Everyone | Once after cloning | Activates the Git hooks |
| `003_test_hooks.sh` | Everyone | After 002, or after changing a hook | Tests the hooks and the PR check in a temporary test repository |
| `004_check_pr.sh` | Everyone | Before opening a PR | Checks your branch, commits and PR description |
| `005_scan_secrets.sh` | Everyone | Before opening a PR | Scans the full Git history for secrets (gitleaks) and shows open GitHub secret scanning alerts |
| `006_open_pr.sh` | Everyone | To open the PR | Runs 005 and 004, pushes the branch, opens the PR and waits for the GitHub checks |

`003`, `004` and `006` need Python 3. `001` and `006` need the GitHub CLI (`gh auth login`).
`005` uses gitleaks when installed, otherwise Docker, otherwise a basic pattern search.

### Opening a PR in one command
```bash
cp .github/pull_request_template.md ../pr-body.md     # fill it in
sh scripts/006_open_pr.sh ../pr-body.md "Short title"
```
The PR title becomes `IT2627T05-XX: Short title` (ticket taken from the branch name).
Running it again updates the description of the existing PR.

## Once after cloning
```bash
git clone <repo-url>
cd <repo>
sh scripts/002_setup_hooks.sh
sh scripts/003_test_hooks.sh
```
`002_setup_hooks.sh` activates the hooks in `.githooks/`:

| Hook | Runs on | Checks |
|---|---|---|
| `pre-commit` | `git commit` | no commits on `main`/`develop`, correct branch name |
| `commit-msg` | `git commit` | message starts with `IT2627T05-XX: ` |
| `pre-push` | `git push` | no pushes to `main`/`develop`, correct branch name, no deleting remote branches |

`003_test_hooks.sh` ends with `Result: 23 passed, 0 failed` when everything works.

## Working on a ticket
```bash
git checkout develop
git pull
git checkout -b feature/IT2627T05-XX
# ... work ...
git add .
git commit -m "IT2627T05-XX: short description"
git push -u origin feature/IT2627T05-XX
```

## Checking locally before opening a PR
```bash
sh scripts/004_check_pr.sh                       # branch name, target and commits
sh scripts/004_check_pr.sh ../pr-body.md         # also the completed PR description
sh scripts/004_check_pr.sh ../pr-body.md main    # for a release or hotfix PR to main
```
For the PR description:
1. Copy `.github/pull_request_template.md` to a file **outside** the repository, e.g. `../pr-body.md`.
2. Fill it in and check it with `004_check_pr.sh`.
3. When it passes, paste the same text into the PR on GitHub.

This is the same check that GitHub runs on every PR as **Gitflow & PR template** (`scripts/check_pr.py`). If it passes locally, it passes on GitHub.

## Delivering to main
When `develop` contains a version that is ready to deliver (e.g. end of a sprint):
1. **Pull requests → New pull request**, base: `main` ← compare: `develop`.
2. Fill in the template; list the tickets included in this delivery under *Description*.
3. Same rules as any PR: at least 1 approval, conversations resolved, checks green.
4. Merge with a merge commit. `develop` is never deleted.

`feature/*` and `bugfix/*` branches can never target `main` directly.

## Review and merge
1. Ask a team member to review (not yourself).
2. The reviewer leaves feedback as comments in the PR.
3. Address the feedback and mark the conversations as *resolved*.
4. Only merge when **all checks are green**:
   - *Gitflow & PR template*
   - *Secret scan*
   - *At least one approval*
5. Do **not** click "Delete branch" after merging.
6. As the very last step, log your time on the Jira ticket.

## Protection
The repository is public, so GitHub enforces the rules itself. There are three layers:

1. **Rulesets on GitHub (server side)** – the real block, nobody can bypass it:
   - `main` and `develop`: no direct pushes, no force pushes, cannot be deleted;
   - merging only through a PR with at least 1 approval from another team member;
   - new commits after an approval require a new approval;
   - all review conversations must be resolved;
   - the checks **Gitflow & PR template** and **Secret scan** must pass;
   - `feature/**`, `bugfix/**`, `hotfix/**` and `release/**` cannot be deleted;
   - only branches named `main`, `develop`, `feature/IT2627T05-*`, `bugfix/IT2627T05-*`, `hotfix/IT2627T05-*` or `release/*` can be created.
2. **Local hooks** – give feedback already on `git commit` and `git push`, before GitHub rejects anything.
3. ***Branch guard* workflow** – safety net: creates an issue if anything ever lands on `main` or `develop` without an approved PR (e.g. when a ruleset was disabled).

Secrets are checked automatically in two ways:
- **GitHub secret scanning + push protection** (repository setting): GitHub rejects pushes that contain recognisable secrets and shows alerts under **Security**.
- **Secret scan** workflow: scans the full Git history with gitleaks on every PR and every push to `main`/`develop`. It is a required check, so a PR with a secret cannot be merged.

> **Public means visible to everyone**, including the full commit history. Never commit passwords, keys, `.env` files or personal data (Definition of Done, item 2). A secret that was ever pushed must be considered leaked: revoke it, removing the commit is not enough.

## Repository settings (once, by the admin)
Requires the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, and `develop` must already exist on GitHub.
```bash
sh scripts/001_setup_github.sh
```
The script applies:
- default branch = `develop`;
- keep branches after merge ("Automatically delete head branches" off);
- secret scanning + push protection;
- Jira autolink `IT2627T05-XX` → `https://jiradigi.pxl.be/browse/IT2627T05-XX`;
- ruleset *Protect main and develop*;
- ruleset *Keep work branches*;
- ruleset *Branch naming*.

It is safe to run again: existing rulesets are updated. Check the result under **Settings → Rules → Rulesets**.

If the repository is ever made private on GitHub Free, the script still runs but reports the rulesets, autolink and secret scanning as SKIPPED. Protection then relies on the local hooks and the *Branch guard* workflow.

## Files
| File | Purpose |
|---|---|
| `.githooks/` | Local Git hooks |
| `.github/pull_request_template.md` | Mandatory PR template |
| `.github/workflows/pr-checks.yml` | Checks on every PR (Gitflow, template, approval) |
| `.github/workflows/secret-scan.yml` | Scans the full history for secrets with gitleaks (required check) |
| `.github/workflows/branch-guard.yml` | Detects changes on `main`/`develop` without an approved PR |
| `scripts/001_setup_github.sh` | GitHub settings and rulesets |
| `scripts/002_setup_hooks.sh` | Activate the hooks |
| `scripts/003_test_hooks.sh` | Test the hooks and the PR check |
| `scripts/004_check_pr.sh` | Check your branch and PR description locally |
| `scripts/005_scan_secrets.sh` | Scan for secrets locally |
| `scripts/006_open_pr.sh` | Run all checks and open the PR |
| `scripts/check_pr.py` | The check logic, shared by GitHub and `004_check_pr.sh` |
| `docs/GITFLOW.md` | This guide |
