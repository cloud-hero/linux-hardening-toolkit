#!/usr/bin/env python3
"""Disposable synthetic application: semantic gate and rollback, not production proof."""
import http.server, json, threading, urllib.request
state={'release':'A'}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        value={'status':'healthy'} if self.path=='/health' else {'result':'ok' if state['release']=='A' else 'incorrect'}
        data=json.dumps(value).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(data)
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{server.server_port}'
def get(path):
    with urllib.request.urlopen(base+path,timeout=3) as response:return response.status,json.load(response)
try:
    assert get('/transaction')==(200,{'result':'ok'});print('PASS | release A representative transaction')
    state['release']='B'
    assert get('/health')[0]==200;print('PASS | faulty release still returns HTTP 200 from health endpoint')
    accepted=get('/transaction')==(200,{'result':'ok'})
    assert not accepted;print('PASS | semantic acceptance gate detects wrong result and holds rollout')
    state['release']='A'
    assert get('/transaction')==(200,{'result':'ok'});print('PASS | rollback to release A restores representative transaction')
finally:server.shutdown();server.server_close()
