# Testplan IT2627T05-116 – Elke wijziging automatisch gecontroleerd

Bewijst dat de user story en haar twee subtaken af zijn:
- **IT2627T05-171** CI/CD-pipeline opzetten
- **IT2627T05-183** Kwaliteitsregels en securitybeleid vastleggen

Per "klaar wanneer"-punt is er een **positieve test** (het werkt) en waar mogelijk een
**negatieve test** (de pipeline houdt een fout echt tegen). Leg bij elke test het bewijs vast
(screenshot of link naar de run) en hang het aan het Jira-ticket.

## Hoe het nu werkt (zonder Azure)

```
feature/IT2627T05-XX ──PR──▶ develop
      │                        │
  CI op de PR              CI opnieuw ──▶ CD Test
  6 verplichte checks      (images al gebouwd    1. alleen een goedgekeurde merge
  merge geblokkeerd        op de PR: hergebruikt) 2. images van deze commit opzoeken + scannen
  tot alles groen                                 3. uitrollen met Docker Compose
  + 1 goedkeuring                                 4. smoke test (/, /health, /api/projects, /version)
```

- Er is **nog geen server en geen Azure**. De GitHub-omgeving `test` heeft geen `DEPLOY_HOST` en
  geen `DEPLOY_TARGET=azure`, dus *CD Test* rolt uit **op de GitHub-runner zelf**: de containers
  starten echt, de database migreert, de smoke test draait echt – maar de omgeving verdwijnt na
  de run. Het bewijs is de groene run met de smoke test in de log.
- Later, zonder iets aan de code te veranderen:
  - eigen server: `DEPLOY_HOST`, `DEPLOY_SSH_KEY`, … in de omgeving `test` ([`CI_CD.md`](CI_CD.md));
  - Azure: `sh scripts/015_setup_azure.sh test` ([`AZURE.md`](AZURE.md)).
- SonarQube draait op SonarQube Cloud (Free plan, gate *Sonar way*, zie
  [`QUALITY_AND_SECURITY.md`](QUALITY_AND_SECURITY.md) Q3).

## Voorbereiding (eenmalig)

| Stap | Wie | Commando / actie | Status |
|---|---|---|---|
| V1 | admin | SonarQube: `sh scripts/007_setup_sonarqube.sh` | ✅ gedaan |
| V2 | admin | `sh scripts/008_setup_environments.sh <reviewer1> <reviewer2>` | |
| V3 | admin | `sh scripts/001_setup_github.sh` (ruleset met alle verplichte checks) | |
| V4 | iedereen | `sh scripts/002_setup_hooks.sh` + Gitleaks geïnstalleerd | |
| V5 | jij | branch `feature/IT2627T05-116` met alle bestanden gepusht | |

Benodigd lokaal: Git Bash of WSL, Docker Desktop, .NET 10 SDK, Node.js 22, Python 3, `gh`.

## Deel A – Lokaal testen (voor je een PR opent)

Dezelfde scripts als de pipeline, dus wat hier slaagt, slaagt ook op GitHub.

| ID | Wat | Commando | Verwacht |
|---|---|---|---|
| L1 | Build + tests + 80% dekking | `sh scripts/009_build_test.sh` | `RESULT: build, tests and coverage OK`; dekking backend en frontend ≥ 80% in de uitvoer |
| L2 | Kwetsbare dependencies | `sh scripts/010_scan_dependencies.sh` | `RESULT: no HIGH/CRITICAL vulnerabilities` |
| L3 | Secrets in de historie | `sh scripts/005_scan_secrets.sh` | `RESULT: no secrets found.` |
| L4 | Hooks + PR-check | `sh scripts/003_test_hooks.sh` | `Result: 31 passed, 0 failed` |
| L5 | Hele applicatie lokaal (D van DTAP) | `cp deploy/env/dev.env.example deploy/env/dev.env` (wachtwoord invullen), dan `sh scripts/012_deploy.sh dev` | containers bouwen en starten, smoke test `passed`; http://localhost:8080 toont de app, http://localhost:8080/version toont `"environment":"dev"` |
| L6 | Images bouwen zoals de CI | `sh scripts/014_images.sh build` | beide images bouwen zonder fout |
| L7 | Opruimen | `sh scripts/012_deploy.sh dev down` | containers gestopt |

Optioneel, SonarQube lokaal: `docker compose -f deploy/compose.sonarqube.yml up -d` →
http://localhost:9000 (admin/admin) → token maken →
`SONAR_HOST_URL=http://localhost:9000 SONAR_TOKEN=<token> sh scripts/011_sonar_scan.sh`.

## Deel B – IT2627T05-171: CI/CD-pipeline

### B1 · Build, tests en SonarQube bij elke PR
1. Open de PR `feature/IT2627T05-116` → `develop` met de ingevulde PR-template.
2. Onderaan de PR verschijnen deze checks: *Gitflow & PR template*, *Secret scan*, *Build & test*,
   *SonarQube quality gate*, *Dependency scan*, *Docker build & scan*.

**Verwacht:** alle zes groen. *Build & test* toont de dekking in de log; *SonarQube quality gate*
eindigt met `QUALITY GATE STATUS: PASSED` en de PR verschijnt in SonarQube Cloud onder
*Pull Requests*. **Bewijs:** screenshot van de checks + link naar SonarQube.

### B2 · Merge alleen als alles slaagt (negatieve tests)
Maak een aparte testbranch die je **nooit merget**:
```bash
git checkout develop && git pull
git checkout -b feature/IT2627T05-116-demo-fail
```

