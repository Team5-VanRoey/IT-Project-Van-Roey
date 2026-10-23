# CI/CD pipeline & DTAP – Team IT2627T05

Goal: every change is built, tested and checked automatically, so mistakes show up early;
only a fully green change can be merged; and every merge on `develop` is deployed to the test
environment automatically.

The rules behind the checks (80% coverage, Quality Gate, security) are in
[`QUALITY_AND_SECURITY.md`](QUALITY_AND_SECURITY.md). Hosting on Azure and the ready-made
Azure DevOps pipelines are described in [`AZURE.md`](AZURE.md): every step below is a script in
`scripts/`, so it runs the same in GitHub Actions and in Azure Pipelines.

## Build once, deploy everywhere

A container image is built **once** and that same image moves through every environment.
Test, acceptance and production never build anything; they only get other **settings**.

```
                 CI (ci-dev.yml, job "Docker build & scan")               CD (cd-*.yml, redeploy.yml)
 source  ──▶  version = src-<git tree hash of the folder>  ──▶  registry  ──▶  test ──▶ acceptance ──▶ production
               already in the registry? reuse it                ghcr.io     same digest   same digest    same digest
               otherwise: build ▶ Trivy ▶ push (one time)                    (repo@sha256:…)
```

- **One version per source.** `projectcontrol-api` is versioned by `deelproject1/backend`,
  `projectcontrol-web` by `deelproject1/frontend` (`src-<12 chars of the Git tree hash>`). A change
  in only the frontend rebuilds only the web image; a commit that changes neither (docs, workflows)
  rebuilds nothing.
- **Built on the PR, reused after the merge.** The PR must be up to date with its target, so the
  source on the PR equals the source on `develop` after the merge: CI after the merge finds the
  image and only adds the tag `sha-<commit>`. A `release/*` branch and the merge into `main`
  normally contain the same source again, so **production runs the exact image that was tested
  and accepted**.
- **Deployed by digest.** The CD resolves the images of a commit to `repo@sha256:…`
  (`014_images.sh resolve`) and deploys those; a tag can never point to something else halfway.
- **No settings in the image.** Everything per environment comes in at runtime:
  `deploy/compose.<env>.yml`, `deploy/env/<env>.env` / GitHub environment, or the container app
  settings on Azure. The frontend uses relative URLs (`/api`) and nginx gets `API_UPSTREAM`.
- **Visible in the registry.** After a successful deployment the images get the tag `test`, `acc`
  or `prod`, so the registry shows which version runs where.
- Only **D**evelopment builds images itself, from your working copy (`012_deploy.sh dev`).

## The flow

```
feature/IT2627T05-XX ──PR──▶ develop ──────────────▶ release/x.y.z ──PR──▶ main
        │                       │                          │                  │
   CI on the PR            CI + CD Test              CI + CD Acceptance   CI + CD Production
   (merge blocked          deploy to TEST            deploy to ACCEPTANCE  approval ▶ PRODUCTION
    until all green)       (automatic)               (automatic)           (manual approval)
```

| | Environment | Branch | When | Workflow | Compose files |
|---|---|---|---|---|---|
| **D** | Development | `feature/*`, `bugfix/*` | your own computer | – (CI on the PR) | `compose.yml` + `compose.dev.yml` |
| **T** | Test | `develop` | automatically after every **approved** merge | `cd-test.yml` | `compose.yml` + `compose.test.yml` |
| **A** | Acceptance | `release/*` | automatically after every push | `cd-acceptance.yml` | `compose.yml` + `compose.acc.yml` |
| **P** | Production | `main` | after the merge **and a manual approval** | `cd-production.yml` | `compose.yml` + `compose.prod.yml` |

## 1. CI – every Pull Request (`.github/workflows/ci-dev.yml`)

Runs on every PR to `develop` or `main`, and again on `develop`, `release/*` and `main` after
the merge. Four jobs run in parallel; **all four are required checks**, together with
*Gitflow & PR template* and *Secret scan*:

| Check | Script (run it locally too) | What it does | Fails when |
|---|---|---|---|
| **Build & test** | `sh scripts/009_build_test.sh` | .NET restore/build (Release) + tests with coverage; frontend `npm ci`, lint, build, vitest with coverage | build/lint error, a failing test, coverage < 80% |
| **SonarQube quality gate** | `sh scripts/011_sonar_scan.sh` | analyses backend and frontend in SonarQube and waits for the Quality Gate | gate red (see Q3) |
| **Dependency scan** | `sh scripts/010_scan_dependencies.sh` | NuGet (incl. transitive) and npm audit | HIGH/CRITICAL vulnerability |
| **Docker build & scan** | `sh scripts/014_images.sh ensure` | validates the 4 DTAP compose files; per image: reuse when this source version exists, otherwise build, Trivy scan and push **once** | build error, invalid compose, HIGH/CRITICAL in image |

Test results and coverage reports are attached to every run (*Artifacts → test-results*).

