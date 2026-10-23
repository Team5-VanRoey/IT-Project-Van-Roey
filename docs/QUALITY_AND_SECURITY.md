# Quality rules & security policy – Team IT2627T05

Goal: clear quality and security rules, checked **automatically on every Pull Request**, so
mistakes and vulnerabilities are found before they reach `develop` – not in production.

Every rule below has an ID (Q1, S2, …). The workflows and scripts refer to these IDs, so you can
always trace a red check back to the rule behind it. How the checks run is described in
[`CI_CD.md`](CI_CD.md); the branch and PR process in [`GITFLOW.md`](GITFLOW.md).

## Overview

| Rule | What | Enforced by | Blocks the merge? |
|---|---|---|---|
| **Q1** | Build, lint and all tests pass | *Build & test* (`009_build_test.sh`) | yes |
| **Q2** | Test coverage ≥ **80%** | *Build & test* + SonarQube quality gate | yes |
| **Q3** | SonarQube Quality Gate green | *SonarQube quality gate* (`011_sonar_scan.sh`) | yes |
| **Q4** | Every change has tests; every bugfix a regression test | PR template + review | yes (review) |
| **Q5** | Review by another team member | Ruleset (1 approval, conversations resolved) | yes |
| **S1** | No secrets in the repository | pre-commit hook, *Secret scan*, GitHub push protection | yes |
| **S2** | No HIGH/CRITICAL vulnerable dependencies | *Dependency scan* (`010_scan_dependencies.sh`), on every PR and weekly | yes |
| **S3** | Secrets only in GitHub environments or ignored `.env` files | `.gitignore`, `deploy/env/*.example`, review | yes (S1 scan) |
| **S4** | No HIGH/CRITICAL vulnerabilities in container images | *Docker build & scan* + CD (Trivy) | yes / blocks deploy |
| **S5** | No vulnerabilities in our own code, hotspots reviewed | SonarQube quality gate | yes |
| **S6** | Hardened runtime | Dockerfiles, `deploy/compose*.yml`, `nginx/default.conf.template`, Azure setup | review |
| **S7** | Production only after approval | GitHub environment `production` | blocks deploy |
| **S8** | Recoverable data: encrypted backups, tested restores | `backup.yml`, `restore.yml`, `dr-test.yml` | – (monitored) |

The required checks are set in the ruleset *Protect main and develop* (`scripts/001_setup_github.sh`).
"Require branches to be up to date" is on: a PR is checked against the latest `develop`.

---

## Quality rules

### Q1 – Build, lint and tests pass
- Backend: `dotnet build -c Release` without errors, `dotnet test` all green.
- Frontend: `oxlint` without errors, `tsc` + `vite build` succeed, `vitest` all green.
- Locally: `sh scripts/009_build_test.sh` (same script as the CI).

### Q2 – Minimum test coverage 80%
Checked twice, on purpose:

| Where | Measure | Minimum | Configured in |
|---|---|---|---|
| *Build & test* – backend | line coverage of all test projects merged | 80% | `MIN_COVERAGE` in `009_build_test.sh`, `scripts/coverage_check.py` |
| *Build & test* – frontend | lines, statements, functions, branches | 80% each | `coverage.thresholds` in `deelproject1/frontend/vite.config.ts` |
| SonarQube | coverage on **new code** and **overall** | 80% | quality gate *VanRoey way* (`007_setup_sonarqube.sh`) |

**Excluded from coverage** (no logic to test, or generated):
`ProjectControl.AppHost`, `ProjectControl.ServiceDefaults`, `Program.cs`, EF `Migrations/`,
generated code (`[GeneratedCode]`, `[ExcludeFromCodeCoverage]`), `src/main.tsx`.
Settings: `deelproject1/backend/coverage.runsettings`, `vite.config.ts`, `sonar-project.properties`.
Adding an exclusion requires a short reason in the PR and approval in review –
`[ExcludeFromCodeCoverage]` on business logic is never accepted.

