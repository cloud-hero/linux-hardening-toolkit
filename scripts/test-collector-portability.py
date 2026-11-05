#!/usr/bin/env python3
"""Classification regressions for the cross-distribution evidence collector."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
script=r'''
source "$1/scripts/assess.sh"
timeout() { shift; "$@"; }
check() {
  local rc=$1 message=$2 want_errors=$3 want_manual=$4
  errors=0; manuals=0
  run_checked cached_updates fixture bash -c 'printf "%s\n" "$1"; exit "$2"' bash "$message" "$rc" >/dev/null
  [[ $errors == "$want_errors" && $manuals == "$want_manual" ]]
}
check 100 'updates exist' 0 0
check 0 'no cached updates' 0 0
check 1 'Cache-only enabled but no cache for repo example' 0 1
check 1 'no available cached metadata' 0 1
check 1 'permission denied' 1 0
check 124 'cacheonly timeout' 1 0
errors=0;manuals=0
optional 'missing optional tool' cloudhero_nonexistent_command >/dev/null
[[ $errors == 0 && $manuals == 1 ]]
'''
subprocess.run(['bash','-c',script,'bash',str(root)],check=True)
print('PASS | DNF exit 100, missing cache, real failures, timeouts and optional tools retain distinct meanings.')
