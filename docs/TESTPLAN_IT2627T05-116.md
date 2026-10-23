# Test plan IT2627T05-116 – Every change checked automatically

Proves that the user story and its two subtasks are done:
- **IT2627T05-171** CI/CD-pipeline opzetten (set up the CI/CD pipeline)
- **IT2627T05-183** Kwaliteitsregels en securitybeleid vastleggen (define quality rules and security policy)

For every "done when" item there is a **positive test** (it works) and, where possible, a
**negative test** (the pipeline really stops a mistake). Record the evidence for every test
(screenshot or link to the run) and attach it to the Jira ticket.

## How it works now (without Azure)

```
feature/IT2627T05-XX ──PR──▶ develop
      │                        │
  CI on the PR             CI again ──▶ CD Test
  7 required checks        (images already built   1. only an approved merge
  merge blocked            on the PR: reused)      2. look up + scan the images of this commit
  until all green                                  3. deploy with Docker Compose
  + 1 approval                                     4. smoke test (/, /health, /api/projects, /version)
```

- There is **no server and no Azure yet**. The GitHub environment `test` has no `DEPLOY_HOST` and
  no `DEPLOY_TARGET=azure`, so *CD Test* deploys **on the GitHub runner itself**: the containers
  really start, the database really migrates, the smoke test really runs – but the environment
  disappears after the run. The evidence is the green run with the smoke test in its log.
  On the runner the database gets a random throw-away password, so *CD Test* works even before
  the admin ran `008` (P2).
- Later, without changing any code:
    - own server: `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, … in the environment `test` (`docs/CI_CD.md`);
    - Azure: `sh scripts/015_setup_azure.sh test` (`docs/AZURE.md`).
- SonarQube runs on SonarQube Cloud (Free plan, gate *Sonar way*, see
  `docs/QUALITY_AND_SECURITY.md` Q3).

## Preparation (once)

| Step | Who | Command / action | Status |
|---|---|---|---|
| P1 | admin | SonarQube: `sh scripts/007_setup_sonarqube.sh` | ✅ done |
| P2 | admin | `sh scripts/008_setup_environments.sh <reviewer1> <reviewer2>` – not needed for the tests below, **required before the first sprint review / release** (production approval, branch rules per environment, `BACKUP_KEY`; see `docs/GITFLOW.md` → *Delivering to main*) | |
| P3 | admin | `sh scripts/001_setup_github.sh` (ruleset with all required checks) | ✅ done |
| P4 | everyone | `sh scripts/002_setup_hooks.sh` + Gitleaks installed | |
| P5 | you | branch `feature/IT2627T05-116` pushed with all files | ✅ done |

Needed locally: Git Bash or WSL, Docker Desktop, .NET 10 SDK, Node.js 22, Python 3, `gh`.

## Part A – Testing locally (before opening a PR)

The same scripts as the pipeline, so what passes here also passes on GitHub.

| ID | What | Command | Expected |
|---|---|---|---|
| L1 | Build + tests + 80% coverage | `sh scripts/009_build_test.sh` | `RESULT: build, tests and coverage OK`; backend and frontend coverage ≥ 80% in the output |
| L2 | Vulnerable dependencies | `sh scripts/010_scan_dependencies.sh` | `RESULT: no HIGH/CRITICAL vulnerabilities` |
| L3 | Secrets in the history | `sh scripts/005_scan_secrets.sh` | `RESULT: no secrets found.` |
| L4 | Hooks + PR check | `sh scripts/003_test_hooks.sh` | `Result: 31 passed, 0 failed` |
| L5 | Whole application locally (D of DTAP) | `cp deploy/env/dev.env.example deploy/env/dev.env` (fill in a password), then `sh scripts/012_deploy.sh dev` | containers build and start, smoke test `passed`; http://localhost:8080 shows the app, http://localhost:8080/version shows `"environment":"dev"` |
| L6 | Build the images like the CI | `sh scripts/014_images.sh build` | both images build without errors |
| L7 | Clean up | `sh scripts/012_deploy.sh dev down` | containers stopped |

Optional, SonarQube locally: `docker compose -f deploy/compose.sonarqube.yml up -d` →
http://localhost:9000 (admin/admin) → create a token →
`SONAR_HOST_URL=http://localhost:9000 SONAR_TOKEN=<token> sh scripts/011_sonar_scan.sh`.

