# Linux hardening runbook: approved changes

**Purpose: apply a reviewed fix after assessment and change approval. This document contains commands that change servers.** It is not part of collecting evidence and is not a script to execute from beginning to end. Select the relevant control, adapt the example to the approved target and retain the original evidence.

Toolkit LH-1.4; control catalogue LH-1.2. The executable examples were previously exercised on Ubuntu 24.04 LTS ARM64. Other platforms require their own validation. Follow `linux-server-hardening-guide.md` to assess first. Use `lab-guide.md` only to reproduce the disposable VM tests.

**Three gates:** inspect the existing state and proposed transaction; apply only the approved change; verify its result and recovery path. Read commands and change commands are presented in separate blocks where they previously shared a Copy action. Syntax validation followed immediately by a conditional service reload is explicitly a change operation.

The change worksheet, exposure inventory and `worked-change-example.md` support approval, capacity, acceptance thresholds and rollback decisions. Do not install packages or create a new baseline merely to make an assessment report look complete.

## Before changing a server

Record its owner, workload, distribution, release, architecture, kernel flavour, service ports and maintenance window. Confirm a working console or out-of-band recovery path. Keep the existing admin session open, test a second key-authenticated session and verify approved privilege escalation before editing SSH or the firewall.

Back up the exact configuration files you will change, including ownership and permissions. Take a recoverable infrastructure snapshot where appropriate and verify application backup recovery separately: a disk snapshot alone does not prove a database is recoverable. Define health checks, rollback triggers and who decides whether to proceed. Start with a canary host and drain traffic when required.

All executable remediation examples below target **Ubuntu 24.04 LTS with systemd, OpenSSH, UFW and auditd**. They are individual change examples, not a script to paste into production. The lab uses ARM64; an x86 host or another distribution needs its own validation. Do not enable UFW on a host already managed by firewalld, a native nftables policy or a container networking controller without planning ownership.

### Scope the approved change

Select only the controls covered by the approved change. Inspect the existing package and service stack first; an absent observation is not permission to install a replacement firewall or audit system. Package installation, repository refresh, configuration creation, reloads, test events and reboots all belong to the change plan. The bulk package installation used to build our disposable test environment is in `lab-guide.md`, not a production prerequisite.

For a selected configuration example, ensure its directory exists before writing the file. These directory-creation commands are changes; use only the one required by your approved control:

```bash
# CHANGE: only if the approved SSH configuration directory is missing.
sudo install -d -m 0755 /etc/ssh/sshd_config.d
```

```bash
# CHANGE: only if the approved journald configuration directory is missing.
sudo install -d -m 0755 /etc/systemd/journald.conf.d
```

```bash
# CHANGE: only if the approved Audit configuration directory is missing.
sudo install -d -m 0755 /etc/audit/rules.d
```

Stop on missing recovery access, an unreviewed package transaction, conflicting firewall ownership, a failed validation or an unapproved change. The assessment records the original state before any remediation.

## 1. SSH: preserve access while removing weak paths

Use named identities with short-lived certificates or well-managed keys. Limit administration to your VPN, bastion or approved management networks. Remove direct root login after proving that the named administrator can perform required tasks. Review unused accounts, keys, certificate authorities, authorized-key restrictions and revocation procedures with the identity owner.