### Merge only when everything passes
The ruleset *Protect main and develop* (`scripts/001_setup_github.sh`) requires:
all checks above green, the branch up to date with its target, 1 approval from another team
member and all conversations resolved. Without that, GitHub disables the merge button –
also for admins (no bypass).

## 2. CD – deployment per environment

`cd-test.yml`, `cd-acceptance.yml` and `cd-production.yml` start **when the CI workflow has
finished** for a push on their branch, and only continue when CI was **green**. They deploy
the images CI built for exactly that commit and **build nothing**. All three use the reusable
workflow `_deploy.yml`:

0. **Approved merge** (test and production) – `018_check_approved_merge.sh`: the commit must have
   reached `develop`/`main` through a merged PR that another team member approved. A direct push
   (e.g. with a disabled ruleset) is never deployed.
1. **Resolve** – `014_images.sh resolve`: the image digests of this commit (fails if CI did not build them).
2. **Scan again** – `014_images.sh scan-deployed`: Trivy on those exact images, for vulnerabilities
   published since the build.
3. **Deploy** – in the GitHub environment (`test` / `acceptance` / `production`), to the target
   in its variable `DEPLOY_TARGET`:
   - `azure` – `scripts/016_deploy_azure.sh <env>` on Azure Container Apps (login with OIDC),
     smoke test, **automatic rollback** to the previous images when it fails. Set up by
     `scripts/015_setup_azure.sh`, see [`AZURE.md`](AZURE.md).
   - `compose` (default) – `scripts/012_deploy.sh <env> up` pulls the images, starts the
     containers, waits until they are healthy and runs the smoke test.

   The smoke test (`013_smoke_test.sh`) checks the frontend, `/health` and `/api/projects`.
   If anything fails, the run is red and shows the logs.
4. **Record** – `014_images.sh tag <env>`: the images get the tag of the environment.

### Which version runs where? (traceability)
| Where | What you see |
|---|---|
| `https://<environment>/version` | `{"environment":"test","commit":"<sha>","api":"src-…","web":"src-…"}` – set at deploy time |
| Smoke test | step 4 fails unless `/version` reports exactly the deployed commit (the new version is really live) |
| Run summary (*Actions → CD Test*) | commit, image digests (`repo@sha256:…`) and versions, URL |
| *Code → Deployments* / environment page | every deployment per environment with its commit (GitHub keeps the history) |
| Registry (ghcr.io packages) | tags `src-…` (source version), `sha-<commit>`, and `test` / `acc` / `prod` on the running image |
| Image labels | `org.opencontainers.image.revision` = commit, `…version` = `src-…` (`docker inspect`) |

**Rollback or re-deploy** without building: *Actions → Redeploy → Run workflow* (`redeploy.yml`),
choose the environment and the commit SHA of the version you want (from the branch of that
environment; production still needs approval).

Production waits for a reviewer: **Actions → the run → Review deployments → Approve**.
Every environment only accepts deployments from its own branch (deployment branch policy),
so a manual *Run workflow* from another branch is refused.

