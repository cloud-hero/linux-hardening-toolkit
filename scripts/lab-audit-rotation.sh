#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 && -d /root/hardening-backup ]] || exit 2
marker="cloudhero-rotation-$(date +%s)"
before=$(stat -c %i /var/log/audit/audit.log)
auditctl -m "$marker-before" >/dev/null
for n in {1..10}; do grep -q "$marker-before" /var/log/audit/audit.log && break; sleep 1; done
grep -q "$marker-before" /var/log/audit/audit.log
service auditd rotate
for n in {1..10}; do [[ $(stat -c %i /var/log/audit/audit.log) == "$before" ]] || break; sleep 1; done
[[ $(stat -c %i /var/log/audit/audit.log) != "$before" ]]
grep -q "$marker-before" /var/log/audit/audit.log.1
auditctl -m "$marker-after" >/dev/null
for n in {1..10}; do grep -q "$marker-after" /var/log/audit/audit.log && break; sleep 1; done
grep -q "$marker-after" /var/log/audit/audit.log
[[ $(auditctl -s | awk '$1=="lost" {print $2}') == 0 ]]
echo 'PASS | audit rotation created a new active file and retained earlier event'
echo 'PASS | post-rotation event written; kernel audit lost counter remains zero'
echo 'MANUAL | disk-exhaustion behavior and production notification delivery are not proven by rotation'
