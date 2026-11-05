# Lab reproduction guide: disposable VM only

**Optional maintainer task. Do not follow this guide to assess a production server.** It provisions and changes a disposable Ubuntu VM to reproduce implementation tests. An assessment uses `linux-server-hardening-guide.md`; approved real-server fixes use `hardening-runbook.md`. Neither task requires reproducing this lab.

Toolkit LH-1.3; control catalogue LH-1.2. Historical receipts were captured on 3-4 November 2026 with Ubuntu 24.04.5 LTS ARM64, Lima 2.2.1 and Apple Virtualization Framework. The scripts and pinned image remain that tested snapshot. A new run must record its own versions, timestamps and outcomes; it cannot inherit the old PASS labels.

## Host requirements and isolation

Use a macOS ARM64 host with Apple Virtualization Framework and the official verified Lima binaries. `scripts/lima.sh` expects `.lab/tools/bin/limactl` and keeps VM state under this checkout's `.lab/lima`. Obtain Lima from its official release and verify the vendor checksum; the historical binary and image digests are in `lab-validation.txt`. Do not publish `.lab`, private keys or VM disks.

Run host commands below from the extracted toolkit or repository root. `lab.yaml` allocates 2 CPUs, 3 GiB memory and a 16 GiB disk, uses a checksum-pinned Ubuntu image, mounts no host directories and disables application port forwards. Keep that isolation. Its SSH endpoint is localhost port 60024.

```sh
# HOST: start only the dedicated disposable VM.
sh scripts/lima.sh start --name=hardening --tty=false lab.yaml
```

If this VM already contains a previous run, preserve its evidence and choose a fresh disposable instance for initial provisioning. Do not rerun the initial hardening fixture over its saved backup. Adapt the VM name consistently when using another instance.

## Provision the disposable guest

Before installing anything, collect any desired pre-change evidence using the assessment workflow. Missing tools in a fresh image are expected observations, not an instruction to alter a real server. The following installation exists solely to equip this lab for its fixtures.

```sh
# HOST: open the disposable guest shell.
sh scripts/lima.sh shell hardening
```

Inside that guest shell, refresh its signed repositories as a lab change:

```bash
# DISPOSABLE GUEST ONLY: this changes package-manager state.
sudo apt-get -o APT::Update::Error-Mode=any update
```

Inspect the proposed lab dependency transaction:

```bash
# DISPOSABLE GUEST ONLY: review the simulation before proceeding.
sudo apt-get -s install openssh-server ufw auditd audispd-plugins unattended-upgrades needrestart rsyslog-gnutls
```

Only after reviewing it, install the lab dependencies. Installation can start services:

```bash
# DISPOSABLE GUEST ONLY: install the fixture dependencies.
sudo apt-get install openssh-server ufw auditd audispd-plugins unattended-upgrades needrestart rsyslog-gnutls
```

Keep AppArmor enforcing. Leave the guest shell before the following host commands. The VM has no host mounts: the host-to-guest stdin examples deliberately pass reviewed fixture content through Lima rather than assuming project files exist inside the guest.

## Apply the initial lab fixture

Read the fixture first. It requires root and the explicit `/run/cloudhero-disposable-lab` marker. It creates `/root/hardening-backup`, configures SSH/UFW/journald/audit/update examples and writes a baseline. **If that backup already exists, stop and use a fresh lab; do not overwrite it.** The original SSH context in `lab-verify.sh` uses user `andrei`; adapt that context to your own Lima guest user.

```sh
# HOST: mark this disposable guest, then apply its initial fixture once.
sh scripts/lima.sh shell hardening sudo touch /run/cloudhero-disposable-lab
sh scripts/lima.sh shell hardening sudo bash < scripts/lab-harden.sh
```

## Run modifying verification fixtures

