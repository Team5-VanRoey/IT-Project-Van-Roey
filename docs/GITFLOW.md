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

### DTAP environments
Every long-lived branch belongs to one environment. Code only moves forward through a merge, never by deploying a work branch directly.

| Environment | Branch | Deployed | By |
|---|---|---|---|
| **D**evelopment | `feature/*`, `bugfix/*` | your own computer (`sh scripts/012_deploy.sh dev`) + CI on every PR | you |
| **T**est | `develop` | automatically after every merge, once CI is green | `CD Test` workflow |
| **A**cceptance | `release/x.y.z` | automatically after every push, once CI is green | `CD Acceptance` workflow |
| **P**roduction | `main` | after a merge, **only after manual approval** | `CD Production` workflow |

`hotfix/*` is never deployed on its own: it reaches production through its PR to `main`. See `docs/CI_CD.md`.

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
All scripts are in `scripts/` and are numbered in the order you would use them.
On Windows, run them in **Git Bash** or **WSL** (not in PowerShell).

**You only have to run `002` once per clone.** Everything else is either done once by the admin or optional:
GitHub runs the same checks automatically on every PR.

| Script | Required? | Who | When | What it does |
|---|---|---|---|---|
| `001_setup_github.sh` | Once, admin only | Admin | Once for the whole repository (already done) | Applies the GitHub settings and rulesets (see below) |
| `002_setup_hooks.sh` | **Required** | Everyone | Once per clone (again only after a new clone or on another computer) | Activates the Git hooks; after that they run automatically on every `git commit` and `git push` |
| `003_test_hooks.sh` | Optional | Everyone | Once after 002 to verify, or after changing a hook | Tests the hooks and the PR check in a temporary test repository |
| `004_check_pr.sh` | Optional | Everyone | Before opening a PR, if you want to know in advance | Checks your branch, commits and PR description (GitHub does the same automatically) |
| `005_scan_secrets.sh` | Optional | Everyone | Before pushing, if you want to know in advance | Scans the full Git history for secrets (GitHub does the same automatically on every PR) |
| `006_open_pr.sh` | Optional | Everyone | Only if you prefer the terminal over the website | Runs 005 and 004, pushes the branch, opens the PR and waits for the GitHub checks |
| `007_setup_sonarqube.sh` | Once, admin only | Admin | Once | SonarQube projects (main branch `develop`), quality gate (*Sonar way* on the Free plan, *VanRoey way* prepared), `SONAR_TOKEN` secret |
| `008_setup_environments.sh` | Once, admin only | Admin | Once | GitHub environments `test`, `acceptance`, `production` (approval) with their secrets |
| `009_build_test.sh` | Optional | Everyone | Before pushing, if you want to know in advance | Build + lint + tests + coverage ≥ 80% (same as the *Build & test* check) |
| `010_scan_dependencies.sh` | Optional | Everyone | After adding or updating a package | Vulnerable NuGet/npm packages (same as the *Dependency scan* check) |
| `011_sonar_scan.sh` | Optional | Everyone | When you want the Quality Gate before the PR | SonarQube analysis + Quality Gate (same as the *SonarQube quality gate* check) |
| `012_deploy.sh` | Optional | Everyone / GitHub | `dev`: run the app locally; `test`/`acc`/`prod`: by the CD workflows | Deploys one DTAP environment with Docker Compose and runs the smoke test |
| `013_smoke_test.sh` | – | `012`, `016` | After every deployment | Checks frontend, `/health` and `/api/projects` |
| `014_images.sh` | Optional | Everyone / CI | `build` before changing a Dockerfile | Build once: versions images by their source, builds/scans/pushes only new versions, resolves digests for the CD |
| `015_setup_azure.sh` | Once per environment, admin only | Admin | When an environment moves to Azure | Azure Container Apps + free Azure SQL + OIDC deploy identity ([`AZURE.md`](AZURE.md)) |
| `016_deploy_azure.sh` | – | CD | Automatically, when `DEPLOY_TARGET=azure` | Deploys to Azure Container Apps, smoke test, rollback |
| `018_check_approved_merge.sh` | – | CD | Before every deployment to test and production | Only commits merged through a PR approved by another team member are deployed |
| `019_backup.sh` | – | Backup workflow / admin | Nightly, and by hand before risky migrations | Verified, encrypted database backup, copied off the server ([`DISASTER_RECOVERY.md`](DISASTER_RECOVERY.md)) |
| `020_restore.sh` | – | Restore workflow | During an incident | Restore a backup (or Azure point-in-time), with safety backup and smoke test |
| `021_dr_test.sh` | Optional | DR test workflow | Monthly, and after changing 019/020 | Restores the latest backup in a throw-away environment and runs the smoke test |
| `017_setup_azure_devops.sh` | Once, admin only | Admin | Only when moving to Azure DevOps | Variable group, pipelines, environments, branch policies |
| `ado_check_pr.sh` | – | Azure Pipelines | Every PR in Azure Repos | The Gitflow & PR template check for Azure DevOps |

