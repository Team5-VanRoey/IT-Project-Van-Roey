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

## How to test / reproduce (for the reviewer)
<!-- Steps another team member can follow to run or verify the result -->
1.
2.

## Checklist (Definition of Done)
### 1. Functionality
- [ ] The acceptance criteria (SMART-Fit) are implemented and demonstrably tested

### 2. Security
- [ ] A security analysis of the changes has been performed
- [ ] No secrets (passwords, API keys, tokens) in code, config or logs
- [ ] No privacy-sensitive data is shared

### 3. Code quality & CI/CD
- [ ] Existing functionality still works (no regression)
- [ ] The pipeline passed
- [ ] Test coverage is at least 80%
- [ ] SonarQube reports no Blocker or Critical issues

### 4. Gitflow & review
- [ ] Feature branch created from `develop` and named `feature/IT2627T05-XX`
- [ ] Every commit references the ticket (e.g. `IT2627T05-XX: short description`)
- [ ] This PR targets `develop`
- [ ] All review feedback is addressed and all conversations are resolved
- [ ] The feature branch will NOT be deleted after merging

### 5. Reproducibility & documentation
- [ ] Another team member can reproduce or run the result
- [ ] Relevant documentation (README, wiki, ...) is updated

### 6. Administration
- [ ] Time spent will be logged on the Jira ticket after merging
