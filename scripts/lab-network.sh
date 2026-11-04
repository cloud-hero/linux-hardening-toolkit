#!/usr/bin/env bash
# Additional disposable-VM test: public application allowance, blocked listener, rollback.
set -euo pipefail
[[ $EUID -eq 0 && -d /root/hardening-backup ]] || exit 2
cp -p /etc/ufw/user.rules /run/ch-user.rules
cp -p /etc/ufw/user6.rules /run/ch-user6.rules
server_pid=''
cleanup() {
  [[ -z $server_pid ]] || kill "$server_pid" 2>/dev/null || :
  ip netns del ch-app-client 2>/dev/null || :
  ip link del ch-app-host 2>/dev/null || :
  cp -p /run/ch-user.rules /etc/ufw/user.rules
  cp -p /run/ch-user6.rules /etc/ufw/user6.rules
  ufw reload
}
trap cleanup EXIT
ufw allow 443/tcp
python3 - <<'PY' &
import socket,threading
def listen(port):
    s=socket.socket(socket.AF_INET6,socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    s.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,0)
    s.bind(('::',port));s.listen()
    while True:
        c,_=s.accept();c.close()
t=threading.Thread(target=listen,args=(443,),daemon=True);t.start()
listen(8080)
PY
server_pid=$!
ip netns add ch-app-client
ip link add ch-app-host type veth peer name ch-app-peer
ip link set ch-app-peer netns ch-app-client
ip addr add 198.19.0.1/24 dev ch-app-host
ip -6 addr add fd43:face::1/64 dev ch-app-host nodad
ip link set ch-app-host up
ip netns exec ch-app-client ip link set lo up
ip netns exec ch-app-client ip addr add 198.19.0.2/24 dev ch-app-peer
ip netns exec ch-app-client ip -6 addr add fd43:face::2/64 dev ch-app-peer nodad
ip netns exec ch-app-client ip link set ch-app-peer up
ss -lnt | grep -E ':443 |:8080 '
ip netns exec ch-app-client python3 - <<'PY'
import socket
for dst in ['198.19.0.1','fd43:face::1']:
    for port,expected in [(443,True),(8080,False)]:
        s=socket.socket(socket.AF_INET6 if ':' in dst else socket.AF_INET,socket.SOCK_STREAM);s.settimeout(2)
        try:s.connect((dst,port));connected=True
        except socket.timeout:connected=False
        except OSError as e:raise AssertionError(f'Ambiguous failure: {e}')
        finally:s.close()
        assert connected==expected,(dst,port,connected)
        print(f'PASS | Application ingress {dst}:{port}: '+('allowed' if connected else 'filtered despite active listener'),flush=True)
PY
cleanup
trap - EXIT
sha256sum --check /var/lib/cloudhero-baseline/config.sha256
echo 'PASS | Firewall fixture rollback restored exact approved files'
