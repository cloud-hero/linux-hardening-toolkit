# Linux hardening assessment toolkit · LH-1.5

From [CloudHero](https://cloudhero.io/). [Get the LH-1.5 release](https://github.com/cloud-hero/linux-hardening-toolkit/releases/tag/lh-1.5) for the six-step assessment workflow and collector validated on four Linux distributions.

Start with [the copy-and-paste quickstart](quickstart.md): prepare the workstation, clone or upload to the server, collect with sudo, copy the report with SCP, redact it into an isolated review folder, run the full prompt and validate the report structure.

## Tested scope

The observational collector was exercised on official x86_64 EC2 images on 5 November 2026: Ubuntu 24.04.5 LTS, Debian 13.7, Fedora 44 Cloud and Amazon Linux 2023.12. It uses APT or DNF/DNF5 according to the installed package manager and queries available host-firewall tools. This does not validate every version or custom image of those distributions.

The fixed LH-1.2 catalogue still contains 28 controls. Collection success is not a control PASS. Missing tools, metadata, approved policy and production evidence remain visible. Amazon Linux 2023's repository version pin is reported separately from current vendor security coverage.

DNF can create cache files even when asked to use cached metadata only. The collector copies existing metadata into private scratch storage and redirects DNF cache, log and persistent working paths there. The copy excludes downloaded RPMs and is removed after collection. It does not refresh repositories, install packages or apply fixes. Normal SSH/sudo access can still create logs.

## Separate tasks

- [Assessment guide](linux-server-hardening-guide.md): assess existing evidence on a separate workstation.
- [Hardening runbook](hardening-runbook.md): separately approved changes; its modifying examples retain their original Ubuntu lab scope.
- [Historical lab guide](lab-guide.md): optional Ubuntu ARM64 reproduction, not an assessment prerequisite.
- [EC2 collection validation](ec2-validation.md): scope and results of the four-distribution collector tests.
- [Vulnerability context](vulnerability-context.md): optional workstation-only Zero Wire/CISA lookup. Absence from a feed is not evidence of safety.

The original `linux-server-hardening-guide.pdf` is the retained LH-1.4 PDF. Use this revision's Markdown quickstart and guide for the new workflow; the PDF is historical and does not describe the four-distribution collector. No PDF is added to the CloudHero website deployment.

## Assessment inputs and outputs

Open only the quickstart's `review` folder in the approved AI environment. Its six inputs are the redacted assessment, completed policy, target context, full prompt, catalogue and report template. Keep the private original and server credentials outside that workspace. Enforce file access and execution restrictions in the tool; prompt instructions alone are not a sandbox.

The model produces `output/assessment.md` and `output/report.json`. An operator runs `check-report.py` to validate the structure, then reviews the evidence and proposed fixes. The collector never runs the AI prompt or sends evidence to a model.

## Maintenance

Run `python3 scripts/validate-toolkit.py` on a Python 3.10+ workstation. The root-only wrapper fixtures must also run on a disposable test server. Changes to collector behaviour require fresh server evidence; historical tests cannot be relabelled as a new run.

`baseline-paths.json` now includes APT/UFW and DNF/firewalld/nftables/SELinux policy locations. It is a starting scope for an approved baseline, not permission to create or replace one during assessment. Existing installed scopes/manifests must be reviewed independently.

Keep raw reports, keys and cloud resource inventories private and out of Git. Public validation summaries describe the exact tested scope without account IDs, instance addresses or raw server reports.
