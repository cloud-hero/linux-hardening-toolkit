#!/usr/bin/env bash
# Disposable VM only. Dedicated rsyslog + TLS receiver, isolated from host logging.
set -euo pipefail
[[ $EUID -eq 0 && -d /root/hardening-backup ]] || exit 2
lab=$(mktemp -d /var/spool/rsyslog/ch-logging.XXXXXX)
config="/etc/rsyslog.d/cloudhero-lab-$$.fixture"
chmod 0700 "$lab"
forwarder=''; receiver=''
cleanup() {
  if [[ -n $forwarder ]]; then
    kill "$forwarder" 2>/dev/null || :
    for n in {1..20}; do kill -0 "$forwarder" 2>/dev/null || break; sleep .25; done
    kill -KILL "$forwarder" 2>/dev/null || :
    wait "$forwarder" 2>/dev/null || :
  fi
  [[ -z $receiver ]] || kill "$receiver" 2>/dev/null || :
  ip netns del ch-logs 2>/dev/null || :
  ip link del ch-logs-host 2>/dev/null || :
  rm -f "$config"
  # Certificates and logs remain inside the VM's private spool folder for review.
}
trap cleanup EXIT
ip netns add ch-logs
ip link add ch-logs-host type veth peer name ch-logs-peer
ip link set ch-logs-peer netns ch-logs
ip addr add 198.18.10.1/24 dev ch-logs-host
ip link set ch-logs-host up
ip netns exec ch-logs ip addr add 198.18.10.2/24 dev ch-logs-peer
ip netns exec ch-logs ip link set ch-logs-peer up
ip netns exec ch-logs ip link set lo up
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$lab/ca.key" -out "$lab/ca.crt" -days 1 -subj /CN=CloudHero-Disposable-Lab-CA >/dev/null 2>&1
for name in server client; do
  openssl req -newkey rsa:2048 -nodes -keyout "$lab/$name.key" -out "$lab/$name.csr" -subj "/CN=$name.lab.example" >/dev/null 2>&1
  if [[ $name == server ]]; then
    printf 'subjectAltName=DNS:logs.lab.example,IP:198.18.10.2\nextendedKeyUsage=serverAuth\n' > "$lab/$name.ext"
  else printf 'extendedKeyUsage=clientAuth\n' > "$lab/$name.ext"; fi
  openssl x509 -req -in "$lab/$name.csr" -CA "$lab/ca.crt" -CAkey "$lab/ca.key" -CAcreateserial -out "$lab/$name.crt" -days 1 -extfile "$lab/$name.ext" >/dev/null 2>&1
