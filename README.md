# Linux hardening assessment toolkit · LH-1.3

From [CloudHero](https://cloudhero.io/). [Get the LH-1.3 release assets](https://github.com/cloud-hero/linux-hardening-toolkit/releases/tag/lh-1.3): complete ZIP, assessment PDF, prompt and checksums.

Control catalogue LH-1.2: seven areas and 28 controls, tested on Ubuntu 24.04 LTS ARM64. This workflow revision keeps the collection scripts and criteria unchanged. Commands require adaptation and validation on other platforms.

## Choose your task

- **Assess an existing server:** follow [assessment guide](linux-server-hardening-guide.md) (or the [assessment PDF](linux-server-hardening-guide.pdf)) and the four steps below. No package installation, service restart, firewall change or new baseline is required to begin. Unavailable observations remain visible.
- **Apply approved fixes:** use the [hardening runbook](hardening-runbook.md) after assessment and change approval. Its commands can change the target.
- **Reproduce our tests:** use the [lab reproduction guide](lab-guide.md) only for a disposable VM. Lab provisioning and software regression tests are optional maintainer work, not assessment prerequisites.

## Required workflow: server collection, workstation analysis

**Run the collector yourself on the Linux server. Run the assessment prompt on a different machine against a redacted copy of the report.** The prompt must not download or execute collectors, connect to the server, request SSH/sudo access or inspect the analysis workstation. The scripts collect facts and run specific deterministic checks; they are not a complete deterministic 28-control assessor.

### 1. Collect on the approved Linux server

Obtain and extract the toolkit, complete the policy and review `assess.sh` and `collect-report.sh`. From a private directory containing the reviewed scripts on the approved target, run:

```bash
# SERVER: the authorized operator runs this command.
bash collect-report.sh ./assess.sh
```

The wrapper uses the operator's approved sudo access where required. It creates a new `0700` directory and `0600` report at `linux-assessment.XXXXXXXX/assessment.txt`, prints the actual path and preserves failed-collection evidence and exit status. The collector does not install packages, refresh metadata, change configuration or restart services. Normal access can create logs. Neither script applies hardening fixes.

### 2. Redact and transfer

Keep the original private on the server. Review a separate copy, remove data your policy does not permit sharing and transfer the approved redacted report to a different machine using your established secure transfer method. Keep the same target alias across the evidence and policy. Preserve UTC collection times, exit statuses and facts needed for the assessment; record redactions that limit conclusions.

Bring the completed `policy-template.json`, workload role/environment and approved supporting evidence. Do not transfer SSH keys, passwords, tokens or unrestricted logs. Approve the AI service and its processing/retention arrangements: using a cloud model from a workstation still sends the supplied evidence to that service.

### 3. Run the prompt on the analysis workstation

Open your approved Claude or Codex environment on the separate machine. Supply the full `linux-assessment-prompt.txt`, the redacted report, completed policy and target context. Give access only to the approved evidence and output area; keep server credentials and production execution access out of the analysis environment. Explicitly include this instruction alongside the full prompt:

```text
Assess only the server described in the attached redacted evidence.
Required mode: operator collection on the server; AI analysis here.
This is a separate analysis workstation, not the assessment target.
Do not download or execute scripts, connect to the server,
request SSH/sudo access, or inspect this workstation.
Use the supplied policy and collection timestamps.
If evidence is missing, request it from the operator; never guess PASS.
Produce the 28-control report and proposed fixes only. Do not remediate.
```

If no report is supplied, the prompt asks the operator to collect, redact and transfer it first. It must not switch to live collection. For missing observations, the model can propose read commands for the operator to review and run on the server, then analyse the returned redacted receipts. Missing or stale evidence cannot create a PASS. The report describes the supplied collection times; it is not a new live scan.

### 4. Review and validate the report

Require a Markdown assessment and `report.json` with exactly the 28 IDs from `controls.json`, in order. On the analysis workstation, the operator may check its structure:

```bash
# WORKSTATION: report validation only; no server collection.
python3 check-report.py --catalog controls.json report.json
```

Review the findings before approving remediation as a separate task. Repeat server collection and workstation analysis after changes. Start with the PDF or Markdown guide and `adoption-brief.md`; `worked-change-example.md` illustrates the change decision.

The validator rejects missing/duplicate IDs, unsupported PASS entries and unjustified N/A outcomes. It cannot determine whether evidence is true or sufficient. Evidence coverage is not a security score. The included worked lab report deliberately leaves production controls unresolved.

`baseline.py` compares an explicit inventory of paths, types, permissions, ownership, symlink targets and file bytes. Review the tool, scope and independently trusted manifest before use. `create` is a separately authorized change; an assessment runs `check` only. It is not an attestation against an attacker controlling root. Runtime/package drift needs separate evidence.

`rsyslog-forwarding.conf.example` illustrates authenticated delivery with an explicit audit-file input and a bounded queue. Replace its placeholders and validate certificate permissions, input ownership, confinement and receiver policy in staging. The lab's receiver is a disposable test sink; production alert routing and acknowledgement are separate evidence.

The ZIP includes dated lab transcripts under `evidence/` and test sources under `scripts/`. Follow `lab-guide.md` only when your task is reproducing those tests. The modifying `lab-*.sh` fixtures are exclusively for a disposable VM and must never be run on production. `lima.sh` expects official Lima binaries at `.lab/tools/bin/limactl`; the pinned image and VM settings are in `lab.yaml`. See `lab-validation.txt` for what was and was not tested. The source hashes identify this edition, not a signed trust root.

Use `cve-record.md` to add current vendor advisory and exact package/active-fix evidence to an individual CVE article. Do not treat the lab's dated versions as permanent recommendations.

## Optional maintainer validation

Follow the [lab guide](lab-guide.md#local-software-regression-tests) for local software regression and disposable-VM reproduction. These are not steps for collecting a server assessment.

## Evidence and scope

The dated VM evidence covers fresh SSH and rejected authentication, package/kernel upgrades and fallback, allowed/denied IPv4/IPv6 paths, Linux Audit, authenticated log delivery, reconciliation of 300 queued messages, drift detection and a synthetic workload rollback gate.

The worked production catalogue remains **3 scoped PASS and 25 MANUAL**. Cloud/internet/container/UDP paths, human alert acknowledgement, actual business transactions, independent baseline provenance and organization policy still need their own evidence. This is a bounded baseline, not compliance certification. Other distributions and architectures require adaptation and validation.

This repository contains the curated toolkit distribution. The local VM, keys, caches and website working directory are excluded. [Publication notes](PUBLICATION.md) explain the release and evidence provenance.
