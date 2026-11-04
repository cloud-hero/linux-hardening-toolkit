#!/usr/bin/env bash
# Operator-run capture wrapper. Creates a fresh private directory on the target.
# Review this file and the collector before running; run from a private work area.
set -uo pipefail
umask 077
collector=${1:-./assess.sh}
if [[ $# -gt 1 || ! -f $collector || ! -r $collector ]]; then
  echo 'Usage: bash collect-report.sh /reviewed/path/assess.sh' >&2; exit 2
fi
report_dir=$(mktemp -d "$PWD/linux-assessment.XXXXXXXX") || exit 2
report="$report_dir/assessment.txt"
if [[ $EUID -eq 0 ]]; then
  bash -- "$collector" > "$report" 2>&1
else
  sudo -- bash -- "$collector" > "$report" 2>&1
fi
rc=$?
printf 'Report: %s\nCollector exit: %s\n' "$report" "$rc"
echo 'Keep the original private; review and redact a separate copy before sharing.'
exit "$rc"