Forgot to run `002`? Nothing can go wrong on `main` or `develop`: the rulesets on GitHub still block it.
The hooks only give you faster feedback on your own computer.

`003`, `004`, `006`, `007`, `009` and `010` need Python 3. `001`, `006`, `007` and `008` need the GitHub CLI (`gh auth login`).
`009`–`011` need the .NET 10 SDK and Node.js 22; `012` needs Docker with Compose v2. Details: [`CI_CD.md`](CI_CD.md).
`005` uses gitleaks when installed, otherwise Docker, otherwise a basic pattern search.

## PR templates
Every branch type has its own PR template, with extra sections for that type:

| Branch | Template | Extra sections |
|---|---|---|
| `feature/*` | `.github/pull_request_template.md` (default) | – |
| `bugfix/*` | `.github/PULL_REQUEST_TEMPLATE/bugfix.md` | Bug (reproduce, expected/actual), Root cause, regression test |
| `hotfix/*` | `.github/PULL_REQUEST_TEMPLATE/hotfix.md` | Production impact, Root cause, Rollback plan, PR back to `develop` |
| `release/*`, `develop` → `main` | `.github/PULL_REQUEST_TEMPLATE/release.md` | Included tickets, Acceptance (sign-off on the acceptance environment) |

**The right template is chosen automatically from your branch name.** On the website GitHub first shows the default (feature) template; just click **Create pull request**. The *PR checks* workflow then replaces the description with the template of your branch type within a few seconds. Reload the page, click **Edit** on the description and fill it in. The *Gitflow & PR template* check stays red until it is complete, and runs again after every edit.

Want the right template before creating the PR? Add `&template=<name>.md` to the URL:
```
https://github.com/Team5-VanRoey/IT-Project-Van-Roey/compare/develop...bugfix/IT2627T05-XX?expand=1&template=bugfix.md
```
The scripts `004` and `006` also pick the right template from your branch name.

### Opening a PR in one command (optional)
```bash
sh scripts/006_open_pr.sh ../pr-body.md "Short title"   # 1st time: creates ../pr-body.md from the right template
# fill in ../pr-body.md
sh scripts/006_open_pr.sh ../pr-body.md "Short title"   # 2nd time: checks, pushes and opens the PR
```
`hotfix/*` and `release/*` target `main` by default. After a hotfix the script reminds you to open the second PR to `develop`.
The PR title becomes `IT2627T05-XX: Short title` (ticket taken from the branch name).
Running it again updates the description of the existing PR.

## Once after cloning
```bash
git clone https://github.com/Team5-VanRoey/IT-Project-Van-Roey.git
cd IT-Project-Van-Roey
sh scripts/002_setup_hooks.sh      # required
sh scripts/003_test_hooks.sh       # optional: verify that everything works
```
`002_setup_hooks.sh` activates the hooks in `.githooks/`:

