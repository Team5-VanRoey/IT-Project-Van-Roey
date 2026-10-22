## Jira ticket
<!-- Replace XX with the ticket number, e.g. IT2627T05-181 -->
https://jiradigi.pxl.be/browse/IT2627T05-XX

## Type of change
<!-- Tick everything that applies -->
- [ ] New feature
- [ ] Bug fix
- [ ] Refactoring / technical improvement
- [ ] Documentation
- [ ] Configuration / CI-CD

## Description
<!-- What changed and why? Which problem does this solve? -->


## Test results
<!-- How was this tested? Add output, screenshots or a link to the pipeline run. -->
- Tests performed:
- Test coverage (%):
- SonarQube: Blocker issues: __ / Critical issues: __
- Pipeline run:
- Pre-commit hooks: passed on every commit, `--no-verify` not used (yes / no):

## How to test / reproduce (for the reviewer)
<!-- Steps another team member can follow to run or verify the result. Never use --no-verify. -->
1.
2.

## Security analysis
<!-- Which security risks do the changes introduce, and how are they handled?
     Think of secrets, personal data, input validation, permissions and dependencies. -->


## Checklist (Definition of Done)
<!-- Complete the sections in this order. Only tick an item when it is actually done. -->
### 1. Functionality & SMART-Fit
- [ ] The acceptance criteria (SMART-Fit) are implemented and demonstrably tested

### 2. Security
- [ ] A security analysis of the changes has been performed
- [ ] No secrets (passwords, API keys, tokens) in the repository, config or logs
- [ ] No privacy-sensitive data is shared
- [ ] The pre-commit hooks (incl. Gitleaks secret scan) passed on every commit
- [ ] `--no-verify` was never used
- [ ] `.env` files and real data are listed in `.gitignore`

### 3. Code quality & CI/CD
- [ ] Existing functionality still works (no regression)
- [ ] The pipeline passed (all required checks are green)
- [ ] The secret scan in the pipeline found no secrets
- [ ] Test coverage is at least 80%
- [ ] SonarQube reports no Blocker or Critical issues

### 4. Gitflow, review & evaluation
- [ ] Feature branch created from `develop` and named `feature/IT2627T05-XX`
- [ ] No commits were made directly on `develop` or `main`
- [ ] Every commit references the ticket (e.g. `IT2627T05-XX: short description`)
- [ ] This PR targets `develop`
- [ ] This PR template is fully completed (type of change, description, checklist, Jira link)
- [ ] At least one other team member performed a thorough review and approved this PR
- [ ] All review feedback is visible in PR comments and addressed, and all conversations are resolved before merging
- [ ] The feature branch will NOT be deleted after merging

### 5. Reproducibility & documentation
- [ ] Another team member can reproduce or run the result
- [ ] Relevant documentation (README, wiki, ...) is updated

### 6. Administration (Jira)
- [ ] Time spent will be logged on the Jira ticket as the very last step after merging