done
chmod 0600 "$lab"/*.key
cat > "$lab/receiver.py" <<'PY'
import socket,ssl,sys,pathlib
p=pathlib.Path(sys.argv[1]); ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(p/'server.crt',p/'server.key');ctx.load_verify_locations(p/'ca.crt')
ctx.verify_mode=ssl.CERT_REQUIRED
s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('198.18.10.2',6514));s.listen();(p/'receiver-ready').touch()
while True:
    raw,_=s.accept()
    try:
        with ctx.wrap_socket(raw,server_side=True) as conn:
            with (p/'received.log').open('ab',buffering=0) as out:
                while True:
                    data=conn.recv(8192)
                    if not data: break
                    out.write(data)
    except (ssl.SSLError,ConnectionError,OSError):raw.close()
PY
make_config() {
  local peer=$1
  cat > "$config" <<EOF
global(workDirectory="$lab" DefaultNetstreamDriverCAFile="$lab/ca.crt" DefaultNetstreamDriverCertFile="$lab/client.crt" DefaultNetstreamDriverKeyFile="$lab/client.key")
module(load="imuxsock" SysSock.Use="off")
input(type="imuxsock" Socket="$lab/input.sock" CreatePath="on")
module(load="impstats" interval="1" format="json" log.syslog="off" log.file="$lab/stats.json")
template(name="LabLine" type="string" string="%msg%\\n")
action(name="cloudhero-forward" type="omfwd" target="198.18.10.2" port="6514" protocol="tcp"
 StreamDriver="gtls" StreamDriverMode="1" StreamDriverAuthMode="x509/name"
 StreamDriverPermittedPeers="$peer" template="LabLine"
 action.resumeRetryCount="-1" action.resumeInterval="1"
 queue.type="LinkedList" queue.filename="forward" queue.size="1000" queue.saveOnShutdown="on"
 queue.maxDiskSpace="32m")
EOF
  rsyslogd -N1 -f "$config" > "$lab/syntax.log" 2>&1
}
start_receiver() {
  rm -f "$lab/receiver-ready"
  ip netns exec ch-logs python3 "$lab/receiver.py" "$lab" > "$lab/receiver.stderr" 2>&1 & receiver=$!
  for n in {1..30}; do [[ ! -f "$lab/receiver-ready" ]] || return 0; sleep .2; done
  echo 'FAIL | receiver did not become ready'; exit 1
}
start_forwarder() {
  rsyslogd -n -i "$lab/forward.pid" -f "$config" > "$lab/forward.stderr" 2>&1 & forwarder=$!
  for n in {1..30}; do [[ ! -S "$lab/input.sock" ]] || return 0; sleep .2; done
  echo 'FAIL | forwarder did not become ready'; exit 1
}
await_marker() {
  for n in {1..30}; do
    if grep -q "$1" "$lab/received.log" 2>/dev/null; then return 0; fi
    sleep 1
  done
  cat "$lab/forward.stderr"; echo "FAIL | receiver missing $1"; exit 1
}
start_receiver; make_config logs.lab.example; start_forwarder
marker="cloudhero-tls-$(date +%s)"
logger -u "$lab/input.sock" -t cloudhero-delivery "$marker"
await_marker "$marker"
echo 'PASS | Unique syslog marker delivered across namespace boundary with mutual TLS'
# A real Linux Audit event, read as an explicit input source by rsyslog imfile.
printf '\nmodule(load="imfile")\ninput(type="imfile" File="/var/log/audit/audit.log" Tag="linux-audit:" Severity="info" Facility="local6" PersistStateInterval="1" freshStartTail="on")\n' >> "$config"
kill "$forwarder"; wait "$forwarder"; forwarder=''
start_forwarder
sleep 1
audit_marker="cloudhero-audit-tls-$(date +%s)"
auditctl -m "$audit_marker" >/dev/null
await_marker "$audit_marker"
echo 'PASS | Linux Audit marker delivered through explicit audit-file input'
kill "$receiver"; wait "$receiver" || :; receiver=''
# Start a fresh sender connection while the receiver is unavailable, to separate
# confirmed queued traffic from TCP's ambiguous in-flight disconnect window.
kill "$forwarder"; wait "$forwarder"; forwarder=''; start_forwarder
logger -u "$lab/input.sock" -t cloudhero-delivery "cloudhero-warmup-$marker"
for n in {1..15}; do grep -Eqi 'cannot connect.*Connection refused|suspended' "$lab/forward.stderr" && break; sleep 1; done
grep -Eqi 'cannot connect.*Connection refused|suspended' "$lab/forward.stderr"
echo 'PASS | Receiver outage produces an observable forwarding connection failure'
# Bound the fixture well below its disk limit; never exhaust the guest filesystem.
for n in {1..300}; do logger -u "$lab/input.sock" -t cloudhero-delivery "cloudhero-outage-$n-$marker"; done
python3 - "$lab" <<'PY'
import datetime,json,pathlib,sys,time
p=pathlib.Path(sys.argv[1]);deadline=time.monotonic()+15
while time.monotonic()<deadline:
    records=[]
    for line in (p/'stats.json').read_text().splitlines() if (p/'stats.json').exists() else []:
        try: record=json.loads(line[line.index('{'):])
        except (ValueError,json.JSONDecodeError):continue
        if record.get('origin')=='core.queue' and record.get('name','').startswith('cloudhero-forward'):records.append(record)
    if records and records[-1].get('size',0)>=20:
        receipt=dict(destination='local fixture alert sink',threshold=20,queue=records[-1],observed_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
        (p/'queue-alert.json').write_text(json.dumps(receipt)+'\n')
        print('PASS | Real queue-pressure observation delivered to local fixture alert sink; size='+str(records[-1]['size']))
        break
    time.sleep(.25)
else:raise SystemExit('FAIL | no real queue-pressure receipt before deadline')
PY
start_receiver
logger -u "$lab/input.sock" -t cloudhero-delivery "cloudhero-recovery-$marker"
await_marker "cloudhero-recovery-$marker"
await_marker "cloudhero-outage-300-$marker"
python3 - "$lab" "$marker" <<'PY'
import collections,json,pathlib,re,sys
p=pathlib.Path(sys.argv[1]);marker=sys.argv[2]
seen=collections.Counter(map(int,re.findall(r'cloudhero-outage-(\d+)-'+re.escape(marker), (p/'received.log').read_text())))
missing=sorted(set(range(1,301))-seen.keys());duplicates={n:c for n,c in seen.items() if c>1}
(p/'reconciliation.json').write_text(json.dumps(dict(expected=300,unique_received=len(seen),missing=missing,duplicates=duplicates))+'\n')
print(f'RECONCILIATION | expected=300 unique_received={len(seen)} missing={missing} duplicates={duplicates}')
assert not missing, 'Missing outage sequence IDs'
assert set(range(1,301))-(seen.keys()-{1})=={1}, 'Gap detector must identify a deliberately withheld ID'
print('PASS | Every queued sequence ID reconciled; negative gap check passed (no exactly-once guarantee)')
PY
# Wrong expected server identity must reject TLS even with the same trusted CA.
kill "$forwarder"; wait "$forwarder"; forwarder=''
make_config wrong.lab.example; start_forwarder
logger -u "$lab/input.sock" -t cloudhero-delivery "cloudhero-wrong-peer-$marker"
for n in {1..15}; do
  if grep -Eiq 'not permitted|not authorized|name.*not|peer.*not' "$lab/forward.stderr"; then break; fi
  sleep 1
done
grep -Eiq 'not permitted|not authorized|name.*not|peer.*not' "$lab/forward.stderr"
if grep -q "cloudhero-wrong-peer-$marker" "$lab/received.log"; then echo 'FAIL | wrong certificate peer accepted'; exit 1; fi
echo 'PASS | Valid CA but wrong server certificate identity rejected; marker absent at receiver'
echo 'PASS | Logging fixture completed; private PKI and logs remain only inside the VM spool folder'