### Q3 – SonarQube Quality Gate
Two SonarQube projects, both must be green:
`Team5-VanRoey_IT-Project-Van-Roey` (backend, C#) and `…_frontend` (TypeScript/React).

Quality gate **VanRoey way**:

| Condition | Threshold |
|---|---|
| Coverage on new code | ≥ 80% |
| Overall coverage | ≥ 80% |
| Duplicated lines on new code | ≤ 3% |
| Reliability rating on new code (bugs) | A |
| Security rating on new code (vulnerabilities) | A |
| Maintainability rating on new code (code smells) | A |
| Security hotspots reviewed on new code | 100% |
| Overall security rating | A |

*New code* = the changes compared to `develop` (the main branch in SonarQube).
**SonarQube Cloud Free** does not allow a custom gate: the built-in *Sonar way* then applies, which
has the same new-code conditions (incl. coverage on new code ≥ 80%); the overall 80% is enforced by
*Build & test*. Free also analyses only PRs into `develop`; PRs into `main` contain code that was
already analysed on its way into `develop`. The same rules apply in Azure DevOps (`AZURE.md`).

A red gate is fixed in the code. Marking an issue *false positive* or *won't fix* in SonarQube
is only allowed with a comment that explains why, and is checked in the review.

### Q4 – Tests with every change
- New behaviour comes with unit tests (Domain, AppLogic) and, where it touches the database or
  API, tests on Infrastructure/Api level.
- A bugfix or hotfix contains a test that fails without the fix (PR template: *Regression test added*).
- Tests are independent of each other and of the machine: no real database or network
  (Infrastructure tests use SQLite in memory).

### Q5 – Review
- At least 1 approval from another team member; new pushes require a new approval.
- All conversations resolved. The reviewer also checks the rules that tools cannot check
  (Q4, S3, S6, exclusions under Q2/Q3).

---

## Security policy

### S1 – No secrets in the repository
Passwords, connection strings with passwords, API keys, tokens, certificates and private keys
never go into Git – also not in a branch, an old commit or a test.

Checked by: the `pre-commit` hook (gitleaks on the staged changes), the *Secret scan* workflow
(gitleaks over the full history, required check), and GitHub secret scanning + push protection.
Locally: `sh scripts/005_scan_secrets.sh`.

**A secret that was pushed is leaked** (the repository is public): revoke/rotate it first,
then remove it from the code. Removing the commit alone is not enough. Report it in the team
channel the same day.

### S2 – Dependencies
- The *Dependency scan* blocks a PR when a NuGet or npm package (including transitive ones)
  has a known **HIGH or CRITICAL** vulnerability. MODERATE and LOW are shown but do not block.
- The same scan runs **weekly on `develop`** (CI workflow, `schedule`), so a vulnerability that is
  published after a package was added is found too. A red weekly run is picked up as a ticket.
- Updates are made by the team in a normal `feature/`/`bugfix/` branch with a Jira ticket; no tool
  opens automatic update PRs (no Dependabot), so every change goes through the same review.
- `package-lock.json` is always committed; CI installs with `npm ci` (exact versions).
- New packages: only well-maintained, widely used packages with a compatible licence; mention
  the reason in the PR.

| Severity | Fix within |
|---|---|
| Critical | 1 working day (or before the next deployment) |
| High | 1 sprint |
| Moderate | next planned update |
| Low | when convenient |

Locally: `sh scripts/010_scan_dependencies.sh`.

### S3 – Secrets in the environments
- Each DTAP environment has its own secrets in its **GitHub environment** (`test`, `acceptance`,
  `production`): `MSSQL_SA_PASSWORD`, `DEPLOY_SSH_KEY`. They are generated by
  `008_setup_environments.sh` and are never printed or shared in chat.
- **Azure**: the pipelines log in with **OIDC / workload identity federation** – no Azure password,
  key or client secret exists anywhere. Each environment has its own identity, Contributor on its
  own resource group only, usable only by its own GitHub environment (or Azure DevOps service
  connection). The database password lives only as a secret of the API container app.
- Locally: `deploy/env/<env>.env`, created from the `.example` file. These files are in `.gitignore`.
- The workflows only get the permissions they need (`permissions:` per workflow); secrets are
  not available to PRs from forks.
- Never put a secret in a URL, a log line, a Docker image layer or `appsettings*.json`.

### S4 – Container images
- Every image is scanned with **Trivy** in CI (*Docker build & scan*) and again before every
  deployment. HIGH/CRITICAL vulnerabilities with an available fix block the merge/deployment.
- Official base images only (`mcr.microsoft.com/dotnet`, `node`, `nginxinc/nginx-unprivileged`).
- Containers run as a non-root user (API: `$APP_UID`, frontend: unprivileged nginx).
- **Build once, deploy everywhere**: an image is built once per source version and deployed by
  digest to test, acceptance and production, so what was tested and accepted is exactly what runs
  in production. Images contain no environment settings or secrets. Tags `sha-<commit>` and
  `test`/`acc`/`prod` show which version runs where.

### S5 – Vulnerabilities in our own code
- SonarQube security rating A (no vulnerabilities) and 100% reviewed security hotspots (Q3).
- Input from users is validated in the API; database access only through EF Core
  (parameterised, no string-built SQL).
- Development-only features stay behind `IsDevelopment()` / `import.meta.env.DEV`
  (e.g. OpenAPI, the dev login button).

### S6 – Hardened runtime
- The frontend (nginx) sends security headers: `Content-Security-Policy`,
  `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`.
- Containers run with `no-new-privileges`; in acceptance and production also read-only with
  memory limits (`deploy/compose.acc.yml`, `deploy/compose.prod.yml`).
- Only the frontend port is published in test, acceptance and production; the API and the
  database are only reachable inside the Docker network. On Azure the API has *internal* ingress
  only, the frontend is HTTPS-only, and the SQL firewall only admits Azure services.
- `/health` returns only *Healthy/Unhealthy*, no details.
- Production database: SQL Server **Express** edition (licence) with Docker Compose, Azure SQL on
  Azure; never reset by a script (`012_deploy.sh prod reset` is refused).
  *Known limitation:* the API connects with the server admin login (`sa` / `pcadmin`); before real
  customer data a dedicated database user with minimal rights (or a managed identity on Azure)
  replaces it.

### S7 – Path to production
Code reaches production only via `main`, after a release has been accepted on the acceptance
environment, and after a reviewer approved the deployment in the GitHub environment
`production` (nobody can approve their own deployment) – in Azure DevOps the *Approvals* check on
`projectcontrol-production`. A failed smoke test on Azure rolls back to the previous release
automatically. See [`CI_CD.md`](CI_CD.md).

---

### S8 – Disaster recovery
- Acceptance and production are backed up every night: verified (`CHECKSUM`), copied off the
  server, **AES-256 encrypted** with `BACKUP_KEY`, kept 35 days. On Azure: automatic point-in-time backups.
- `BACKUP_KEY` lives in the GitHub environments **and** in the team's password manager (offline copy).
- Backups contain production data: they are only restored into acceptance/production
  (`restore.yml`, production with approval) or into the throw-away DR test (`021`), never into
  test or a personal computer.
- Every restore first makes a safety backup; every month `dr-test.yml` proves the latest backup restores.
- Targets and runbooks: [`DISASTER_RECOVERY.md`](DISASTER_RECOVERY.md).

## Changing these rules
These rules are agreed by the whole team. A change (e.g. another threshold) goes through a
normal PR that updates this document **and** the configuration in the same PR, approved by
another team member.
