# Azure & Azure DevOps – Team IT2627T05

The project is built so it can move to Azure – and later, if needed, from GitHub to Azure DevOps –
**without changing the rules or rewriting the pipeline**. This document explains the choices,
the Azure setup and the migration path.

## Choices (and why)

| Part | Choice now | Why |
|---|---|---|
| Code + CI/CD | **GitHub + GitHub Actions** | Public repository: Actions minutes are free and unlimited. Azure DevOps' free tier for a new organisation is one parallel job and must often be requested first. |
| Code quality | **SonarQube Cloud Free** | Free for public projects, no server to manage, works with GitHub *and* Azure DevOps. |
| Hosting | **Azure Container Apps** + **Azure SQL Database free offer** | Same containers as Docker Compose, scales to zero, and both have a monthly free amount (see *Costs*). |
| Azure login from CI | **OIDC / workload identity federation** | No passwords or keys in GitHub or Azure DevOps (security rule S3). |
| Later on Azure DevOps | `azure-pipelines/` is ready | Same scripts, same checks, same DTAP. |

**The key design rule: every pipeline step is a script in `scripts/`.** GitHub Actions and Azure
Pipelines only install tools and call those scripts. That is why one set of rules
(`QUALITY_AND_SECURITY.md`) works on both, and why a move is configuration, not a rewrite.

```
            GitHub Actions (.github/workflows)      Azure Pipelines (azure-pipelines/)
                         \                                  /
                          '---------- scripts/ -----------'
   005 secrets · 009 build & test · 010 dependencies · 011 SonarQube · 014 images
   012 deploy (Docker Compose) · 016 deploy (Azure) · 013 smoke test · check_pr.py
```

## Target architecture on Azure

One resource group per DTAP environment (`test`, `acc`, `prod`), created by
`scripts/015_setup_azure.sh`:

```
rg-projectcontrol-<env>
├── cae-projectcontrol-<env>          Container Apps environment (Consumption plan)
│   ├── pc-<env>-web   public HTTPS   nginx + React; forwards /api and /health to the API
│   └── pc-<env>-api   internal only  ASP.NET Core API (not reachable from the internet)
└── sql-projectcontrol-<env>-<id>     Azure SQL server, firewall: Azure services only
    └── ProjectControl                serverless database on the free offer (auto-pause)
```

- **Development** stays on your own computer (`sh scripts/012_deploy.sh dev`, Docker Compose).
- The **same images** (built once by CI, deployed by digest) run on a Compose server and on Azure. The frontend finds the API
  through `API_UPSTREAM` (`http://api:8080` in Compose, `http://pc-<env>-api` on Azure).
- The database password is generated once and stored **only** as a secret of the API container app.
- Each environment has its own deploy identity (`github-projectcontrol-<env>`) that is
  Contributor on **its own resource group only**, and that only the matching GitHub environment
  can use (federated credential). The test pipeline can therefore never touch production.

### Costs

Azure is not free, but this setup stays within the free amounts for a student project:

| Service | Free amount | How we stay within it |
|---|---|---|
| Container Apps (Consumption) | first 180,000 vCPU-seconds, 360,000 GiB-seconds and 2 million requests per subscription per month | scale to zero (`AZURE_MIN_REPLICAS=0`), small sizes (API 0.5 vCPU, web 0.25 vCPU) |
| Azure SQL Database free offer | per database 100,000 vCore-seconds + 32 GB per month, max. 10 free databases per subscription | serverless, **auto-pause** when the free amount is used up (no extra cost; the database is then offline until next month) |
| Backups | Azure SQL automatic backups (point-in-time restore) are included | `restore.yml` / `020_restore.sh --time`; see `DISASTER_RECOVERY.md` |
| Logging | – | no Log Analytics workspace (`--logs-destination none`); use `az containerapp logs show` |
| Images | GHCR is free for public packages | packages made public, no Azure Container Registry needed |

Check before you start: the SQL free offer is not available on *Azure for Students Starter*
(it is on *Azure for Students*). Set a **budget alert** on the subscription (Cost Management →
Budgets, e.g. €5) so nobody is surprised. With `AZURE_MIN_REPLICAS=0` the first request after a
quiet period takes a few seconds, and up to a minute when the database was paused; the smoke
test waits for that.

## Setting up Azure (once, by the admin)

Needs the Azure CLI (`az login` with rights to create resources and role assignments) and the
GitHub CLI.

```bash
sh scripts/008_setup_environments.sh <reviewer1> <reviewer2>   # GitHub environments (if not done yet)
sh scripts/015_setup_azure.sh test                              # T
sh scripts/015_setup_azure.sh acc                               # A
sh scripts/015_setup_azure.sh prod                              # P
```

`015` also sets `DEPLOY_TARGET=azure` and the Azure variables on the GitHub environment, so the
**next** CD run deploys to Azure instead of Docker Compose. Nothing else changes:
CI on the PR → merge → CD → `scripts/016_deploy_azure.sh`, which deploys the image of exactly
the tested commit, runs the smoke test and **rolls back automatically** if the smoke test fails.