Inspect the effective configuration, not just a line in a file. OpenSSH generally uses the first obtained value; Include order and Match blocks matter. A later file named `99-hardening.conf` may not override an earlier setting. Evaluate each relevant user and source address, including root and any special-purpose accounts. [OpenSSH configuration reference](https://man.openbsd.org/sshd_config).

```bash
sudo /usr/sbin/sshd -t
sudo /usr/sbin/sshd -T
# Replace the values with the real connecting user, client host and source IP.
sudo /usr/sbin/sshd -T \
  -C user=admin,host=admin-client,addr=192.0.2.10
```

Here `host` means the connecting client's hostname. Include `laddr` and `lport` when your Match rules depend on the destination address or port. Do not assume the example account or documentation address exists on your server.

For a **key-only server that does not use PAM keyboard-interactive MFA**, a reviewed drop-in can contain the following. Preserve `UsePAM` and your distribution's authentication/session controls. If you use MFA, assess the complete `AuthenticationMethods` chain instead of disabling its mechanism.

```text
# /etc/ssh/sshd_config.d/00-cloudhero.conf
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
LogLevel VERBOSE
```

Disable forwarding only when the server's role permits it; bastions and developer workflows may depend on it. Do not copy arbitrary cipher lists that drift away from supported vendor defaults. Changing the SSH port reduces noise but does not replace authentication and network restrictions.

**Apply and verify:** validate syntax, inspect all relevant effective contexts, then reload the service. On the tested Ubuntu image the service is `ssh`; other distributions may use `sshd`. A change to listening addresses or ports can also involve socket activation and needs its own procedure. This example changes authentication only. [Ubuntu OpenSSH guide](https://ubuntu.com/server/docs/how-to/security/openssh-server/).

```bash
sudo /usr/sbin/sshd -t && sudo systemctl reload ssh
```

Open a new connection from an approved source. Replace the example identity and host with the actual target; verify the host key through your established trust channel.

```bash
ssh -o ControlMaster=no -o ControlPath=none -o BatchMode=yes \
  admin@server.example 'id -un'
```

**Expected:** the named identity and exit 0 prove a fresh key login. Verify privilege separately according to the identity's approved role. For an interactive administrator, open a fresh terminal with `ssh -t -o ControlMaster=no -o ControlPath=none admin@server.example`, run `sudo -l`, complete required authentication, and perform the specific approved task from the runbook. For an automation identity already authorized for noninteractive sudo, use `sudo -n` with its exact approved command and arguments. A password prompt is valid policy for a human administrator; failure of `sudo -n true` does not by itself mean access is broken. Do not expand privileges to make a generic probe pass. SSH-03 needs both the fresh-login receipt and successful role-appropriate task evidence. [Ubuntu sudo reference](https://manpages.ubuntu.com/manpages/noble/en/man8/sudo.8.html).

For this key-only profile, effective output includes `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no` and `pubkeyauthentication yes`. A context that permits an unintended authentication path fails SSH-01 even if the main configuration file looks correct. Verify key removal/certificate expiry and offboarding separately; named accounts alone do not prove lifecycle control.

**Stop and recover:** keep the original session until the new one succeeds. On failure, use it or the console to restore the exact previous SSH files, validate and reload, then test a new session again. Do not close the last working session. Schedule and record an independent console recovery and access-revocation exercise for SSH-04.

## 2. Patch management: define how fixes reach production

Inventory operating-system packages, third-party repositories, agents, language runtimes and applications outside the package manager. Assign patch deadlines based on exploit activity, exposure and business impact. Document the owner of exceptions, the compensating control and an expiry date. A configured update timer needs evidence of recent successful runs.

For Ubuntu, inspect holds, package consistency and the proposed transaction before an approved update. The simulation uses existing metadata; stale indexes can hide available fixes. Refreshing metadata changes local package-manager state and belongs in an authorized maintenance task, not the observational assessment.

```bash
apt-mark showhold
sudo dpkg --audit
sudo apt-get -s upgrade
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
```

**Change - refresh package metadata only within the approved maintenance task:**

```bash
# Authorized maintenance only:
sudo apt-get -o APT::Update::Error-Mode=any update
```

**Inspect the refreshed transaction proposal:**

```bash
sudo apt-get -s upgrade
```

Use your tested patch pipeline or unattended security updates. On Ubuntu, `unattended-upgrades` selects updates according to its allowed origins; third-party repositories are not automatically covered. Inspect the effective settings and run a dry run in staging. That dry run may write logs, so it is not part of the read-only prompt. [Ubuntu automatic updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/).

```text
# /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";

# /etc/apt/apt.conf.d/52cloudhero-reboot
Unattended-Upgrade::Automatic-Reboot "false";
```

```bash
# In staging or an approved maintenance window:
sudo unattended-upgrade --dry-run --debug
```

**Change - apply the approved package transaction:**

```bash
sudo apt-get upgrade
```

**Inspect remaining restart needs:**

```bash
sudo needrestart -r l
```

`apt-get upgrade` applies all eligible upgrades from configured repositories, not just security updates. It can keep packages back when they require new dependencies. In this lab, that left the kernel meta-packages on the old revision. Review the following simulation, then explicitly approve its additional packages before running the second command. This option permits new packages without removing installed ones; do not turn a broad `full-upgrade` into an automatic removal decision. [Ubuntu APT command reference](https://manpages.ubuntu.com/manpages/noble/man8/apt-get.8.html).

```bash
sudo apt-get -s --with-new-pkgs upgrade
```

**Change - only after approving the proposed new dependencies:**

```bash
# Only after reviewing the proposed new dependencies:
sudo apt-get --with-new-pkgs upgrade
```

Package scripts can restart services even when automatic reboots are disabled. `needrestart -r l` lists restart needs; arrange the actual restarts through your change process. In the lab it initially reported the running kernel as up to date while newer kernel packages were still kept back. Pair restart checks with repository candidate and meta-package checks.

**Verify:** capture the completed transaction, investigate failures and holds, compare installed vendor revisions with the relevant advisory, and confirm affected services are using the updated code. Package rollback is not always available or safe; define a tested image, snapshot or application recovery path before maintenance.

**Expected:** a successful refresh for every required source, no unexplained holds or kept-back packages, no incomplete dpkg transaction, and a completed update/pipeline receipt. A timer's enabled state is insufficient: inspect the actual last successful run, intended security origins and failure notifications. The strict refresh option makes transient retrieval errors fail the operation. An unreachable mirror means "inventory incomplete", not "zero updates needed".

Use `apt-cache policy` to inspect installed and candidate versions for the affected package and the actual kernel meta-package. The lab uses `linux-image-virtual`; an AWS, Azure, generic or HWE host can use a different supported track. Do not switch tracks merely to match an example. For a CVE, first establish the exact vendor release/package applicability, then compare complete Debian revisions with `dpkg --compare-versions`. A true comparison still needs active-process/kernel verification.

**Stop and recover:** hold rollout on an unexpected removal, unresolved dependency, failed refresh, unsupported source or failed workload gate. Do not force package downgrades or delete package-manager lock files. Restore the tested image/application state if required, reopen the vulnerability finding and apply a time-limited mitigation. Record failed update alerts and exception expiry with PATCH-03/04.

## 3. Kernel lifecycle: installed is not running

Track three states separately: the kernel currently running, kernel packages installed on disk, and the kernel the bootloader will select next. Keep the distribution's appropriate kernel meta-package so future security kernels continue to arrive. Verify the supported track for the exact OS release, hardware/cloud flavour and subscription coverage.

```bash
uname -r
dpkg-query -W 'linux-image-*'
df -h /boot /
test ! -f /run/reboot-required || cat /run/reboot-required
test ! -f /run/reboot-required.pkgs || cat /run/reboot-required.pkgs
sudo needrestart -r l
```

An absent reboot marker does not prove the running kernel contains a CVE fix. Do not choose the next-boot kernel by sorting filenames alone; inspect the actual bootloader/default entry and any saved selections. Keep a known-good fallback and verify console access. Avoid removing the running kernel or the only recovery kernel to free disk space.

Livepatch can reduce exposure for covered vulnerabilities, but coverage depends on the kernel, service state and specific fix. It does not eliminate kernel lifecycle management or every reboot. Verify livepatch status and the advisory rather than inferring protection from an installed client. [Canonical's reboot guidance](https://ubuntu.com/security/livepatch/docs/client/explanation/troubleshooting/do-i-need-to-reboot/).

**Apply and verify:** drain the canary, perform an approved reboot, then compare `uname -r` and package ownership with the intended supported kernel. Check boot errors, drivers, storage mounts, networking and application behavior before returning traffic. If the kernel fails, use the console to select the tested fallback, then investigate; rolling back may reintroduce the vulnerability.

For the tested GRUB image, inspect the default and saved selections together with the generated menu entries. UEFI/systemd-boot and cloud image-replacement workflows need their own supported equivalent. A `/boot/vmlinuz` symlink alone does not prove what a bootloader will choose.

```bash
cat /proc/sys/kernel/random/boot_id
dpkg-query -W 'linux-image-*'
sudo grep -nE '^[[:space:]]*GRUB_(DEFAULT|SAVEDEFAULT)=' /etc/default/grub
sudo grub-editenv list
sudo grep -nE '^[[:space:]]*(submenu|menuentry|linux|linuxefi)[[:space:]]' /boot/grub/grub.cfg
```

This excerpt preserves indented titles and submenu declarations; it is a navigation aid, not a boot-selection parser. If `/etc/default/grub.d` exists, inspect its applicable `.cfg` overrides too. Source settings may not yet have been regenerated into the active `grub.cfg`. Read the generated selection logic as text without sourcing or executing it: confirm whether `next_entry` takes precedence, whether the default uses `saved_entry`, or whether a fixed index/title/ID is selected. Follow the entire submenu path to the associated `linux`/`linuxefi` image. For example, `Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-142-generic` identifies a nested entry, not the first kernel printed by grep. Retain that mapping with the boot environment evidence. Custom boot logic, another active bootloader or an unresolved path leaves KERN-02 MANUAL. [GNU GRUB selection reference](https://www.gnu.org/software/grub/manual/grub/html_node/default.html).

**Expected:** the reviewed next-boot entry names the intended image; after reboot the boot ID changes and `uname -r` names that image. The old kernel stays available until recovery requirements are satisfied. KERN-02 remains open if the boot choice cannot be established. KERN-04 requires an actual recovery exercise, not merely an old image on disk. The companion lab booted the retained `6.8.0-142-generic` entry once, checked access/services/auditing, then returned to default `6.8.0-147-generic`. This proves a planned fallback boot on that VM; it does not prove recovery from every unbootable system or meet your application's recovery objective.

**Stop and recover:** do not reboot a second node until the canary passes access, storage, driver, networking and workload checks. If fallback is needed, record the reverted kernel, reopen any affected CVEs, keep compensating exposure controls and establish a new remediation deadline.

## 4. Firewall exposure: test the path packets take

Build a small service inventory: listener, protocol, address family, expected source, business purpose and owner. Check the host, cloud security groups/firewalls, load balancers, VPN routes and container networking together. A listener on `0.0.0.0` or `::` is not proof of public reachability, and a quiet local port scan is not proof that every external path is closed.

### Worked exposure inventory

- **Administration:** TCP 22, IPv4 and IPv6 if deployed, from named VPN/bastion ranges only; platform owner. Required proof: approved-source connection succeeds; an untrusted-source connection fails against the same live SSH listener.
- **Public web entry:** TCP 443 only where this host is the intended public endpoint; service owner. If a load balancer is the sole entry point, use its approved source paths instead of allowing the whole internet at the host.
- **Application backend:** TCP 8080 bound to loopback or permitted only from approved proxies; application owner. Prove it is unreachable from the untrusted test source while the backend is running.
- **Dependencies:** outbound DNS, NTP, package mirrors, central logging and workload endpoints; network/service owner. Include actual UDP dependencies and record return-traffic handling.

Download the exposure CSV and fill in real sources, destinations, interfaces, cloud rules and test vantage points before changing a rule. Documentation addresses below are never an approved production source list.

```bash
sudo ss -lntu
sudo ufw status verbose
sudo nft list ruleset
```

Read the native rules to understand the resulting policy; do not edit UFW-managed nftables/iptables chains directly. On a new UFW-managed host, allow the actual administration source and required application traffic **before** enabling default-deny ingress. These are documentation ranges and examples; replace them, verify your source as the server sees it, and preserve console recovery. Add the correct IPv6 management prefix when that path is used. [Ubuntu firewall documentation](https://ubuntu.com/server/docs/how-to/security/firewalls/).

```bash
# Example values only. Adapt to the approved service inventory.
sudo ufw allow from 192.0.2.10/32 to any port 22 proto tcp
sudo ufw allow from 2001:db8:100::10/128 to any port 22 proto tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

Inspect the resulting policy separately after the approved change:

```bash
sudo ufw status verbose
```

The egress allowance is a starting policy, not egress control. If you restrict outbound traffic, inventory DNS, NTP, package mirrors, telemetry and application dependencies first. Do not block required ICMPv6 blindly; neighbour discovery and path MTU behavior matter.

Docker-published ports can be routed before the normal UFW input policy. Review published mappings, forwarding chains and the backend-specific Docker guidance; do not disable Docker's firewall integration as a shortcut. [Docker firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/).

**Verify:** from authorized management and untrusted test sources, check only approved target ports over both IPv4 and IPv6. Prove that allowed traffic succeeds and disallowed traffic fails while a known listener exists. Include UDP where used. Record source, destination, port, family and result. If no external vantage point is available, mark external exposure unverified. Restore the exact prior rules from the console if the change interrupts required traffic.

**Expected:** every listener has an inventory row; every deployed address family has explicit policy and probe evidence. Confirm UFW's IPv6 configuration and existing rules. Changing the default policy does not remove a pre-existing broad allow rule. A firewall timeout without a known healthy listener and positive control is inconclusive. For UDP, require an application-level request/response or receiver evidence; an absent response alone does not establish filtering.

**Stop and recover:** before changing management access, prove an independent console/recovery route and retain the exact host and cloud policy. Restore through that route if access or dependencies fail; verify both allowed and denied paths after restoration. The lab's temporary application allowance is removed and original firewall files are compared byte-for-byte. NET-02/03 remain MANUAL for cloud and internet paths until those environments provide evidence.

## 5. Audit logging: prove an event reaches a person

System journals describe service behavior. Linux Audit records configured security events. Neither a running daemon nor a directory full of logs proves that the events you need are being retained and reviewed. Set retention according to investigation needs, privacy requirements, disk capacity and central storage policy.

For a small host, the following is a starting journal policy; size it for the workload. Persistent storage keeps local journals across boots, subject to limits and available disk. [systemd journal configuration](https://www.freedesktop.org/software/systemd/man/262/journald%40.conf.html).

```text
# /etc/systemd/journald.conf.d/60-cloudhero.conf
[Journal]
Storage=persistent
SystemMaxUse=256M
SystemKeepFree=512M
```

```bash
sudo systemctl restart systemd-journald
sudo journalctl --flush
```

**Inspect journal retention and time synchronization after the change:**

```bash
sudo journalctl --list-boots
sudo journalctl --disk-usage
timedatectl show -p NTPSynchronized
```

Create targeted audit rules for changes to SSH and privilege configuration. These rules are a narrow starting point, not a full audit policy. Ensure the referenced paths exist. The lab exercised the 64-bit rules on ARM64; systems that run a 32-bit ABI may need additional architecture-specific rules validated on that system. [Linux Audit rules](https://man7.org/linux/man-pages/man7/audit.rules.7.html).

```text
# /etc/audit/rules.d/50-cloudhero.rules
-a always,exit -F arch=b64 -F path=/etc/ssh/sshd_config -F perm=wa -k ssh_config
-a always,exit -F arch=b64 -F dir=/etc/ssh/sshd_config.d -F perm=wa -k ssh_config
-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -k privilege_config
-a always,exit -F arch=b64 -F dir=/etc/sudoers.d -F perm=wa -k privilege_config
```

```bash
# Approved configuration change only:
sudo augenrules --load
```

**Inspect the loaded audit policy:**

```bash
sudo auditctl -l
sudo auditctl -s
```

`augenrules` assembles persistent rule files and loads the resulting policy. If auditing is immutable (`enabled 2`), a reboot may be needed to change it; do not disable protection to force a reload. Watch the backlog and `lost` counter under representative load. Define disk-full and forwarding-failure behavior deliberately rather than copying a setting that could halt a production workload. [augenrules reference](https://man7.org/linux/man-pages/man8/augenrules.8.html).

### Audit retention is separate from journal retention

The journal's `SystemMaxUse` does not limit `/var/log/audit/audit.log`. Inspect the effective auditd configuration separately:

```bash
sudo grep -Ev '^[[:space:]]*(#|$)' /etc/audit/auditd.conf
sudo auditctl -s
df -h /var/log /var/log/audit
```

**Expected:** writing is enabled; rotation or archival matches the retention policy; low-space, full-disk and write-error actions have named responders. As an illustrative capacity calculation, 8 files at 64 MiB is roughly a 512 MiB local rotation budget, not a guarantee of a number of days. Measure event volume and allow headroom. Keeping every log indefinitely can exhaust disk; suspending logging can leave a running but blind service. Record these availability/detection tradeoffs explicitly. [Ubuntu auditd configuration](https://manpages.ubuntu.com/manpages/noble/man5/auditd.conf.5.html).

Verify rotation in staging with an approved rotate operation, then prove a new event reaches the active file and an earlier event remains available. Exercise low-space/queue alert logic on a disposable fixture; never fill production storage to test an alert. Capture audit `lost` counters before and after a representative workload and investigate any increase.

### A concrete central-delivery test

The companion rsyslog example uses a trusted CA, expected receiver certificate identity, client certificate, bounded disk-assisted queue and retry policy. Provision the organization's certificates and validate `rsyslogd -N1` before a reload/restart. Keep the distribution's confinement policy enabled; grant only the required paths through the reviewed policy. The lab had to move its fixture into permitted paths rather than disable AppArmor. [rsyslog TLS client guidance](https://docs.rsyslog.com/doc/tutorials/tls_cert_client.html).

A syslog marker does not demonstrate Linux Audit ingestion. Include an explicit approved audit input or supported audit collector, with permissions and confinement validated, and test that stream separately. The downloadable examples name the certificate, input and queue assumptions; use one ingestion route per stream to avoid duplicates.

```bash
# Approved delivery exercise only; record this exact ID and UTC timestamp.
MARKER="linux-baseline-$(date -u +%Y%m%dT%H%M%SZ)"
logger -t linux-baseline "$MARKER"
sudo auditctl -m "$MARKER-audit"
```

**Expected receiver receipt:** marker ID, host alias, source-event UTC time, receiver UTC time, stream and measured delivery delay. Search the central receiver for both IDs. Then trigger the approved detection rule and retain its ticket/notification plus human acknowledgement. Match the delivery and acknowledgement deadlines from the policy worksheet. Missing receiver access leaves AUD-03 MANUAL; missing human acknowledgement leaves AUD-04 MANUAL.

In staging, reject a receiver with the wrong certificate identity, simulate a bounded receiver outage, recover it and reconcile every expected sequence ID at the sink. Record the expected count, unique receipts, missing IDs and duplicates; a final marker alone cannot prove delivery of earlier messages. TCP/TLS and a queue do not guarantee exactly-once delivery; use an acknowledged protocol or an application-level reconciliation requirement where that is necessary. The revised lab observed all 300 messages sent after connection refusal, with no missing IDs or duplicates. That proves the tested queue-recovery sequence, not preservation of ambiguous in-flight messages during an abrupt disconnect. [rsyslog forwarding and queue guidance](https://docs.rsyslog.com/doc/configuration/modules/omfwd.html).

For queue monitoring, use the named action's `impstats` queue size, disk-spool use, discard counters and forwarding diagnostics. Agree thresholds, measurement freshness, alert destination and response deadline. A disconnected exporter or missing metrics must alert rather than report an empty queue. The lab triggered a real queue-size threshold and wrote a receipt to an isolated local alert sink while keeping the filesystem below its capacity limit. Production notification routing and human acknowledgement remain AUD-04 evidence. AppArmor remained enforcing; restricted optional resource metrics did not substitute for the observed queue counter. Disk-full behavior and crash durability are separate tests, not implied by a queue-pressure exercise. [rsyslog statistics](https://docs.rsyslog.com/doc/configuration/modules/impstats.html).

**Verify:** in staging, make a harmless controlled change to a watched configuration file, retrieve its event by key, restore the exact original file, and verify its checksum. Separately send an approved unique marker through the central pipeline and record its receipt and alert routing. After a reboot, prove that earlier journals remain and audit rules reload. Use authenticated transport, restricted central access and retention controls; root on a host can tamper with its local evidence. The lab verifies local capture and persistence; central delivery and human response require your production environment.

## 6. Configuration drift: keep a trusted desired state

Put the intended package sources, SSH policy, firewall rules, logging policy, service configuration and kernel track in a reviewed configuration repository. Record the approved revision with each deployment. Use your existing configuration-management system to compare expected and observed state, including extra files, removed files, permissions, enabled services and package inventory.

A reviewed inventory must cover more than file bytes. The companion `baseline.py` records path names, file types, owners, permissions, file hashes and symlink targets. Directory scope detects unexpected drop-ins and removed files. The starter scope includes the complete `/etc/apt`, journald drop-in, UFW, sudo and rsyslog configuration locations, alongside SSH, Audit and local systemd units. This detects a new late APT or journald override as well as changes to before/after firewall rules. It hashes regular file bytes locally; it does not print file contents. Treat the manifest and paths as sensitive metadata, especially where configuration contains credentials.

Review include paths and overrides for the actual host: vendor directories, runtime overrides and symlink targets can live outside this starter scope. Symlinks are recorded without traversing their targets; add approved target paths separately when needed. Missing mandatory roots fail collection; explicitly document any legitimate scope adaptation instead of silently skipping it. Package and runtime state require separate comparisons. Authenticate the path list and manifest using an independently controlled repository/artifact digest before trusting a local comparison. [Ubuntu configuration ordering](https://manpages.ubuntu.com/manpages/noble/man5/apt.conf.5.html).

```bash
# Review baseline.py and baseline-paths.json first. Every listed root must exist.
# Approved creation only, from a quiescent, reviewed configuration:
sudo install -d -m 0700 /var/lib/cloudhero-baseline
sudo python3 baseline.py create --paths baseline-paths.json \
  --manifest /var/lib/cloudhero-baseline/files.json
```

**Compare with the independently approved manifest; do not recreate it to clear drift:**

```bash
# Subsequent observational comparison against the independently approved scope:
sudo python3 baseline.py check --paths baseline-paths.json \
  --manifest /var/lib/cloudhero-baseline/files.json
```

**Expected:** exit 0 means the scoped inventory matches; exit 1 means drift; exit 2 means a collection/input error. A missing input during creation must leave the previous manifest unchanged. Creation writes a private temporary file and replaces the manifest only after the entire inventory succeeds. A failed collection must never replace an approved baseline with a partial one.

For integration with `assess.sh`, an authorized operator can install the reviewed tool at `/usr/local/lib/cloudhero/baseline.py` and the approved scope at `/etc/cloudhero/baseline-paths.json`, owned by root and not writable by the assessment account. Keep the approved manifest at `/var/lib/cloudhero-baseline/files.json`. The collector performs a comparison only when these exist; it never creates or promotes a baseline. Keep the authoritative copies and digests outside the target host.

**Verify:** test content change, an unexpected SSH drop-in, file removal, changed mode/owner and symlink substitution in staging. Restore the original state and obtain a clean comparison without regenerating the manifest. The companion regression suite includes these cases and proves that missing or unsupported inputs cannot replace the approved manifest. It is a quiescent inventory tool, not a defence against an attacker concurrently controlling root; local root can also rewrite the tool and manifest.

Compare these additional inventories with their reviewed revision: installed package versions and holds; enabled service units and overrides; effective SSH contexts; active firewall rules; kernel track; central logging destinations. Normalize only fields known to be volatile, not meaningful differences. Use the configuration manager's safe observation mode after reviewing any plugins it can execute. A filesystem MATCH alone cannot pass DRIFT-03.

**Stop and recover:** never refresh the baseline simply to remove an alert. Triage the change against an authorized deployment; investigate unexplained security-sensitive drift before overwriting potential evidence. Restore from the approved source if appropriate, repeat behavior tests, and promote a new baseline only through a reviewed change. Track exception owner, compensating control, approver and expiry.

## 7. Production verification: close the change with evidence

Define acceptance criteria before maintenance. Capture the same checks before the change, after each meaningful step and after reboot. Use a canary and stop the rollout if access, service health or detection degrades.

```bash
uname -r
systemctl --failed --no-pager
sudo dpkg --audit
sudo ss -lntu
sudo /usr/sbin/sshd -t
sudo auditctl -s
sudo journalctl --list-boots
```

These commands are an operating-system checkpoint. Complete the following with workload-specific evidence:

- A fresh authorized admin login and required privilege escalation succeed; the recovery path is available.
- The intended kernel and updated services are active; package transactions are complete and restart requirements are resolved or tracked.
- Approved ingress succeeds and denied ingress fails from the intended source networks over every deployed address family. Cloud and container paths are included.
- A representative user transaction, background job and dependency call succeed. Latency, error rate and saturation remain within your acceptance thresholds for an agreed observation window.
- Security events reach the central destination and the responsible team can receive the alert. No unexplained event loss or disk pressure is present.
- Configuration matches the approved revision; exceptions have owners and expiry dates. Recovery and rollback evidence is attached to the change.

If any item lacks evidence, keep it open. A health endpoint returning HTTP 200 does not prove checkout, authentication, queue processing or data integrity. Record what was actually tested, by whom, when and from where. Return a canary to service only after its acceptance criteria pass, then expand the rollout in stages.

### A completed decision gate

Use the change worksheet to specify the exact transaction, expected result, maximum error/latency change, observation period and minimum healthy capacity before maintenance. These values come from the service's objectives; a generic hardening article cannot choose them for your application.

In the companion's synthetic application, release A passes a representative transaction. Release B returns HTTP 200 from its health endpoint but produces the wrong transaction result. The verifier marks the gate failed, holds advancement, restores release A and proves the expected transaction again. The recorded result demonstrates rollback behavior; a production service must supply its own real transaction, dependency, background-job and recovery evidence.

**Expected:** VERIFY-01 has complete criteria and owners; VERIFY-02 has successful OS/access checks; VERIFY-03 has real workload results within thresholds; VERIFY-04 has an explicit proceed/hold/rollback decision. A test command that exits successfully but returns the wrong semantic result fails the gate. Collect failed-unit names and `dpkg --audit` output, not just their command exit statuses.

**Stop and recover:** abort on loss of management access, unexpected public exposure, missing logs, failed representative work or breached acceptance thresholds. Do not advance another batch while the failed gate is unresolved. Restore the tested state, repeat the same acceptance tests and record whether the vulnerability is reintroduced. A rollback that restores uptime but loses required data is not a successful recovery.
