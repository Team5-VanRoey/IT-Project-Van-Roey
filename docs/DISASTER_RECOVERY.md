# Disaster recovery – Team IT2627T05

Goal: when something goes badly wrong – a bad release, lost or corrupted data, a server that is
gone, a leaked secret – we know **how much we can lose**, **how fast we are back**, and **exactly
what to do**. And we test it regularly, because a backup that was never restored is only a hope.

Related: [`CI_CD.md`](CI_CD.md) (deployments, rollback), [`QUALITY_AND_SECURITY.md`](QUALITY_AND_SECURITY.md)
(secrets), [`AZURE.md`](AZURE.md) (hosting on Azure).

## What can be lost, and what not

| Part | Where it lives | Can it be rebuilt? |
|---|---|---|
| Source code, scripts, workflows, compose files | Git (GitHub + every team member's clone) | yes, from any clone |
| Container images | GHCR, immutable, by digest; tags `src-…`, `sha-…`, `test/acc/prod` | yes: CI rebuilds them from Git; old versions stay in the registry |
| Settings per environment | `deploy/compose.<env>.yml` (Git) + GitHub environment variables | yes: `008_setup_environments.sh`, `015_setup_azure.sh` |
| Secrets (database password, SSH key, Sonar token) | GitHub environment secrets | yes: generate new ones with `008` / `015` |
| **BACKUP_KEY** | GitHub secrets **+ the team's password manager** | **no** – without it the backups cannot be decrypted. Keep the offline copy. |
| **Database data** (acceptance, production) | SQL Server volume on the server / Azure SQL | **only from a backup** – this is what DR protects |
| Database data (test, dev) | disposable test data | not needed: the CD and migrations recreate it |

## Targets per DTAP environment (RPO / RTO)

**RPO** = how much data we may lose at most. **RTO** = how long until the environment works again.

| | Environment | Backup | RPO | RTO | How we recover |
|---|---|---|---|---|---|
| **D** | Development | none | – | 15 min | `sh scripts/012_deploy.sh dev reset` + `dev` |
| **T** | Test | none (test data) | – | 30 min | *Redeploy* (same images) or a new server + CD; data is recreated |
| **A** | Acceptance | nightly, kept 35 days | 24 h | 2 h | *Restore* workflow + *Redeploy* |
| **P** | Production – Docker Compose | nightly, kept 35 days, **monthly restore test** | 24 h | 2 h | *Restore* workflow (approval) + *Redeploy* |
| **P** | Production – Azure | Azure SQL automatic backups, point-in-time | ≈ 10 min | 1 h | *Restore* workflow with a point in time |

Before risky work (a migration that drops or converts data) make an extra backup by hand:
`sh scripts/019_backup.sh prod` (or *Actions → Backup → Run workflow*). That makes the RPO zero
for that change.

## How the backups work

| | What | Where |
|---|---|---|
| `scripts/019_backup.sh <env>` | SQL Server `BACKUP … WITH CHECKSUM` + `RESTORE VERIFYONLY`, copied **off the server**, gzip, **AES-256 encrypted** (`BACKUP_KEY`), SHA-256 checksum, metadata with the app version (commit, image versions) | runs on the GitHub runner, talks to the server over SSH |
| `.github/workflows/backup.yml` | every night 01:23 UTC for acceptance and production; stores the encrypted backup as an artifact for **35 days** | GitHub (not on the server: server and backups never disappear together) |
| `scripts/020_restore.sh <env> <file\|latest>` | checksum → decrypt → **safety backup of the current database** → stop API → `RESTORE … WITH REPLACE, CHECKSUM` → start API → row counts → smoke test | |
| `scripts/020_restore.sh <env> --time <UTC>` | Azure: point-in-time restore to a new database, swapped in under the original name (old one kept) | |
| `.github/workflows/restore.yml` | the restore as a workflow: production needs a reviewer's approval, the reason is logged, the safety backup is kept 30 days | |
| `scripts/021_dr_test.sh` + `.github/workflows/dr-test.yml` | **monthly restore test**: the latest production backup is restored into a throw-away environment on the runner with the matching app version, smoke test must pass, recovery time is measured | never touches a real server |

Why the backups are encrypted: the repository is public; artifacts are only downloadable for
people with access, but encrypted backups stay safe even if one leaks (security rule S3). They are
**production data**: never restore them into test or a personal computer except through `021`
(which deletes the throw-away environment afterwards).

## Runbooks

Always: say in the team channel that you are handling an incident, and write down the times
(for the incident report). Take a backup before changing anything, if the database still works.

### 1. A release breaks the application (data is fine)
1. *Actions → Redeploy → Run workflow*, environment = the broken one, commit = the last good one
   (see the *CD* run history or `/version` before the incident). Production: approval needed.
   On Azure a failed smoke test already rolled back automatically.
2. Check `/version` and the smoke test in the run.
3. Fix the bug through a normal `bugfix/` or `hotfix/` branch.

RTO: ~15 minutes. No data lost.

### 2. Data is wrong or lost (bad migration, wrong delete, corruption)
1. Stop the damage: if needed, redeploy the previous version (runbook 1), so nothing keeps writing.
2. Choose the moment to go back to: the last backup **before** the problem (*Actions → Backup*
   runs, or the metadata `.json`). On Azure: a time just before the problem.
3. *Actions → Restore → Run workflow* (from `main` for production, `release/*` for acceptance):
   environment, backup run id (empty = latest) or point in time, reason (ticket).
   Production: a second team member approves.
4. The run makes a safety backup first, restores, shows the row counts and runs the smoke test.
5. The output says which app version belongs to the backup. If that differs from what runs now
   (the schema may differ), redeploy that commit (runbook 1).
6. Data entered between the backup and the restore is lost (RPO): inform the users.

### 3. The server is gone (hardware, deleted, hacked)
1. New server: Docker + Compose v2, user `deploy` in the `docker` group, SSH key (see `CI_CD.md`).
   If the old server was **hacked**: also runbook 4 (new secrets, new SSH key).
2. Update `DEPLOY_HOST` and `DEPLOY_KNOWN_HOSTS` in the GitHub environment (and in `backup`).
3. *Actions → Redeploy* the version that ran before (tag `prod` / `acc` in the registry shows it):
   this creates the containers and an empty database.
4. *Actions → Restore* with the latest backup (runbook 2, steps 3–5).
5. Check the smoke test and `/version`, then make one manual backup (*Actions → Backup*).

RTO: ~2 hours, most of it preparing the server. RPO: up to 24 hours.

On Azure: run `sh scripts/015_setup_azure.sh <env>` (recreates everything that is missing),
then *Redeploy*; if the database itself is gone, restore it from the Azure backups
(as long as the SQL server still exists, a deleted database can be restored in the portal:
SQL server → *Deleted databases*).

### 4. A secret leaked (password, key, token)
1. Revoke/rotate it **first** (removing it from Git is not enough – the repository is public):
   - database password: new value in the GitHub environment, update the password in SQL Server
     (`ALTER LOGIN sa WITH PASSWORD = …`) and redeploy;
   - SSH key: new key pair, replace `authorized_keys` on the server and the `DEPLOY_SSH_KEY` secret;
   - Sonar token: revoke in SonarQube, run `007` again;
   - `BACKUP_KEY`: new key for new backups (`gh secret set BACKUP_KEY …` in backup, acceptance,
     production); **keep the old key** in the password manager until the old backups expire
     (35 days) – to restore an older backup, set the old key temporarily.
2. Check the logs for misuse; report it the same day.

### 5. GitHub is unavailable
- Code: every clone is a full copy. Images that already run keep running.
- Deploy by hand from a clone: `sh scripts/012_deploy.sh <env>` with `API_IMAGE`/`WEB_IMAGE` set to
  the digests of the last run (see a recent *CD* run summary) – needs the registry.
- Backups: copy the latest backups from GitHub to a second place periodically if the team needs
  that extra safety (e.g. an Azure Storage account); the restore script works with any copy and
  the `BACKUP_KEY` from the password manager.

## Testing the recovery

| What | How often | How |
|---|---|---|
| Restore test of the latest production backup | **monthly, automatic** | `dr-test.yml` (red = backups cannot be trusted: fix first) |
| Nightly backups succeed | daily | `backup.yml` – a red run is picked up the same day |
| Full exercise (runbook 2 on acceptance, or runbook 3 with a fresh test server) | once per semester | the team, timed against the RTO; findings into this document |
| Restore script changed | every change | run `021_dr_test.sh` locally on a backup before merging |

## Setup (once, by the admin)
1. `sh scripts/008_setup_environments.sh <reviewers>` – also creates the environment `backup` and the
   `BACKUP_KEY` (same key in `backup`, `acceptance`, `production`). **Put the key in the team's
   password manager** and delete the file the script wrote.
2. In the environment `backup` (Settings → Environments → backup), for the server(s) with acceptance
   and production: secret `DEPLOY_SSH_KEY`; variables `DEPLOY_HOST` (or `DEPLOY_HOST_ACC` and
   `DEPLOY_HOST_PROD`), `DEPLOY_KNOWN_HOSTS`, `DEPLOY_USER`. On Azure: `DEPLOY_TARGET=azure`
   (or `DEPLOY_TARGET_PROD=azure`).
3. *Actions → Backup → Run workflow*, then *Actions → DR test → Run workflow*: both green = DR works.

Until there is a real server, the CD deploys on the runner (temporary): there is nothing to back
up yet, and `backup.yml` / `dr-test.yml` say so instead of failing.