After the first CD run: make the packages `projectcontrol-api` and `projectcontrol-web` public on
GitHub (organisation → Packages → package → Package settings), or run `015` with
`GHCR_USERNAME`/`GHCR_TOKEN` so Azure can pull private images.

Going back to Docker Compose for an environment: set its variable `DEPLOY_TARGET` to `compose`.

## Moving to Azure DevOps (when the team decides to)

Everything that is checked on GitHub is also checked in Azure DevOps:

| GitHub | Azure DevOps | Where |
|---|---|---|
| `.github/workflows/ci-dev.yml` (required checks) | pipeline `projectcontrol-ci` + branch policy *Build validation* | `azure-pipelines/ci.yml` |
| `cd-test/acceptance/production.yml` | pipeline `projectcontrol-cd` (3 stages) | `azure-pipelines/cd.yml`, `templates/deploy.yml` |
| *Gitflow & PR template* (`pr-checks.yml`) | job *Gitflow & PR template* | `scripts/ado_check_pr.sh` → same `check_pr.py` |
| *Secret scan* (`secret-scan.yml`) | job *Secret scan* | same `005_scan_secrets.sh` |
| Ruleset: 1 approval, conversations resolved, checks green | branch policies on `develop`/`main` | `017_setup_azure_devops.sh` |
| Ruleset *Branch naming* | Repository → Security → branch permissions (create only `feature/IT2627T05-*`, …) | portal |
| GitHub environments + required reviewers | Azure DevOps environments + *Approvals* check | `017` + portal |
| Environment variables `AZURE_*` + OIDC | service connections with workload identity federation | portal |
| `SONAR_TOKEN` secret | variable group `projectcontrol-ci` | `017` |
| `backup.yml`, `restore.yml`, `dr-test.yml` | not yet as pipelines: run `019`/`020`/`021` from a scheduled / manual pipeline (same scripts) | `DISASTER_RECOVERY.md` |
| Weekly dependency scan (`schedule`) | scheduled trigger on `projectcontrol-ci` | `azure-pipelines/ci.yml` |
| Local hooks (`.githooks/`) | unchanged | – |
| Jira autolink | Jira's Azure DevOps integration, or keep the ticket in branch/commit (checked by `check_pr.py`) | – |

### Steps
1. Create the organisation and project at dev.azure.com. For a new organisation, request the free
   parallel job (*Organization settings → Parallel jobs*); this can take a few working days.
2. **Repos → Import repository** with the GitHub URL (history, branches and tags come along).
3. `SONAR_TOKEN=<token> sh scripts/017_setup_azure_devops.sh https://dev.azure.com/<org> <project>`
   creates the variable group, both pipelines, the three environments and the branch policies,
   and copies the PR templates to `.azuredevops/`.
4. Do the portal steps `017` prints at the end: Azure service connections per environment
   (*workload identity federation – automatic*, scoped to `rg-projectcontrol-<env>`), the GHCR
   registry connection, the approval on `projectcontrol-production`, the SonarQube Cloud binding.
5. Run `projectcontrol-ci` once on `develop`, approve its permissions, and open a test PR: all six
   checks must run and block the merge until green.
6. When everything works: make the GitHub repository read-only (Settings → Archive) so nobody
   pushes to the old place.

Azure resources (`015`) are reused unchanged; only the login moves from GitHub OIDC to the Azure
DevOps service connections. With `SKIP_GITHUB=1`, `015` no longer touches GitHub.

### Things to know about Azure DevOps
- Azure DevOps cannot pick a PR template from the **source** branch like our GitHub workflow does;
  the bugfix/hotfix/release templates appear in the template dropdown when creating the PR.
  The *Gitflow & PR template* job still checks the right template per branch type.
- SonarQube Cloud Free analyses only the main branch (we set it to `develop`) and PRs into it,
  on GitHub and on Azure DevOps alike (see `011_sonar_scan.sh`, `SONAR_BRANCH_ANALYSIS`).
- Private Azure DevOps projects have one free parallel job: the six CI jobs then run one after
  another (slower, still free). Public projects get more.

## Sources
- Azure SQL Database free offer: https://learn.microsoft.com/azure/azure-sql/database/free-offer
- Azure Container Apps pricing (free grant): https://azure.microsoft.com/pricing/details/container-apps/
- Container Apps – calling another app in the same environment: https://learn.microsoft.com/azure/container-apps/connect-apps
- Container Apps ingress (`--allow-insecure`): https://learn.microsoft.com/azure/container-apps/ingress-how-to
- SonarQube Cloud plans (Free: main-branch and PRs into it, no custom quality gates): https://docs.sonarsource.com/sonarcloud/administering-sonarcloud/managing-subscription/subscription-plans
