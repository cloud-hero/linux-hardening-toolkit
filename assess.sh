#!/usr/bin/env bash
# LH-1.5: observational collector for Ubuntu, Debian, Fedora and Amazon Linux 2023.
# No installations, package-index refreshes, service changes or remediation.
set -uo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C SYSTEMD_PAGER=cat PAGER=cat
errors=0
manuals=0
manual() { printf 'MANUAL: %s\n' "$*"; manuals=$((manuals+1)); }
run_checked() {
  local kind=$1 label=$2; shift 2
  local output rc
  printf '\n### %s\n[observed_at=%s]\n$' "$label" "$(date -u +%FT%TZ)"
  printf ' %q' "$@"; printf '\n'
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR: tool unavailable: %s\n[exit=127]\n' "$1"
    errors=$((errors+1)); return 0
  fi
  output=$(timeout 30 "$@" 2>&1); rc=$?
  printf '%s\n[exit=%s]\n' "$output" "$rc"
  if [[ $kind == virtualization && $rc -eq 1 && $output == none ]]; then
    echo 'OBSERVED: no virtualization detected; this is not a collection failure.'
  elif [[ $kind == inventory && $rc -eq 1 ]]; then
    echo 'OBSERVED: drift detected; retain the finding, not a collection failure.'
  elif [[ $kind == enablement && $rc -eq 1 && -n $output ]] &&
       ! printf '%s\n' "$output" | grep -Eqv '^(enabled|enabled-runtime|disabled|masked|masked-runtime|static|indirect|alias|linked|linked-runtime|generated|transient)$'; then
    echo 'OBSERVED: timer enablement state; evaluate against the approved update pipeline.'
  elif [[ $kind == cached_updates && $rc -eq 100 ]]; then
    echo 'OBSERVED: cached metadata lists available updates. This is not a collection failure or proof of current vendor coverage.'
  elif [[ $kind == cached_updates && $rc -ne 0 && $rc -ne 124 ]] &&
       printf '%s\n' "$output" | grep -Eiq 'cache.only enabled but no cache|no cached metadata|no usable cache|no available cached metadata|cacheonly.*no cache|no cache for repository'; then
    manual 'Required repository metadata is unavailable locally. No network refresh was attempted; package freshness remains unresolved.'
  elif [[ $rc -ne 0 ]]; then
    echo 'ERROR: collection failed.'; errors=$((errors+1))
  fi
  return 0
}
run() { run_checked normal "$@"; }
optional() {
  local label=$1; shift
  if command -v "$1" >/dev/null 2>&1; then run "$label" "$@"; else printf '\n### %s\n' "$label"; manual "Tool $1 is not installed. This observation is not a PASS; do not install it just to complete collection."; fi
}
optional_file() {
  local label=$1 file=$2 pattern=$3
  if [[ -r $file ]]; then run "$label" awk "$pattern" "$file"; else printf '\n### %s\n' "$label"; manual "Configuration file $file is absent or unreadable."; fi
}
package_evidence() {
  local os_id=$1 scratch=$2 manager cache path
  if command -v dpkg-query >/dev/null && command -v apt-get >/dev/null; then
    echo 'PACKAGE_FAMILY=apt'
    run 'Installed package inventory' dpkg-query -W '-f=${binary:Package}\t${Version}\t${db:Status-Status}\n'
    optional 'Package holds' apt-mark showhold
    run 'Update simulation (existing metadata only)' apt-get -s -o Debug::NoLocking=1 upgrade
    run 'Update simulation including new dependencies (existing metadata only)' apt-get -s -o Debug::NoLocking=1 --with-new-pkgs upgrade
    run 'Package consistency' dpkg --audit
    run 'Effective APT periodic/reboot/origin settings' bash -o pipefail -c 'apt-config dump | awk '\''/^(APT::Periodic::(Update-Package-Lists|Unattended-Upgrade)|Unattended-Upgrade::(Automatic-Reboot|Allowed-Origins|Origins-Pattern))/ {print; found=1} END {if (!found) print "MANUAL: no explicit settings found; resolve installed vendor defaults and approved pipeline."}'\'''
    if [[ -d /var/lib/apt/lists ]]; then
      run 'APT metadata timestamps' find /var/lib/apt/lists -maxdepth 1 -type f -name '*InRelease' -printf '%TY-%Tm-%TdT%TH:%TM:%TS %f\n'
      if ! find /var/lib/apt/lists -maxdepth 1 -type f -name '*InRelease' -print -quit | grep -q .; then manual 'APT metadata is absent. A successful simulation cannot establish available updates; no refresh was attempted.'; fi
    else manual 'APT metadata directory is absent; current update coverage is unresolved.'; fi
    run 'APT update service and timer states' systemctl show apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState -p LastTriggerUSec
  elif command -v rpm >/dev/null; then
    echo 'PACKAGE_FAMILY=rpm'
    run 'Installed RPM package inventory' rpm -qa '--qf=%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}\n'
    if command -v dnf5 >/dev/null; then manager=dnf5;cache=/var/cache/libdnf5
    elif command -v dnf >/dev/null; then manager=dnf;cache=/var/cache/dnf
    else manual 'Neither dnf5 nor dnf is installed; cached update evidence is unavailable.';return;fi
    run 'Package manager version' "$manager" --version
    if [[ -d $cache ]]; then
      run 'RPM repository metadata timestamps' find "$cache" -type f '(' -name '*repomd.xml' -o -name '*.solv' -o -name 'metalink.xml' -o -name 'mirrorlist' ')' -printf '%TY-%Tm-%TdT%TH:%TM:%TS %p\n'
    fi
    if [[ ! -d $cache ]] || ! find "$cache" -type f '(' -name '*repomd.xml' -o -name '*.solv' ')' -print -quit | grep -q .; then
      manual 'No RPM repository metadata is cached. Update availability is unknown; no repository refresh was attempted.'
    else
      # DNF may create solv/lock files even with --cacheonly. Work from a private
      # metadata copy so assessment cannot rewrite the host's repository cache.
      mkdir -p "$scratch/cache" "$scratch/log" "$scratch/state"
      if ! (timeout 30 tar -C "$cache" --exclude='*/packages' --exclude='*.rpm' --exclude='metadata_lock.pid' -cf - . | timeout 30 tar -C "$scratch/cache" -xf -); then
        echo 'ERROR: could not copy cached RPM metadata into the private scratch directory.'; errors=$((errors+1)); return
      fi
      if [[ $manager == dnf5 ]]; then
      run_checked cached_updates 'Available RPM updates (cache only; exit 100 means updates exist)' dnf5 --cacheonly --setopt="system_cachedir=$scratch/cache" --setopt="cachedir=$scratch/cache" --setopt="logdir=$scratch/log" --setopt="persistdir=$scratch/state" --setopt='*.skip_if_unavailable=False' check-upgrade
    else
      run_checked cached_updates 'Available RPM updates (cache only; exit 100 means updates exist)' dnf --cacheonly --setopt="cachedir=$scratch/cache" --setopt="logdir=$scratch/log" --setopt="persistdir=$scratch/state" --setopt='*.skip_if_unavailable=False' check-update
    fi
    fi
    for path in /etc/dnf/dnf.conf /etc/dnf/automatic.conf /etc/dnf/automatic.conf.d/*.conf /etc/yum.repos.d/*.repo; do
      [[ -f $path ]] || continue
      run 'RPM update/signing policy (allowlisted fields only)' awk '/^[[:space:]]*(\[|gpgcheck[[:space:]]*=|repo_gpgcheck[[:space:]]*=|sslverify[[:space:]]*=|enabled[[:space:]]*=|skip_if_unavailable[[:space:]]*=|apply_updates[[:space:]]*=|download_updates[[:space:]]*=|upgrade_type[[:space:]]*=|reboot[[:space:]]*=)/' "$path"
    done
    run 'RPM automatic update service and timer states' systemctl show dnf-automatic.timer dnf-automatic-install.timer dnf5-automatic.timer dnf-automatic.service dnf5-automatic.service -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState -p LastTriggerUSec
    if [[ $os_id == amzn ]]; then
      if [[ -r /etc/dnf/vars/releasever ]]; then run 'Amazon Linux repository release pin' cat /etc/dnf/vars/releasever; fi
      manual 'Amazon Linux 2023 repositories are version-locked. No cached updates within that pin does not prove that the latest AL2023 release or all security fixes are installed. Obtain approved vendor release evidence separately.'
    fi
    manual 'RPM version locks, package consistency, repository completeness and service restart/reboot requirements need approved vendor-specific evidence; the collector does not install plugins or verify every package file.'
  else manual 'No supported APT or RPM package manager detected. Supply distribution-specific package and update evidence.';fi
  printf '\n### Reboot marker\n'
  if [[ -r /run/reboot-required ]]; then cat /run/reboot-required;else echo 'Absent: this alone does not prove no reboot is needed.';fi
  if [[ -r /run/reboot-required.pkgs ]]; then cat /run/reboot-required.pkgs;fi
}
main() {
  if [[ $(uname -s) != Linux ]]; then echo 'ERROR: this collector requires Linux.' >&2;exit 2;fi
  if [[ $EUID -ne 0 ]]; then echo 'ERROR: root is needed to read effective SSH, firewall and audit configuration.' >&2;exit 2;fi
  if ! command -v timeout >/dev/null; then echo 'ERROR: GNU timeout is required to bound collection commands.' >&2;exit 2;fi
  errors=0;manuals=0
  local os_id scratch path firewall_seen=0
  os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' /etc/os-release)
  scratch=$(mktemp -d /tmp/cloudhero-collector.XXXXXXXX) || exit 2
  trap 'rm -rf -- "$scratch"' RETURN
  printf 'CloudHero Linux evidence collector LH-1.5\nAssessment only: existing state, no remediation.\n'
  run 'Collection time (UTC)' date -u +%FT%TZ
  run 'Distribution' cat /etc/os-release
  run 'Running kernel' uname -r
  run 'Architecture' uname -m
  run_checked virtualization 'Virtualization' systemd-detect-virt
  run 'Boot identity' cat /proc/sys/kernel/random/boot_id
  run 'SSH syntax' /usr/sbin/sshd -t
  printf '\n### SSH effective settings (global defaults; inspect Match contexts separately)\n[observed_at=%s]\n' "$(date -u +%FT%TZ)"
  local effective rc
  effective=$(timeout 30 /usr/sbin/sshd -T 2>&1);rc=$?
  printf '[exit=%s]\n' "$rc"
  if [[ $rc -eq 0 ]];then printf '%s\n' "$effective" | grep -E '^(port|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|x11forwarding|allowtcpforwarding|allowagentforwarding|usepam|loglevel|allowusers|allowgroups) '
  else printf 'ERROR: sshd -T failed (exit=%s).\n' "$rc";errors=$((errors+1));fi
  run 'SSH service/socket states (both distro naming conventions)' systemctl show ssh.service ssh.socket sshd.service sshd.socket -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState
  run 'Listening sockets (no command lines)' ss -lntu
  for path in ufw nft iptables ip6tables;do
    command -v "$path" >/dev/null || continue;firewall_seen=1
    case $path in ufw)run 'UFW status' ufw status verbose;;nft)run 'nftables ruleset' nft list ruleset;;iptables)run 'IPv4 iptables rules' iptables -S;;ip6tables)run 'IPv6 iptables rules' ip6tables -S;;esac
  done
  if command -v firewall-cmd >/dev/null;then
    firewall_seen=1;run 'firewalld service state' systemctl show firewalld.service -p LoadState -p ActiveState -p SubState -p UnitFileState
    if systemctl is-active --quiet firewalld.service;then run 'firewalld active zone configuration' firewall-cmd --list-all-zones
    else manual 'firewalld is not active. Inspect collected kernel rules and the approved network policy.';fi
  fi
  [[ $firewall_seen -eq 1 ]] || manual 'No supported host-firewall inspection tool installed. Host filtering is unverified; cloud firewall evidence remains separate.'
  optional 'Loaded audit rules' auditctl -l
  optional 'Audit health' auditctl -s
  optional_file 'Audit rotation/pressure policy' /etc/audit/auditd.conf '/^[[:space:]]*(log_file|write_logs|flush|freq|max_log_file|num_logs|max_log_file_action|space_left|space_left_action|admin_space_left|admin_space_left_action|disk_full_action|disk_error_action)[[:space:]]*=/'
  run 'Journal configuration (resolve vendor defaults and overrides)' bash -o pipefail -c 'systemd-analyze cat-config systemd/journald.conf | awk '\''/^[[:space:]]*(Storage|SystemMaxUse|SystemKeepFree|MaxRetentionSec)[[:space:]]*=/ {print; found=1} END {if (!found) print "MANUAL: no explicit journal values; review vendor defaults and approved retention policy."}'\'''
  run 'Journal boots retained' journalctl --list-boots --no-pager
  run 'Journal disk usage' journalctl --disk-usage
  run 'Time synchronization' timedatectl show -p NTPSynchronized -p Timezone
  run 'Failed services' systemctl --failed --no-pager --plain
  run 'Enabled service inventory' systemctl list-unit-files --state=enabled --no-pager --plain
  for path in / /boot /var/log /var/log/audit;do
    if [[ -d $path ]];then run "Filesystem capacity: $path" df -h "$path";else manual "Directory $path is absent; corresponding log retention/capacity remains unresolved.";fi
  done
  if command -v getenforce >/dev/null;then run 'SELinux enforcement mode' getenforce;fi
  if [[ -r /sys/module/apparmor/parameters/enabled ]];then run 'AppArmor kernel enablement' cat /sys/module/apparmor/parameters/enabled;fi
  package_evidence "$os_id" "$scratch"
  if [[ -r /usr/local/lib/cloudhero/baseline.py && -r /etc/cloudhero/baseline-paths.json && -r /var/lib/cloudhero-baseline/files.json ]];then
    run_checked inventory 'Approved full file inventory' /usr/bin/python3 /usr/local/lib/cloudhero/baseline.py check --paths /etc/cloudhero/baseline-paths.json --manifest /var/lib/cloudhero-baseline/files.json
  else manual 'Reviewed inventory tool/scope/manifest not installed. No file-drift conclusion; no baseline was created.';fi
  manual 'Verify metadata freshness, vendor support/CVE status, next-boot kernel, per-user SSH Match contexts, cloud firewalls, external reachability, central log delivery, policy, baseline provenance and real service health.'
  printf '\nCollection errors: %s. Manual collector notes: %s (individual observations can contain additional gaps). These are collection results, not control verdicts. A timeout is exit 124. Evaluate all 28 controls.\n' "$errors" "$manuals"
  [[ $errors -eq 0 ]]
}
if [[ ${BASH_SOURCE[0]:-$0} == "$0" ]];then main "$@";fi