## Part B – IT2627T05-171: CI/CD pipeline

### B1 · Build, tests and SonarQube on every PR
1. Open the PR `feature/IT2627T05-116` → `develop` with the completed PR template.
2. At the bottom of the PR these checks appear: *Gitflow & PR template*, *Secret scan*,
   *Build & test*, *SonarQube backend (C#)*, *SonarQube frontend (React)*, *Dependency scan*,
   *Docker build & scan*.

**Expected:** all seven green. *Build & test* shows the coverage in its log; both SonarQube checks
end with `QUALITY GATE STATUS: PASSED`, the SonarQube bot posts "Quality Gate passed" on the PR
(one comment per project), and the PR appears in SonarQube Cloud under *Pull Requests*.
**Evidence:** screenshot of the checks and the SonarQube comments + link to SonarQube.

### B2 · Merge only when everything passes (negative tests)
Create a separate test branch that you **never merge**:
```bash
git checkout develop && git pull
git checkout -b feature/IT2627T05-116-demo-fail
```

| Test | Change on the test branch | Expected on the PR |
|---|---|---|
| B2a – failing test | in `deelproject1/frontend/tests/App.test.tsx`: change `'Aanmelden'` in the first test to `'Fout'` | *Build & test* red |
| B2b – no approval | (all checks green, no review yet) | *Merge* button disabled: "Review required" |
| B2c – template not filled in | empty the PR description | *Gitflow & PR template* red |

Commit every change as `IT2627T05-116: demo ... (do not merge)`, push, open a PR to `develop`.
**Expected:** GitHub shows "Merging is blocked" and names the missing check or review – also for
an admin. **Evidence:** screenshot. Then close the PR **without merging**.

### B3 · Deployment to the test environment after a merge on develop
1. Have a team member **approve** the real PR (B1) and merge it.
2. *Actions*: first *CI* on `develop`, then **CD Test** starts automatically.

**Expected in the log of *CD Test*:**
- `0. Only approved merges are deployed` → `OK: … came into 'develop' through PR #…, approved by 1 …`
- `1. Resolve the images CI built` → `API_IMAGE=ghcr.io/…@sha256:…` (nothing rebuilt)
- `3. Deploy` → `Smoke test passed.` with `OK deployed version is live (<commit>)` and the
  `/version` output `{"environment":"test","commit":"…"}`
- summary: `test: success`, the commit, both image digests with their `src-…` version, target
  "Docker Compose on the GitHub runner (temporary)" and "Same image digests as in the other
  environments: built once by CI, never rebuilt here."
- the notice "No DEPLOY_HOST or Azure for 'test': deploying on the GitHub runner (temporary)" is
  expected as long as there is no server or Azure.

**Evidence:** link to the run + screenshot of the summary. On the repository home page,
*Deployments → test* shows a green deployment of that commit; under *Packages* the images
`projectcontrol-api` and `projectcontrol-web` carry the tags `src-…`, `sha-<commit>` and `test`.

**If *CI* on `develop` is red on the SonarQube checks right after the first merge:** the very first
analysis of `develop` is only the starting point for "new code", so SonarQube Cloud has no gate
status yet (`curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=Team5-VanRoey_IT-Project-Van-Roey_frontend&branch=develop"`
returns `"status":"NONE"`) and the scanner reports that as FAILED. *Re-run failed jobs* once; from
the second analysis on the gate is computed and *CD Test* starts.

### B4 · Look at the deployed test version yourself (optional)
The test environment on the runner is gone after the run, but the same images can be started
locally (nothing is built):
```bash
gh auth refresh -s read:packages
gh auth token | docker login ghcr.io -u <github-username> --password-stdin
git checkout develop && git pull
cp deploy/env/test.env.example deploy/env/test.env    # fill in MSSQL_SA_PASSWORD
sh scripts/012_deploy.sh test
```
**Expected:** only `pull` of `…@sha256:…` (no build), `Smoke test passed`; http://localhost:8081
shows the app and http://localhost:8081/version shows `"environment":"test"` with the same commit
and image versions as the *CD Test* summary. Clean up: `sh scripts/012_deploy.sh test reset`.

## Part C – IT2627T05-183: quality and security rules

### C1 · SonarQube Quality Gate and minimum test coverage of 80%
| Test | How | Expected |
|---|---|---|
| C1a – gate set up | SonarQube Cloud → project `…Van-Roey` → *Administration → Quality Gate* | *Sonar way* (Free plan), with "Coverage on New Code ≥ 80%"; same for `…_frontend` |
| C1b – 80% in the build | `sh scripts/009_build_test.sh` | backend and frontend coverage shown, minimum 80% |
| C1c – threshold works (negative) | `MIN_COVERAGE=101 sh scripts/009_build_test.sh backend` | `FAILED: line coverage … is below the minimum of 101%` – proves the threshold is really enforced |
| C1d – gate fails on poor new code (negative) | on the demo branch: new file `deelproject1/frontend/src/demo.ts` with a function of about 20–30 lines without tests, open a PR | *SonarQube frontend (React)* red ("Coverage on New Code < 80%") and *Build & test* red (frontend threshold) |

Note on C1d: SonarQube only applies the coverage condition from 20 new lines of code onwards, so
the demo function must be at least that long.

### C2 · Security rules for vulnerabilities, dependencies and secrets
| Test | How | Expected |
|---|---|---|
| C2a – vulnerable dependency (negative) | on the demo branch: `cd deelproject1/frontend && npm install lodash@4.17.20`, commit, push | *Dependency scan* red: lodash, severity **high** |
| C2b – secret is blocked (negative, **local only, never push**) | see below | commit rejected: `REJECTED: Gitleaks found a possible secret` (rule `github-pat`) |
| C2c – secret scan on the PR | (automatic) | *Secret scan* green on the real PR |
| C2d – vulnerabilities in images | (automatic) | *Docker build & scan* green; the log shows the Trivy scan of both images |
| C2e – weekly scan | after a Monday: *Actions → CI*, run with event `schedule` on `develop` | green run in which only *Dependency scan* ran (the other jobs *skipped*) |

C2b – generate a **fake** token (random, not a real key) and try to commit it:
```bash
printf 'github_token = "ghp_%s"\n' "$(head -c 300 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)" > demo-secret.txt
git add demo-secret.txt
git commit -m "IT2627T05-116: demo secret (must be rejected)"     # must be rejected
git rm --cached -q demo-secret.txt && rm demo-secret.txt         # clean up
```
Never use `--no-verify`.

### C3 · Rules documented
| Document | Content |
|---|---|
| `docs/QUALITY_AND_SECURITY.md` | rules Q1–Q5 and S1–S8, each with the check that enforces it |
| `docs/CI_CD.md` | pipeline, DTAP, what to do when a check is red |
| `docs/GITFLOW.md` | branches, PRs, scripts |
| `docs/DISASTER_RECOVERY.md` | backups and recovery per environment |

**Evidence:** link to the files on `develop` after the merge.

## Checklist

| Ticket | Done when | Tests | ✓ |
|---|---|---|---|
| 171 | Build, tests and SonarQube on every PR | B1, L1 | |
| 171 | Merge only when everything passes | B2a, B2b, B2c, C1d, C2a | |
| 171 | Deployment to the test environment after a merge on develop | B3 | |
| 183 | SonarQube Quality Gate and minimum 80% test coverage set up | C1a–C1d | |
| 183 | Security rules for vulnerabilities, dependencies and secrets defined | C2a–C2e | |
| 183 | Quality and security rules documented | C3 | |
| 184 | Built and deployed after an approved merge, image version traceable, smoke test | B3 (B4 optional) | |
| 116 | Acceptance criteria of the story | all of the above | |

Afterwards: demo PRs closed without merging, time logged on IT2627T05-116.

Not part of this story: acceptance (`release/*`) and production (`main`) use the same workflows
and are tested at the first release (see `docs/GITFLOW.md` → *Delivering to main*).