| Test | Wijziging op de testbranch | Verwacht op de PR |
|---|---|---|
| B2a – falende test | in `deelproject1/frontend/src/App.test.tsx`: verander `'Aanmelden'` in de eerste test in `'Fout'` | *Build & test* rood |
| B2b – geen goedkeuring | (alle checks groen, nog geen review) | knop *Merge* uitgeschakeld: "Review required" |
| B2c – template niet ingevuld | maak de PR-beschrijving leeg | *Gitflow & PR template* rood |

Commit elke wijziging met `IT2627T05-116: demo ... (do not merge)`, push, open een PR naar `develop`.
**Verwacht:** GitHub toont "Merging is blocked" en noemt de check of de review die ontbreekt –
ook voor een admin. **Bewijs:** screenshot. Sluit daarna de PR **zonder merge**.

### B3 · Uitrol naar de testomgeving na merge op develop
1. Laat een teamlid de echte PR (B1) **goedkeuren** en merge hem.
2. *Actions*: eerst *CI* op `develop`, daarna start **CD Test** automatisch.

**Verwacht in de log van *CD Test*:**
- `0. Only approved merges are deployed` → `OK: … came into 'develop' through PR #…, approved by 1 …`
- `1. Resolve the images CI built` → `API_IMAGE=ghcr.io/…@sha256:…` (niets opnieuw gebouwd)
- `3. Deploy` → `Smoke test passed.` met `OK deployed version is live (<commit>)` en de
  `/version`-uitvoer `{"environment":"test","commit":"…"}`
- samenvatting: commit, image-digests, doel "GitHub runner (temporary)"

**Bewijs:** link naar de run + screenshot van de samenvatting. Onder *Code → Environments → test*
staat de uitrol met de commit.

## Deel C – IT2627T05-183: kwaliteits- en securityregels

### C1 · SonarQube Quality Gate en minimale testdekking van 80%
| Test | Hoe | Verwacht |
|---|---|---|
| C1a – gate ingesteld | SonarQube Cloud → project `…Van-Roey` → *Administration → Quality Gate* | *Sonar way* (Free plan), met "Coverage on New Code ≥ 80%"; zelfde voor `…_frontend` |
| C1b – 80% in de build | `sh scripts/009_build_test.sh` | dekking backend en frontend getoond, minimum 80% |
| C1c – grens werkt (negatief) | `MIN_COVERAGE=101 sh scripts/009_build_test.sh backend` | `FAILED: line coverage … is below the minimum of 101%` – bewijst dat de grens echt afdwingt |
| C1d – gate faalt op slechte nieuwe code (negatief) | op de demo-branch: nieuw bestand `deelproject1/frontend/src/demo.ts` met een functie van een tiental regels zonder test, PR openen | *SonarQube quality gate* rood ("Coverage on New Code < 80%") en *Build & test* rood (frontend-drempel) |

### C2 · Securityregels voor kwetsbaarheden, dependencies en secrets
| Test | Hoe | Verwacht |
|---|---|---|
| C2a – kwetsbare dependency (negatief) | op de demo-branch: `cd deelproject1/frontend && npm install lodash@4.17.20`, commit, push | *Dependency scan* rood: lodash, severity **high** |
| C2b – secret wordt tegengehouden (negatief, **lokaal, nooit pushen**) | zie hieronder | commit geweigerd: `REJECTED: Gitleaks found a possible secret` (regel `github-pat`) |
| C2c – secret scan op de PR | (automatisch) | *Secret scan* groen op de echte PR |
| C2d – kwetsbaarheden in images | (automatisch) | *Docker build & scan* groen; de log toont de Trivy-scan van beide images |
| C2e – wekelijkse scan | na een maandag: *Actions → CI*, run met event `schedule` op `develop` | groene run waarin alleen *Dependency scan* draaide (de andere jobs *skipped*) |

C2b – een **nep**-token genereren (willekeurig, geen echte sleutel) en proberen te committen:
```bash
printf 'github_token = "ghp_%s"\n' "$(head -c 300 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)" > demo-secret.txt
git add demo-secret.txt
git commit -m "IT2627T05-116: demo secret (must be rejected)"     # moet geweigerd worden
git rm --cached -q demo-secret.txt && rm demo-secret.txt         # opruimen
```
Gebruik nooit `--no-verify`.

### C3 · Regels gedocumenteerd
| Document | Inhoud |
|---|---|
| [`QUALITY_AND_SECURITY.md`](QUALITY_AND_SECURITY.md) | regels Q1–Q5 en S1–S8, elk met de check die ze afdwingt |
| [`CI_CD.md`](CI_CD.md) | pipeline, DTAP, wat te doen bij een rode check |
| [`GITFLOW.md`](GITFLOW.md) | branches, PR's, scripts |
| [`DISASTER_RECOVERY.md`](DISASTER_RECOVERY.md) | back-ups en herstel per omgeving |

**Bewijs:** link naar de bestanden op `develop` na de merge.

## Afvinklijst

| Ticket | Klaar wanneer | Tests | ✓ |
|---|---|---|---|
| 171 | Build, tests en SonarQube bij elke PR | B1, L1 | |
| 171 | Merge alleen als alles slaagt | B2a, B2b, B2c, C1d, C2a | |
| 171 | Uitrol naar de testomgeving na merge op develop | B3 | |
| 183 | SonarQube Quality Gate en minimaal 80% testdekking ingesteld | C1a–C1d | |
| 183 | Securityregels voor kwetsbaarheden, dependencies en secrets vastgelegd | C2a–C2e | |
| 183 | Kwaliteits- en beveiligingsregels gedocumenteerd | C3 | |
| 116 | Acceptatiecriteria van de story | alle bovenstaande | |

Na afloop: de demo-PR's gesloten zonder merge, tijd gelogd op IT2627T05-116.
