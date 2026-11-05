# LH-1.5 disposable EC2 validation — 5 November 2026

Tests ran against the local LH-1.5 candidate before publication. The fixed catalogue remains LH-1.2 (28 controls).

## Tested scope

Four separate official x86_64 EC2 images in eu-central-1, using t3.small instances with encrypted 16 GiB root volumes, IMDSv2, no instance role and SSH restricted to the operator IP. SSH host keys were verified against the authenticated EC2 console output. These test credentials and raw observations are excluded from the package.

| System | Image | Package checks | Monitored files | Final collection / SCP |
|---|---|---|---:|---|
| Ubuntu 24.04.5 LTS | `ami-0c228cd2b65888e1b` | APT | 101 | exit 0 / bytes match |
| Debian 13.7 | `ami-04e9b382a9b6299a6` | APT | 39 | exit 0 / bytes match |
| Fedora 44 Cloud | `ami-089b8ba3189f7e8dd` | DNF5 | 60 | exit 0 / bytes match |
| Amazon Linux 2023.12.20261102 | `ami-01376afa3e7def694` | DNF4 | 50 | exit 0 / bytes match |

All final runs preserved the hashes, modes and mtimes of the monitored configuration and metadata files; installed-package inventory, running kernel and boot identity were unchanged. Normal SSH/sudo access logs and the intended private evidence files are expected writes; this was not a whole-filesystem immutability test.

## Test stages and findings

1. Initial collections on all four fresh images. Amazon Linux revealed that DNF cache-only queries can write solver/lock files. This initial defect was fixed before final validation.
2. Cache isolation: bounded copies of existing RPM metadata, with DNF cache, persistent state and log paths redirected to a private temporary directory. Final monitored package-state files did not change.
3. Explicit disposable-lab setup installed Git where missing and populated repository metadata. These were test preparation actions, not collector actions. Collection then ran successfully with populated APT, DNF4 and DNF5 metadata.
4. An enabled but uncached fixture repository on Fedora and Amazon Linux verified that missing repository metadata remains MANUAL. `skip_if_unavailable=False` prevents silent omission. The fixture was removed before the final runs.
5. A final clean run on each host verified zero collection errors, report mode 0600, report directory mode 0700 and SHA-256 equality after SCP. Missing observations remained visible; none was reclassified as a security PASS.
6. The documented interactive SSH → `tee collection.log` → parse the exact report path → SCP sequence passed on all four hosts. Each workstation review folder contained exactly six input files; the original stayed outside it. The four evidence sets were not submitted to an external AI service.
7. Root capture-wrapper and collector-portability fixtures passed on all four hosts. DNF exit 100, permission errors, timeouts, missing cache and missing tools were exercised through deterministic fixtures. No naturally occurring exit-100 update set was observed on these images.

The public LH-1.4 repository was cloned successfully from all four hosts. LH-1.5 was uploaded from the local candidate for these tests because its release tag does not exist yet. The published LH-1.5 clone command therefore remains a release-time smoke test, not a completed test.

## What changed

- Distribution-aware APT and DNF/DNF5 package observations, SSH service/socket names, available host-firewall tools and SELinux/AppArmor observations.
- DNF cache isolation, expected exit-100 handling and explicit missing-cache gaps. Amazon Linux repository pinning is called out separately.
- Missing optional tools become evidence gaps; failed attempted commands and timeouts remain collection errors.
- Optional baseline scope now includes RPM repository, firewalld, SELinux and crypto-policy paths. No baseline is automatically created or replaced.
- Six copy-and-paste steps with server/workstation labels, a six-file input folder, a constrained AI handoff prompt and local JSON report validation.

## Boundaries

This validates collection and transfer on the listed image versions and architecture. It does not establish cross-distribution remediation safety, compliance, production control results, an AI model's assessment quality or support for every Linux variant. The original modifying Ubuntu ARM64 lab remains dated, separate evidence. Package metadata and vendor fixes still require an approved freshness and release-coverage decision.

## Cleanup

All four instances were confirmed terminated; no run-tagged volumes remained. The temporary security group and AWS key pair were deleted, and the local private key removed. Cleanup completed at 2026-11-05T19:57:08.176776+00:00.

## Primary references

- [DNF5 check-upgrade exit statuses](https://dnf5.readthedocs.io/en/latest/commands/check-upgrade.8.html)
- [DNF command reference and cache-only behavior](https://dnf.readthedocs.io/en/latest/command_ref.html)
- [DNF5 cache and state settings](https://dnf5.readthedocs.io/en/latest/dnf5.conf.5.html)
- [Amazon Linux 2023 versioned repositories](https://docs.aws.amazon.com/linux/al2023/ug/deterministic-upgrades.html)
- [Official Ubuntu AMI discovery](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/)
- [Debian EC2 images](https://wiki.debian.org/Amazon/EC2/HowTo/awscli)
- [Fedora Cloud images](https://www.fedoraproject.org/cloud/download/)

Collector SHA-256: `11826457d79d640de13ef8f924fdd3c749bfb71cfff54dc03abf1f3c94a07b6e`.
