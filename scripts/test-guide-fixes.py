#!/usr/bin/env python3
"""Regression cases from the line-by-line review; no production target required."""
import json, os, re, stat, subprocess, sys, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='guide-regression-') as temp:
    work=Path(temp)
    scope=json.loads((root/'content/baseline-paths.json').read_text())
    directories={'/etc/ssh/sshd_config.d','/etc/apt','/etc/systemd/journald.conf.d','/etc/audit/rules.d','/etc/ufw','/etc/sudoers.d','/etc/rsyslog.d','/etc/systemd/system'}
    for name in scope:
        p=work/name.lstrip('/');p.parent.mkdir(parents=True,exist_ok=True)
        if name in directories:p.mkdir(exist_ok=True)
        else:p.write_text('approved\n')
    for name in ['/etc/apt/apt.conf.d','/etc/apt/sources.list.d']:(work/name.lstrip('/')).mkdir()
    paths=work/'paths.json';paths.write_text(json.dumps([str(work/p.lstrip('/')) for p in scope]))
    manifest=work/'manifest.json'
    def inventory(action):
        return subprocess.run([sys.executable,str(root/'scripts/baseline.py'),action,'--paths',str(paths),'--manifest',str(manifest)],capture_output=True,text=True)
    assert inventory('create').returncode==0
    for name in ['/etc/apt/apt.conf.d/99-disable-updates','/etc/apt/sources.list.d/unapproved.sources','/etc/systemd/journald.conf.d/99-volatile.conf','/etc/ufw/before.rules','/etc/ufw/after6.rules','/etc/sudoers.d/unapproved','/etc/rsyslog.d/unapproved.conf']:
        p=work/name.lstrip('/');p.write_text('unapproved\n');result=inventory('check')
        assert result.returncode==1 and str(p) in result.stdout,(name,result.stdout,result.stderr)
        p.unlink();assert inventory('check').returncode==0
        print('PASS | added override detected and restoration clean: '+name)
    p=work/'etc/default/ufw';p.write_text('changed\n')
    assert inventory('check').returncode==1;print('PASS | firewall defaults drift detected')
    guide=(root/'content/guide.md').read_text()
    pattern=re.search(r"sudo grep -nE '([^']+)' /boot/grub/grub.cfg",guide).group(1)
    fixture="menuentry 'Ubuntu' {\n linux /boot/new\n}\nsubmenu 'Advanced' {\n  menuentry 'Old kernel' {\n    linux /boot/old\n  }\n}\n"
    result=subprocess.run(['grep','-nE',pattern],input=fixture,capture_output=True,text=True)
    assert result.returncode==0 and all(x in result.stdout for x in ["submenu 'Advanced'","menuentry 'Old kernel'",'linux /boot/old'])
    print('PASS | documented GRUB excerpt preserves submenu, nested title and image')
    if os.geteuid()==0:
        old=work/'assessment.txt';old.write_text('existing report\n');old.chmod(0o644)
        target=work/'existing-target';target.write_text('preserve\n')
        (work/'linux-assessment.fixed').symlink_to(target)
        paths=[]
        for code in (0,1):
            collector=work/'fake-collector.sh';collector.write_text(f'printf "test evidence\\n"\nexit {code}\n')
            result=subprocess.run(['bash',str(root/'scripts/collect-report.sh'),str(collector)],cwd=work,capture_output=True,text=True)
            assert result.returncode==code
            report=Path(re.search(r'^Report: (.+)$',result.stdout,re.M).group(1));paths.append(report)
            assert stat.S_IMODE(report.stat().st_mode)==0o600
            assert stat.S_IMODE(report.parent.stat().st_mode)==0o700
            assert report.read_text()=='test evidence\n'
        assert paths[0]!=paths[1] and old.read_text()=='existing report\n' and target.read_text()=='preserve\n'
        print('PASS | fresh private reports, failure evidence/exit preserved, existing file and symlink untouched')
    else: print('SKIP | root capture-wrapper integration: run in the disposable VM')
tests=r'''
source "$1/scripts/assess.sh"
# Classification fixture: execute real short commands without requiring GNU timeout on macOS.
timeout() { shift; "$@"; }
case_check() {
  local kind=$1 code=$2 output=$3 expected=$4
  errors=0
  run_checked "$kind" fixture bash -c 'printf "%s\n" "$1"; exit "$2"' bash "$output" "$code" >/dev/null
  [[ $errors == "$expected" ]] || { echo "FAIL $kind $code $output"; exit 1; }
}
case_check virtualization 1 none 0
case_check virtualization 1 'permission denied' 1
case_check virtualization 124 '' 1
case_check virtualization 0 kvm 0
case_check enablement 1 $'disabled\nmasked' 0
case_check enablement 4 'not-found' 1
case_check inventory 1 'DRIFT: 1 entries' 0
case_check inventory 2 'ERROR: invalid manifest' 1
errors=0
run_checked normal fixture definitely_missing_cloudhero_tool >/dev/null
[[ $errors == 1 ]]
'''
subprocess.run(['bash','-c',tests,'bash',str(root)],check=True)
print('PASS | collector distinguishes bare-metal observation, policy findings, permission/tool errors and timeout')
stdin_source='uname() { printf "Darwin\\n"; }\n'+(root/'scripts/assess.sh').read_text()
result=subprocess.run(['bash'],input=stdin_source,capture_output=True,text=True)
assert result.returncode==2 and 'requires Linux' in result.stderr and 'unbound variable' not in result.stderr
print('PASS | stdin entry reaches platform guard; importing helpers does not execute collection')
