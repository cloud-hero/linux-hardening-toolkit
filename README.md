# Linux Hardening Toolkit

A reusable Linux server hardening guide and evidence-first assessment toolkit from [CloudHero](https://cloudhero.io/).

**LH-1.2 · seven areas · 28 fixed controls · tested on Ubuntu 24.04 LTS ARM64.**

Covers SSH, patch management, kernel lifecycle, firewall exposure, audit logging, configuration drift and production verification. Use it when provisioning a server, reviewing an existing fleet or adding operational context to a CVE article.

## Start here

- [Read the guide](linux-server-hardening-guide.md) or [download the PDF](https://github.com/cloud-hero/linux-hardening-toolkit/releases/latest/download/linux-server-hardening-guide.pdf).
- [Download the complete toolkit ZIP](https://github.com/cloud-hero/linux-hardening-toolkit/releases/latest/download/linux-hardening-toolkit.zip).
- [Copy the assessment prompt](linux-assessment-prompt.txt).
- [Review the adoption brief](adoption-brief.md) and [completed fictional change](worked-change-example.md).
- [Inspect the 28 controls](controls.json), [worked lab report](lab-assessment-report.md) and [dated test record](lab-validation.txt).

## Run an assessment

The default workflow gives the AI tool an operator-collected, redacted evidence pack. It does not give the model production shell or sudo access. Complete the policy worksheet and review the scripts before running them on an approved target.

```bash
# On the approved Ubuntu target, from the extracted toolkit directory:
bash collect-report.sh ./assess.sh
```

Every capture creates a new mode-0700 directory and mode-0600 report. Keep the original private, redact a separate copy and share only approved evidence with the assessment prompt. Collection success is not a security PASS. Remediation is a separate approved task.

## Validate this toolkit

Python 3.10+ and Bash are sufficient for the fixture tests; no third-party Python packages are required.

```bash
python3 scripts/validate-toolkit.py
```

This runs inventory, report-contract and review-regression tests, checks distributed copies, verifies the 28-control prompt/report contract and confirms referenced evidence exists. Local tests do not replace VM or production validation. Root-specific capture assertions run only when the suite is intentionally run as root in a disposable environment; ordinary local runs report that case as skipped. The existing real-VM results include those assertions.

The `scripts/lab-*` fixtures change users, packages, firewall rules or logging configuration. They are for a disposable VM only. See [the lab record](lab-validation.txt) and [pinned Lima configuration](lab.yaml) before reproducing them. The original Lima fixtures use the lab user `andrei`; adapt the SSH context for your own disposable VM. The tested VM had no host-directory mounts.

## Evidence and scope

The dated VM evidence covers fresh SSH and rejected authentication, package/kernel upgrades and fallback, allowed/denied IPv4/IPv6 paths, Linux Audit, authenticated log delivery, reconciliation of 300 queued messages, drift detection and a synthetic workload rollback gate.

The worked production catalogue remains **3 scoped PASS and 25 MANUAL**. Cloud/internet/container/UDP paths, human alert acknowledgement, actual business transactions, independent baseline provenance and organization policy still need their own evidence. This is a bounded baseline, not compliance certification. Other distributions and architectures require adaptation and validation.

This repository contains the curated toolkit distribution. It excludes the local VM, keys, caches and website working directory. The PDF retains the reviewed edition's local-review label; publication does not expand its validation claims. [Publication notes](PUBLICATION.md) describe the source and checksum boundaries.

## Toolkit workflow and files

1. Complete `policy-template.json`, `change-worksheet.md` and `exposure-inventory.csv` with actual scope, owners, thresholds and deadlines. Example values are not your organization's policy.
2. An authorized operator reviews `assess.sh` and `collect-report.sh`, then runs `bash collect-report.sh ./assess.sh` on the approved Linux target from a private work area. Each run creates a new private report directory; retain the original and redact a separate copy. The script does not install, refresh, repair or reboot. Missing permissions/tools remain visible; exit 1 reports collection errors, not a security score. Keep the original evidence private.
3. Supply the approved evidence and completed policy to your approved AI service with `linux-assessment-prompt.txt`. The default workflow gives the model no production execution access. Confirm data-processing and retention terms before sharing output.
4. Require exactly the IDs in `controls.json`, preserving order and version. Complete `report-template.json` alongside the Markdown assessment. A missing policy or required observation remains unresolved.
5. Validate the report structure and recalculate evidence coverage:

```sh
python3 check-report.py --catalog controls.json report.json
```

The validator rejects missing/duplicate IDs, unsupported PASS entries and unjustified N/A outcomes. It cannot determine whether evidence is true or sufficient. Evidence coverage is not a security score. The included worked lab report deliberately leaves production controls unresolved.

`baseline.py` compares an explicit inventory of paths, types, permissions, ownership, symlink targets and file bytes. Review the tool, scope and independently trusted manifest before use. `create` is a separately authorized change; an assessment runs `check` only. It is not an attestation against an attacker controlling root. Runtime/package drift needs separate evidence.

`rsyslog-forwarding.conf.example` illustrates authenticated delivery with an explicit audit-file input and a bounded queue. Replace its placeholders and validate certificate permissions, input ownership, confinement and receiver policy in staging. The lab's receiver is a disposable test sink; production alert routing and acknowledgement are separate evidence.

The ZIP includes dated lab transcripts under `evidence/` and test sources under `scripts/`. The modifying `lab-*.sh` fixtures are exclusively for a disposable VM and must never be run on production. `lima.sh` expects official Lima binaries at `.lab/tools/bin/limactl`; the pinned image and VM settings are in `lab.yaml`. See `lab-validation.txt` for what was and was not tested. The source hashes identify this edition, not a signed trust root.

Use `cve-record.md` to add current vendor advisory and exact package/active-fix evidence to an individual CVE article. Do not treat the lab's dated versions as permanent recommendations.