| Hook | Runs on | Checks |
|---|---|---|
| `pre-commit` | `git commit` | no commits on `main`/`develop`, correct branch name, Gitleaks secret scan of the staged changes |
| `commit-msg` | `git commit` | message starts with `IT2627T05-XX: ` |
| `pre-push` | `git push` | no pushes to `main`/`develop`, correct branch name, no deleting remote branches |

The `pre-commit` hook needs **Gitleaks** (`winget install Gitleaks.Gitleaks`, `brew install gitleaks` or the [releases page](https://github.com/gitleaks/gitleaks/releases)); without it every commit is rejected.

`003_test_hooks.sh` ends with `Result: 31 passed, 0 failed` when everything works.

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
Then open the PR on GitHub:
1. Click **Compare & pull request** in the yellow bar (or **Pull requests → New pull request**).
2. Check: base `develop` ← compare `feature/IT2627T05-XX`.
3. Title: `IT2627T05-XX: short description`.
4. The PR template is filled in automatically. For a bugfix, hotfix or release it is swapped for the right template right after you create the PR (see **PR templates**). Complete every section and tick the checklist.
5. Choose a team member as **Reviewer** and click **Create pull request**.
6. Wait until all required checks are green (see **Review and merge**). If one is red, click **Details**, fix it and update the PR.

## Checking locally before opening a PR (optional)
```bash
sh scripts/004_check_pr.sh                       # branch name, target and commits
sh scripts/004_check_pr.sh ../pr-body.md         # also the completed PR description
sh scripts/004_check_pr.sh ../pr-body.md develop # e.g. the second hotfix PR, to develop
```
hotfix/* and release/* are checked against `main` by default, all other branches against `develop`.

For the PR description:
1. Run `004_check_pr.sh ../pr-body.md`: the first time it creates `../pr-body.md` from the template of your branch type (**outside** the repository).
2. Fill it in and run `004_check_pr.sh ../pr-body.md` again.
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
4. Only merge when **all checks are green** and **a team member approved** the PR:
   - *Gitflow & PR template*
   - *Secret scan*
   - *Build & test* (build, lint, tests, coverage ≥ 80%)
   - *SonarQube quality gate*
   - *Dependency scan* (no HIGH/CRITICAL vulnerabilities in dependencies)
   - *Docker build & scan* (images build, compose files valid, no HIGH/CRITICAL in the images)
   - the branch is up to date with its target (update it with **Update branch** on the PR)
   - the approval is enforced by the ruleset: without it, GitHub shows "Review required" and blocks the merge.
5. Do **not** click "Delete branch" after merging.
6. As the very last step, log your time on the Jira ticket.

## Protection
The repository is public, so GitHub enforces the rules itself. There are three layers:

1. **Rulesets on GitHub (server side)** – the real block, nobody can bypass it:
   - `main` and `develop`: no direct pushes, no force pushes, cannot be deleted;
   - merging only through a PR with at least 1 approval from another team member;
   - new commits after an approval require a new approval;
   - all review conversations must be resolved;
   - the checks **Gitflow & PR template**, **Secret scan**, **Build & test**, **SonarQube quality gate**, **Dependency scan** and **Docker build & scan** must pass, on a branch that is up to date with its target;
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
| `.github/pull_request_template.md` | Default PR template (feature) |
| `.github/PULL_REQUEST_TEMPLATE/` | PR templates for bugfix, hotfix and release |
| `.github/workflows/ci-dev.yml` | CI on every PR: Build & test, SonarQube quality gate, Dependency scan, Docker build & scan (required checks) |
| `.github/workflows/cd-test.yml` | Deploys `develop` to **test** after every merge (when CI is green) |
| `.github/workflows/cd-acceptance.yml` | Deploys `release/*` to **acceptance** |
| `.github/workflows/cd-production.yml` | Deploys `main` to **production** after manual approval |
| `.github/workflows/_deploy.yml` | Reusable: resolve the images CI built, scan them again, deploy, smoke test (never builds) |
| `.github/workflows/backup.yml`, `restore.yml`, `dr-test.yml` | Disaster recovery: nightly backups, restore (with approval), monthly restore test |
| `docs/DISASTER_RECOVERY.md` | RPO/RTO per environment and runbooks |
| `.github/workflows/redeploy.yml` | Manual rollback / re-deploy of a version that was already built |
| `deploy/compose.yml`, `deploy/compose.<dev\|test\|acc\|prod>.yml` | Docker Compose base + one file per DTAP environment |
| `deploy/env/*.env.example` | Settings per environment (the real `.env` files are ignored by Git) |
| `deploy/compose.sonarqube.yml` | Local SonarQube server |
| `deelproject1/frontend/Dockerfile`, `nginx/default.conf.template` | Frontend image (nginx, proxies `/api` to `API_UPSTREAM`) |
| `azure-pipelines/` | The same CI/CD for Azure DevOps (ready, not used while on GitHub) |
| `deelproject1/frontend/sonar-project.properties` | SonarQube settings for the frontend |
| `.github/workflows/pr-checks.yml` | Sets the PR template per branch type and checks every PR (branch name, target, commits, PR template) |
| `.github/workflows/secret-scan.yml` | Scans the full history for secrets with gitleaks (required check) |
| `.github/workflows/branch-guard.yml` | Detects changes on `main`/`develop` without an approved PR |
| `scripts/001_setup_github.sh` | GitHub settings and rulesets |
| `scripts/002_setup_hooks.sh` | Activate the hooks |
| `scripts/003_test_hooks.sh` | Test the hooks and the PR check |
| `scripts/004_check_pr.sh` | Check your branch and PR description locally |
| `scripts/005_scan_secrets.sh` | Scan for secrets locally |
| `scripts/006_open_pr.sh` | Run all checks and open the PR |
| `scripts/007_setup_sonarqube.sh` | SonarQube projects and quality gate |
| `scripts/008_setup_environments.sh` | DTAP environments on GitHub |
| `scripts/009_build_test.sh` | Build, tests and coverage check |
| `scripts/010_scan_dependencies.sh` | Dependency vulnerability scan |
| `scripts/011_sonar_scan.sh` | SonarQube analysis + Quality Gate |
| `scripts/012_deploy.sh` | DTAP deployment with Docker Compose |
| `scripts/013_smoke_test.sh` | Smoke test after a deployment |
| `scripts/coverage_check.py` | Merges the .NET coverage reports and checks the 80% minimum |
| `scripts/014_images.sh` … `017_setup_azure_devops.sh`, `ado_check_pr.sh` | Images, Azure and Azure DevOps (see the scripts table) |
| `docs/AZURE.md` | Azure hosting, costs and the move to Azure DevOps |
| `scripts/pr_template.sh` | Picks the PR template per branch type, shared by `004`, `006` and *PR checks* |
| `scripts/check_pr.py` | The check logic, shared by GitHub and `004_check_pr.sh` |
| `docs/GITFLOW.md` | This guide |
| `docs/CI_CD.md` | CI/CD pipeline and DTAP |
| `docs/QUALITY_AND_SECURITY.md` | Quality rules and security policy |
| `.gitattributes` | Forces LF line endings for scripts and hooks, so they also work on Windows |

## Troubleshooting on Windows
| Problem | Cause | Fix |
|---|---|---|
| `$'\r': command not found`, `Syntax error: end of file unexpected` | Windows line endings (CRLF) in the scripts | `sed -i 's/\r$//' .githooks/* scripts/*.sh` (with `.gitattributes` this should not happen anymore) |
| `sh: command not found` in PowerShell | The scripts are shell scripts | Run them in Git Bash or WSL |
| `git status` shows many files with `old mode 100644 / new mode 100755` (WSL) | File permissions on the Windows drive | `git config core.fileMode false` |
| `Deletion of directory 'scripts' failed` when switching branches | Another program has the folder open | Close your IDE, Explorer windows and terminals in that folder, answer `n` |
| `Unable to read current working directory` (WSL) | The folder was recreated by Git on the Windows side | `cd` into the repository again |