#!/usr/bin/env bash
# Disposable VM only: prove role-appropriate checks without widening real users.
set -euo pipefail
[[ $EUID -eq 0 && -d /root/hardening-backup ]] || exit 2
python3 - <<'PY'
import pathlib,pwd,secrets,subprocess
users=['ch-review-human','ch-review-auto'];created=[]
policy=pathlib.Path('/etc/sudoers.d/cloudhero-review-fixture')
assert not policy.exists()
for user in users:
    try:pwd.getpwnam(user)
    except KeyError:pass
    else:raise SystemExit('Refusing to reuse existing identity '+user)
try:
    for user in users:
        subprocess.run(['useradd','--no-create-home','--shell','/bin/sh',user],check=True);created.append(user)
    password=secrets.token_urlsafe(32)
    subprocess.run(['chpasswd'],input=users[0]+':'+password+'\n',text=True,check=True,capture_output=True)
    policy.write_text(users[0]+' ALL=(root) PASSWD: /usr/bin/id -u\n'+users[1]+' ALL=(root) NOPASSWD: /usr/bin/id -u\n');policy.chmod(0o440)
    subprocess.run(['visudo','-cf',str(policy)],check=True,capture_output=True)
    def run(user,args,secret=None):
        return subprocess.run(['runuser','-u',user,'--','sudo','-k']+args,input=secret,text=True,capture_output=True)
    result=run(users[0],['-n','/usr/bin/id','-u'])
    assert result.returncode!=0 and 'password is required' in result.stderr
    result=run(users[0],['-S','-p','','/usr/bin/id','-u'],password+'\n')
    assert result.returncode==0 and result.stdout.strip()=='0'
    print('PASS | password-required role fails noninteractive probe but succeeds with authorized authentication')
    result=run(users[1],['-n','/usr/bin/id','-u'])
    assert result.returncode==0 and result.stdout.strip()=='0'
    assert run(users[1],['-n','/usr/bin/true']).returncode!=0
    print('PASS | restricted automation role executes its approved command; generic true probe is rejected')
finally:
    policy.unlink(missing_ok=True)
    for user in reversed(created):subprocess.run(['userdel',user],check=True,capture_output=True)
print('PASS | temporary policy and identities removed; existing administrator policy untouched')
PY