### Where is deployed?
With `DEPLOY_TARGET=azure` all settings are written by `015_setup_azure.sh` (`AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `APP_URL`); see `AZURE.md`.
For the Docker Compose target, per GitHub environment (**Settings → Environments → <env>**):

| Setting | Kind | Meaning |
|---|---|---|
| `MSSQL_SA_PASSWORD` | secret | database password (generated by `008`) |
| `WEB_PORT` | variable | published port (test 8081, acceptance 8082, production 8083) |
| `DEPLOY_HOST` | variable | server with Docker; **empty = deploy on the GitHub runner** |
| `DEPLOY_USER` | variable | SSH user on that server (default `deploy`, member of the `docker` group) |
| `DEPLOY_SSH_KEY` | secret | private SSH key of that user |
| `DEPLOY_KNOWN_HOSTS` | variable | output of `ssh-keyscan <server>` (host key check) |
| `APP_URL` | variable | public URL, shown on the run and used by the smoke test |
| `MIGRATE_ON_STARTUP` | variable | `true` (default): the API applies EF migrations at startup |

Without `DEPLOY_HOST` the release is deployed on the GitHub runner itself: the deployment,
health checks and smoke test are real, but the environment is gone when the job ends. As soon
as the team has a server, set the variables above – nothing else changes. One server can host
all three environments side by side: each has its own Compose project name, port and database volume.

Preparing a server (once): install Docker + Compose v2, create user `deploy` in the `docker`
group, add the public key to `~deploy/.ssh/authorized_keys`, open the `WEB_PORT`s
(or put a reverse proxy with HTTPS in front).

## 3. DTAP with Docker Compose (`deploy/`)

| File | Content |
|---|---|
| `compose.yml` | base for all environments: `db` (SQL Server), `api`, `web` (nginx + frontend, proxies `/api` and `/health`), health checks, log rotation |
| `compose.dev.yml` | **D**: the only environment that builds (from your working copy); exposes SQL (1433) and the API (5244) for debugging |
| `compose.test.yml` | **T**: the images CI built (`API_IMAGE`/`WEB_IMAGE`), memory limit |
| `compose.acc.yml` | **A**: like production: read-only containers, limits |
| `compose.prod.yml` | **P**: read-only containers, limits, SQL Server Express |
| `compose.sonarqube.yml` | local SonarQube server (optional) |
| `env/<env>.env.example` | settings per environment; copy to `env/<env>.env` (ignored by Git) |

### Scripts
```bash
# D – run the whole application on your own computer
cp deploy/env/dev.env.example deploy/env/dev.env     # choose a password
sh scripts/012_deploy.sh dev                         # http://localhost:8080
sh scripts/012_deploy.sh dev logs                    # logs
sh scripts/012_deploy.sh dev down                    # stop (database is kept)
sh scripts/012_deploy.sh dev reset                   # stop and delete the database

# Same checks as the CI, before you open a PR
sh scripts/009_build_test.sh                         # Q1 + Q2
sh scripts/010_scan_dependencies.sh                  # S2
SONAR_TOKEN=... sh scripts/011_sonar_scan.sh         # Q3 (SonarCloud)

# Q3 against a local SonarQube server
docker compose -f deploy/compose.sonarqube.yml up -d # http://localhost:9000, admin/admin
SONAR_HOST_URL=http://localhost:9000 SONAR_TOKEN=<token> sh scripts/011_sonar_scan.sh

# T/A/P by hand (normally the CD workflows do this), e.g. test on your own Docker
cp deploy/env/test.env.example deploy/env/test.env   # choose a password
docker login ghcr.io                                 # when the packages are private
sh scripts/012_deploy.sh test                        # images CI built for this commit

# Images
sh scripts/014_images.sh versions                    # version of each image for this commit
sh scripts/014_images.sh resolve                     # the digests the CD would deploy
sh scripts/014_images.sh build                       # try a Dockerfile locally (tag 'local')
```
`012_deploy.sh prod reset` is always refused.

## 4. One-time setup (admin)

In this order, with the GitHub CLI signed in as admin:

```bash
SONAR_TOKEN=<admin token> sh scripts/007_setup_sonarqube.sh   # SonarQube projects, quality gate, SONAR_TOKEN secret
sh scripts/008_setup_environments.sh <reviewer1> <reviewer2>   # GitHub environments test/acceptance/production
sh scripts/001_setup_github.sh                                 # ruleset with all required checks
sh scripts/015_setup_azure.sh test|acc|prod                    # optional: host the environment on Azure (AZURE.md)
```

SonarQube Cloud **Free** has two limits the scripts take into account: a custom quality gate can
be created but not assigned, so both projects use the built-in *Sonar way* (80% coverage on new
code; the overall 80% is enforced by *Build & test*, see `QUALITY_AND_SECURITY.md` Q3), and only
the main branch – set to `develop` by `007` – and PRs into it are analysed. PRs into `main`
(release, hotfix) skip the Sonar step; that code was analysed on its way into `develop`.

For SonarCloud: first sign in at sonarcloud.io with GitHub and import the organization
`team5-vanroey` (free for public repositories). For a SonarQube server instead, set
`SONAR_HOST_URL` when running `007`; it stores the URL as repository variable for the CI.

Packages on GHCR: after the first deployment, open the package `projectcontrol-api` /
`projectcontrol-web` → *Package settings* → link it to this repository (or make it public)
so a server can pull it.

## 5. When a check is red

| Check | First step |
|---|---|
| Build & test | open the log: failing test name or "coverage below 80%" with the file list (lowest % first). Same command locally: `009_build_test.sh` |
| SonarQube quality gate | open the link in the log → *Pull Request* tab in SonarQube; fix the new issues / add tests |
| Dependency scan | update the package mentioned (`dotnet add package X`, `npm update X` / `npm audit fix`) |
| Docker build & scan | Dockerfile error, or update the base image tag; Trivy lists the package + fixed version |
| CD: "No images for <sha>" | CI did not build this commit (CI red or still running, or a fork PR): fix CI first |
| CD: deployment | the run shows `docker compose ps` and the last API/web log lines; fix via a normal PR |

## 6. Disaster recovery
Backups, restores and the monthly restore test per DTAP environment are described in
[`DISASTER_RECOVERY.md`](DISASTER_RECOVERY.md) (RPO/RTO, runbooks). In short: acceptance and
production are backed up every night (`backup.yml`, encrypted, off the server), restored with
`restore.yml` (production needs approval), and `dr-test.yml` proves every month that the latest
production backup really restores. A bad release is undone with *Redeploy* (no data restore needed).

Never "fix" a red check by lowering a threshold, adding an exclusion or skipping a test
without the team's agreement (see *Changing these rules* in `QUALITY_AND_SECURITY.md`).
