#!/usr/bin/env bash
# Configuration-only collector. No installs, refreshes, restarts, or remediation.
# Capture privately on the approved target with: bash collect-report.sh ./assess.sh
set -uo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C
export SYSTEMD_PAGER=cat
export PAGER=cat
errors=0
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
  elif [[ $rc -ne 0 ]]; then
    echo 'ERROR: collection failed.'; errors=$((errors+1))
  fi
  return 0
}
run() { run_checked normal "$@"; }
main() {
if [[ $(uname -s) != Linux ]]; then
  echo 'ERROR: this collector requires Linux.' >&2
  exit 2
fi
if [[ $EUID -ne 0 ]]; then
  echo 'ERROR: root is needed to read effective SSH, firewall and audit configuration.' >&2
  exit 2
fi
errors=0
run 'Collection time (UTC)' date -u +%FT%TZ
run 'Distribution' cat /etc/os-release
run 'Running kernel' uname -r
run 'Architecture' uname -m
run_checked virtualization 'Virtualization' systemd-detect-virt
run 'Boot identity' cat /proc/sys/kernel/random/boot_id
run 'SSH syntax' /usr/sbin/sshd -t
# Only display allowlisted effective settings; no key material or arbitrary config.
printf '\n### SSH effective settings (global defaults; inspect Match contexts separately)\n'
printf "[observed_at=%s]\n$ timeout 30 /usr/sbin/sshd -T\n" "$(date -u +%FT%TZ)"
ssh_effective=$(timeout 30 /usr/sbin/sshd -T 2>&1); rc=$?
printf "[exit=%s]\n" "$rc"
if [[ $rc -eq 0 ]]; then
  printf '%s\n' "$ssh_effective" | grep -E '^(port|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|x11forwarding|allowtcpforwarding|allowagentforwarding|usepam|loglevel|allowusers|allowgroups) '
else printf 'ERROR: sshd -T failed (exit=%s).\n' "$rc"; errors=$((errors+1)); fi
run 'SSH service/socket state' systemctl show ssh.service ssh.socket -p Id -p ActiveState -p SubState -p UnitFileState
run 'Listening sockets (no command lines)' ss -lntu
run 'Host firewall' ufw status verbose
run 'Loaded audit rules' auditctl -l
run 'Audit health' auditctl -s
run 'Audit rotation/pressure policy' awk '/^[[:space:]]*(log_file|write_logs|flush|freq|max_log_file|num_logs|max_log_file_action|space_left|space_left_action|admin_space_left|admin_space_left_action|disk_full_action|disk_error_action)[[:space:]]*=/' /etc/audit/auditd.conf
run 'Journal fragments (resolve overrides and vendor defaults)' bash -o pipefail -c 'systemd-analyze cat-config systemd/journald.conf | awk "/^[[:space:]]*(Storage|SystemMaxUse|SystemKeepFree|MaxRetentionSec)[[:space:]]*=/"'
run 'Journal boots retained' journalctl --list-boots --no-pager
run 'Journal disk usage' journalctl --disk-usage
run 'Time synchronization' timedatectl show -p NTPSynchronized -p Timezone
run 'Failed services' systemctl --failed --no-pager --plain
run 'Enabled service inventory' systemctl list-unit-files --state=enabled --no-pager --plain
run 'Boot and log filesystem capacity' df -h / /boot /var/log /var/log/audit
run 'Update timers' systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager
run_checked enablement 'Update timer enablement' systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer
printf '\n### Effective periodic and reboot policy\n'
if command -v apt-config >/dev/null; then
  run 'Effective APT periodic/reboot/origin settings' bash -o pipefail -c 'apt-config dump | awk '\''/^(APT::Periodic::(Update-Package-Lists|Unattended-Upgrade)|Unattended-Upgrade::(Automatic-Reboot|Allowed-Origins|Origins-Pattern))/ {print; found=1} END {if (!found) print "MANUAL: no explicit settings found; resolve installed vendor defaults and approved pipeline."}'\'''
else
  echo 'ERROR: apt-config unavailable; effective update policy not collected.'
  errors=$((errors+1))
fi
if command -v dpkg-query >/dev/null; then
  run 'Installed baseline packages' dpkg-query -W '-f=${binary:Package} ${Version} ${db:Status-Status}\n' openssh-server ufw auditd unattended-upgrades 'linux-image-*'
  run 'Package holds' apt-mark showhold
  run 'Installed package inventory' dpkg-query -W '-f=${binary:Package}\t${Version}\t${db:Status-Status}\n'
  run 'Update simulation (existing metadata only)' apt-get -s upgrade
  run 'Update simulation including new dependencies (existing metadata only)' apt-get -s --with-new-pkgs upgrade
  run 'APT metadata timestamp evidence' find /var/lib/apt/lists -maxdepth 1 -type f -name '*InRelease' -printf '%TY-%Tm-%TdT%TH:%TM:%TS %f\n'
  run 'Package consistency' dpkg --audit
  printf '\n### Reboot marker\n'
  if [[ -e /run/reboot-required ]]; then cat /run/reboot-required; else echo 'Absent: this alone does not prove no reboot is needed.'; fi
  if [[ -e /run/reboot-required.pkgs ]]; then cat /run/reboot-required.pkgs; fi
else
  errors=$((errors+1))
  printf '\nERROR: Ubuntu/Debian package checks unavailable. Use vendor-specific checks.\n'
fi
if [[ -r /usr/local/lib/cloudhero/baseline.py && -r /etc/cloudhero/baseline-paths.json && -r /var/lib/cloudhero-baseline/files.json ]]; then
  run_checked inventory 'Approved full file inventory' /usr/bin/python3 /usr/local/lib/cloudhero/baseline.py check --paths /etc/cloudhero/baseline-paths.json --manifest /var/lib/cloudhero-baseline/files.json
else printf '\nMANUAL: reviewed inventory tool/scope/manifest not installed in the documented locations. No file-drift conclusion.\n'; fi
printf '\nMANUAL: verify metadata freshness, vendor support/CVE status, next-boot kernel, per-user SSH Match contexts, cloud firewalls, external IPv4/IPv6 reachability, central log delivery, policy owner, baseline provenance, and production health.\n'
printf '\nCollection errors: %s. This is a collector result, not a security assessment. A timeout is exit 124. The fixed 28-control catalogue must still be evaluated.\n' "$errors"
[[ $errors -eq 0 ]]
}
if [[ ${BASH_SOURCE[0]:-$0} == "$0" ]]; then main "$@"; fi
