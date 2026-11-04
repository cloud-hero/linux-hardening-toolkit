#!/usr/bin/env bash
# Run as root only inside the disposable VM; creates temporary test network state.
set -euo pipefail
[[ $EUID -eq 0 && -d /root/hardening-backup ]] || exit 2
pass() { printf 'PASS | %s\n' "$1"; }
check_setting() {
  local actual
  actual=$(/usr/sbin/sshd -T -C user=andrei,host=lab-client,addr=192.168.5.2 | grep "^$1 ")
  [[ $actual == "$1 $2" ]] || { echo "FAIL | $actual"; exit 1; }
  pass "SSH $actual"
}
/usr/sbin/sshd -t
check_setting permitrootlogin no
check_setting passwordauthentication no
check_setting kbdinteractiveauthentication no
check_setting pubkeyauthentication yes
check_setting allowtcpforwarding no
# Deliberately invalid fixture must fail validation without touching the live file.
printf 'ThisDirectiveDoesNotExist yes\n' > /run/cloudhero-invalid-sshd.conf
if /usr/sbin/sshd -t -f /run/cloudhero-invalid-sshd.conf 2>/run/cloudhero-invalid.err; then
  echo 'FAIL | invalid SSH fixture accepted'; exit 1
fi
pass 'Invalid SSH configuration rejected before reload'
systemctl is-active --quiet auditd
[[ $(auditctl -l | grep -c 'key=\| -k ') -ge 4 ]]
[[ $(auditctl -s | awk '$1=="lost" {print $2}') == 0 ]]
pass 'Audit rules loaded; lost event counter is zero'
sha256sum --check /var/lib/cloudhero-baseline/config.sha256
pass 'Approved file hashes match'
audit_start=$(date '+%H:%M:%S')
printf '\n# deliberate lab drift marker\n' >> /etc/ssh/sshd_config.d/00-cloudhero.conf
if sha256sum --check /var/lib/cloudhero-baseline/config.sha256 >/run/cloudhero-drift.txt 2>&1; then
  echo 'FAIL | drift not detected'; exit 1
fi
pass 'Deliberate SSH configuration drift detected'
# Restore the exact pre-test bytes, not an updated manifest.
sed -i '/^# deliberate lab drift marker$/d' /etc/ssh/sshd_config.d/00-cloudhero.conf
truncate -s -1 /etc/ssh/sshd_config.d/00-cloudhero.conf
sha256sum --check /var/lib/cloudhero-baseline/config.sha256
pass 'Restored configuration matches original baseline'
# Audit events can take several seconds to be completed/flushed.
for attempt in {1..10}; do
  if ausearch --input-logs -k ssh_config -ts today "$audit_start" -i > /run/cloudhero-audit-event.txt 2>/dev/null; then break; fi
  sleep 1
done
grep -q '00-cloudhero.conf' /run/cloudhero-audit-event.txt
pass 'SSH configuration write produced a retrievable audit event'
systemctl is-enabled --quiet apt-daily.timer apt-daily-upgrade.timer
pass 'Both APT timers enabled'
apt-config dump | grep -F 'APT::Periodic::Unattended-Upgrade "1";'
apt-config dump | grep -F 'Unattended-Upgrade::Automatic-Reboot "false";'
pass 'Daily automatic security updates configured; automatic reboot disabled'
ufw status | grep -q 'Status: active'
pass 'Host firewall active'
# Independent network namespace provides ingress, not a loopback self-test.
cleanup() {
  ip netns del ch-client 2>/dev/null || :
  ip link del ch-host 2>/dev/null || :
}
trap cleanup EXIT
ip netns add ch-client
ip link add ch-host type veth peer name ch-peer
ip link set ch-peer netns ch-client
ip addr add 198.18.0.1/24 dev ch-host
ip -6 addr add fd42:face::1/64 dev ch-host nodad
ip link set ch-host up
ip netns exec ch-client ip link set lo up
ip netns exec ch-client ip addr add 198.18.0.2/24 dev ch-peer
ip netns exec ch-client ip addr add 198.18.0.3/24 dev ch-peer
ip netns exec ch-client ip -6 addr add fd42:face::2/64 dev ch-peer nodad
ip netns exec ch-client ip -6 addr add fd42:face::3/64 dev ch-peer nodad
ip netns exec ch-client ip link set ch-peer up
ip netns exec ch-client python3 - <<'PY'
import socket
cases=[('IPv4 approved SSH','198.18.0.2','198.18.0.1',22,True),
       ('IPv4 unapproved SSH','198.18.0.3','198.18.0.1',22,False),
       ('IPv6 approved SSH','fd42:face::2','fd42:face::1',22,True),
       ('IPv6 unapproved SSH','fd42:face::3','fd42:face::1',22,False)]
for name,src,dst,port,expected in cases:
    s=socket.socket(socket.AF_INET6 if ':' in src else socket.AF_INET,socket.SOCK_STREAM)
    s.settimeout(2);s.bind((src,0))
    try:s.connect((dst,port));connected=True
    except socket.timeout:connected=False
    except OSError as e:raise AssertionError(f'{name}: ambiguous network failure: {e}')
    finally:s.close()
    assert connected==expected,(name,connected,expected)
    print(f'PASS | {name}: {src} -> {dst}:{port}: '+('connected' if connected else 'timed out (filtered)'),flush=True)
PY
pass 'IPv4 and IPv6 allowed/denied ingress tests complete'
task_failed_units=$(systemctl list-units --state=failed --no-legend --plain)
[[ -z $task_failed_units ]] || { printf 'FAIL | failed units: %s\n' "$task_failed_units"; exit 1; }
task_package_issues=$(dpkg --audit)
[[ -z $task_package_issues ]] || { printf 'FAIL | dpkg audit: %s\n' "$task_package_issues"; exit 1; }
pass 'No failed systemd units or dpkg audit findings'
echo 'All scripted lab assertions passed.'