These are controlled exercises, not observation-only server assessment. `lab-verify.sh` deliberately changes/restores a watched file and creates temporary network namespaces. `lab-network.sh` changes/restores temporary firewall allowances. Logging and rotation fixtures create events and isolated test services; the sudo fixture creates then removes temporary identities. Do not run them on production.

```sh
# HOST: run only against the prepared disposable guest.
sh scripts/lima.sh shell hardening sudo bash < scripts/lab-verify.sh
```

After that fixture succeeds, run each following fixture separately and inspect its result before continuing:

```sh
sh scripts/lima.sh shell hardening sudo bash < scripts/lab-network.sh
```

```sh
sh scripts/lima.sh shell hardening sudo bash < scripts/lab-logging.sh
```

```sh
sh scripts/lima.sh shell hardening sudo bash < scripts/lab-audit-rotation.sh
```

```sh
sh scripts/lima.sh shell hardening sudo bash < scripts/lab-sudo.sh
```

```sh
sh scripts/lima.sh shell hardening python3 < scripts/lab-workload.py
```

Inspect each exit status and receipt before continuing; stop and investigate any failure. Keep raw transcripts private and share only reviewed/redacted copies. The logging fixture uses a disposable namespace/PKI, cleans up its test processes and leaves private material only in the guest spool. It tests bounded queue recovery, not exactly-once delivery or production human acknowledgement.

## Local software regression tests

Python 3.10+ and Bash are sufficient for the fixture suites. These create temporary test files to check the toolkit's software; they do not assess your server or prepare it for assessment. Run from the toolkit root on the development workstation:

```sh
python3 scripts/test-baseline.py
python3 scripts/test-report.py
python3 scripts/test-guide-fixes.py
```

The public repository also provides `python3 scripts/validate-toolkit.py` to run these suites and check package integrity. Root-specific assertions are skipped on an ordinary workstation. To repeat them, copy the relevant scripts and content files into the disposable guest and run the regression there as root. The original VM receipts are retained; a local skipped assertion is not a new VM PASS.

For real-host inventory comparison in the lab, review `baseline-paths.json` and use the approved creation/comparison procedure in the separate hardening runbook. The tool, scope and manifest must already be installed at the documented locations before collector integration can compare them. The collector never creates a manifest.

## Kernel and recovery exercises

Use the kernel chapter of the hardening runbook to inspect the actual supported meta-package, transaction and generated boot selection. Review updates before applying them. Reboot the guest, capture a changed boot ID and the actual active kernel, then repeat acceptance. Select a retained fallback only from this VM's actual GRUB entries, exercise it once, then return to the intended patched kernel and repeat acceptance. Do not copy the historical 142/147 versions or an old menu title as a current recommendation.

Verify host keys through the VM's trusted provisioning/console path for fresh SSH checks. Never disable host-key verification to work around a changed key. Lima stop/start regenerated cloud-init identities in the original run; a normal guest reboot preserved them. `/run` and `/tmp` may be cleared, so recreate only the explicitly disposable marker when required and recopy any guest fixtures.

**Lab troubleshooting:** after an OpenSSH package update, the socket was listening while the service was inactive; `sshd -t` reported a missing `/run/sshd`. A fresh authorized connection activated the service and restored its runtime directory. Inspect `ssh.service` and `ssh.socket`; do not interpret this error as a clean syntax result or blindly create runtime directories to hide it.

## Finish and retain evidence

Check that fixture identities, namespaces, listeners and temporary rules were removed/restored. Store the observed timestamps, versions, commands, exit statuses, assertions and limitations. A clean lab does not close organizational policy, external exposure, production transactions or human-response controls.

```sh
# HOST: stop the lab and preserve its disk for review.
sh scripts/lima.sh stop hardening
```

Historical evidence paths in `lab-validation.txt` refer to the tested snapshot. The worked production assessment intentionally retains 3 scoped PASS and 25 MANUAL outcomes against the seven-area catalogue. Do not change those findings merely because a fixture passes.
