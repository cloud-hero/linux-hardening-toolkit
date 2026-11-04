# Adoption decision: Linux hardening baseline

**Purpose:** reduce unauthorized access, unpatched active software, unintended exposure and undetected configuration changes while preserving service availability. This Ubuntu-tested baseline has seven areas and 28 evidence-based controls; application security and business continuity standards remain companion requirements.

**Authorize a bounded pilot first.** Name the service owner and one accountable person for each area in the operating matrix. Select a representative staging host and one recoverable production canary. Agree the AI evidence-processing boundary before sharing data. The security owner proposes vulnerability deadlines and exceptions; the service owner owns business acceptance and recovery decisions.

**Before a production change:** complete the policy and change worksheets; inventory identities, software and traffic paths; prove recovery access; identify application backup/recovery evidence; approve the exact change, observation window and rollback trigger. Establish trusted configuration provenance and central logging. Missing required evidence holds the associated gate; an exception needs a named approver, compensating control and expiry and never becomes a PASS.

**Rollout:** collect and review evidence; test changes and recovery in staging; change one approved canary; verify fresh access, active fixes, allowed/denied paths, log receipt and real workload behavior; observe the agreed thresholds; expand in approved batches. Stop on a failed gate. The service owner signs proceed, hold or rollback at each decision point.

**Resource commitment:** estimate engineering time for inventory, staging, canary verification and rollout separately. Reserve identity, network, observability and application-owner participation plus recovery capacity. Use pilot measurements to budget each additional host class and the recurring work; do not promise a universal completion time. Onboarding includes maintenance-window effort, and continuous automation still needs failure triage.

**Operate and report:** review patch failures, exposure and drift daily; review access and log delivery on the approved cadence; verify every material change/reboot; schedule recovery exercises. Report overdue applicable fixes, unsupported hosts, missing detection evidence, unexplained drift and recovery-test completion with denominators, owners, age and due dates. Report unknowns and stale evidence separately from compliant results. Evidence coverage is not a risk score.

**Decision record:** sponsor, pilot scope, accountable owners, approved policy revision, staffing/maintenance allocation, acceptance thresholds and review date. Approve expansion only after pilot acceptance and unresolved-risk review. The fictional worked change illustrates a complete decision; its numbers are not default policy.
