#!/usr/bin/env bash
# Disposable Ubuntu lab ONLY. Never run this fixture on production.
set -euo pipefail
[[ $EUID -eq 0 && -f /run/cloudhero-disposable-lab ]] || { echo 'Requires the explicit disposable-lab marker'; exit 2; }
install -d -m 0700 /root/hardening-backup
cp -a /etc/ssh /root/hardening-backup/ssh
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-cloudhero.conf <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
LogLevel VERBOSE
EOF
/usr/sbin/sshd -t
systemctl reload ssh
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/52cloudhero-reboot <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
install -d /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/60-cloudhero.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=256M
SystemKeepFree=512M
EOF
systemctl restart systemd-journald
journalctl --flush
cat > /etc/audit/rules.d/50-cloudhero.rules <<'EOF'
-a always,exit -F arch=b64 -F path=/etc/ssh/sshd_config -F perm=wa -k ssh_config
-a always,exit -F arch=b64 -F dir=/etc/ssh/sshd_config.d -F perm=wa -k ssh_config
-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -k privilege_config
-a always,exit -F arch=b64 -F dir=/etc/sudoers.d -F perm=wa -k privilege_config
EOF
systemctl enable --now auditd
augenrules --load
# Lima's usernet gateway, plus two explicitly designated synthetic admin clients.
ufw allow from 192.168.5.2 to any port 22 proto tcp
ufw allow from 198.18.0.2 to any port 22 proto tcp
ufw allow from fd42:face::2 to any port 22 proto tcp
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
install -d -m 0700 /var/lib/cloudhero-baseline
sha256sum /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-cloudhero.conf \
 /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/52cloudhero-reboot \
 /etc/systemd/journald.conf.d/60-cloudhero.conf /etc/audit/rules.d/50-cloudhero.rules \
 /etc/ufw/user.rules /etc/ufw/user6.rules > /var/lib/cloudhero-baseline/config.sha256
logger -t hardening-lab 'cloudhero-reboot-persistence-marker'
echo 'Lab baseline applied.'
