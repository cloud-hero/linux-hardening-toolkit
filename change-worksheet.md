# Linux maintenance acceptance record

Baseline version: LH-1.2. Complete before remediation. Blank fields are unresolved decisions, not defaults.

- Target alias / environment / business service:
- Change ID / approved revision / service owner / decision maker:
- Security findings and vendor advisory URLs, checked at UTC:
- Installed vendor revision / fixed vendor revision / active revision:
- Management source networks / new-session test identity:
- Console or recovery route / last successful recovery exercise:
- Package/kernel changes and removals reviewed:
- Application backup or replacement-image recovery evidence:
- Maintenance window / load-balancer drain procedure / dependency owners:
- Canary host(s) / rollout batch size / minimum healthy capacity:
- Baseline p95 latency and error rate / acceptable change / observation window:
- Representative user transaction / background job / dependency probe:
- Expected port matrix including address families and UDP:
- Unique log marker / central receipt deadline / alert acknowledgement owner:
- Trigger to abort / exact restore steps / recovery time objective:

## Evidence after each stage

Record UTC time, command or probe, expected value, actual value, exit status, evidence path and responsible engineer. Stages: before change; after configuration/package change; after reboot; after canary observation; after each rollout batch.

Required gates: SSH-03; PATCH-02; KERN-02/03; NET-03; AUD-01/03/04; DRIFT-02/03; VERIFY-02/03. Other fixed controls require current evidence or an approved exception. Missing evidence stops the associated acceptance gate.

## Decision

Proceed / hold / rollback:
Failed or unverified controls:
Exceptions with approver, compensating control and expiry:
Rollback performed and verified (when applicable):
Service-owner sign-off and timestamp:
Next review / follow-up owner:

## Worked synthetic example - not a production threshold

In the disposable lab, release A's representative endpoint returned `{ "result": "ok" }`. Release B still returned HTTP 200 from `/health`, but the representative endpoint returned an incorrect result. The acceptance script held the rollout, restored release A, and verified the expected result again. This demonstrates a decision gate; use real service semantics, jobs, dependencies, capacity and recovery objectives for production.
