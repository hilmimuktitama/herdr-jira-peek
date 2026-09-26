#!/usr/bin/env python3
"""Run the actual worker over a private Unix socket and verify lease cleanup."""
import json
import os
from pathlib import Path
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
ROOT=Path(__file__).resolve().parents[1]

class IntegrationTest(unittest.TestCase):
    def test_status_watcher_retries_initial_sync_after_failed_post(self):
        with tempfile.TemporaryDirectory(prefix='peek-status-', dir='/tmp') as temp:
            base = Path(temp)
            attempts = []
            class Handler(socketserver.StreamRequestHandler):
                def handle(self):
                    self.rfile.readline()
                    length = 0
                    while True:
                        line = self.rfile.readline()
                        if line in (b'\r\n', b'\n', b''):
                            break
                        if line.lower().startswith(b'content-length:'):
                            length = int(line.split(b':', 1)[1])
                    attempts.append(self.rfile.read(length))
                    status = b'503 Unavailable' if len(attempts) == 1 else b'200 OK'
                    self.wfile.write(b'HTTP/1.1 ' + status + b'\r\nContent-Length: 0\r\n\r\n')
            server = socketserver.UnixStreamServer(str(base/'fzf.sock'), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            (base/'highlight-status').write_text('Source: highlight unavailable\n')
            env = dict(os.environ, VIEWER_STATE_DIR=temp,
                       VIEWER_FZF_SOCKET=str(base/'fzf.sock'),
                       VIEWER_CONNECTION_ID='', CURL_BIN_PATH='curl',
                       VIEWER_SOURCE_HIGHLIGHT_ENABLED='1')
            child = subprocess.Popen(['sh', str(ROOT/'scripts/viewer-ui.sh'), 'watch-messages'],
                                     env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while len(attempts) < 2 and time.monotonic() < deadline:
                    time.sleep(.05)
                self.assertGreaterEqual(len(attempts), 2, 'failed startup post must be retried')
                self.assertTrue(all(b'refresh-source-status' in body for body in attempts))
                time.sleep(.6)
                self.assertEqual(len(attempts), 2, 'successful status must not be posted repeatedly')
            finally:
                child.terminate()
                child.communicate(timeout=3)
                server.shutdown()
                server.server_close()
                thread.join()

    def test_worker_renews_changes_and_clears_without_source_input(self):
        with tempfile.TemporaryDirectory(prefix='peek-native-',dir='/tmp') as temp:
            base=Path(temp);events=[]
            class Handler(socketserver.StreamRequestHandler):
                def handle(self):
                    req=json.loads(self.rfile.readline());method=req['method'];params=req['params']
                    events.append((method,params))
                    if method=='pane.get': result={'pane':{'pane_id':'fixture-pane','terminal_id':'fixture-terminal'}}
                    elif method in {'pane.highlight.set','pane.highlight.clear'}:result={'type':'ok'}
                    else:result={'type':'unexpected'}
                    self.wfile.write((json.dumps({'id':req['id'],'result':result})+'\n').encode())
            server=socketserver.UnixStreamServer(str(base/'api.sock'),Handler)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            (base/'candidates').write_text('DEMO-42\nDEMO-43\n');(base/'highlight-request').write_text('DEMO-42\n')
            env=dict(os.environ,VIEWER_STATE_DIR=temp,HERDR_SOCKET_PATH=str(base/'api.sock'),HERDR_VIEWER_SOURCE_PANE='fixture-pane',HERDR_VIEWER_SOURCE_TERMINAL='fixture-terminal')
            child=subprocess.Popen([sys.executable,str(ROOT/'scripts/viewer-highlight.py')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            def wait(predicate):
                deadline=time.monotonic()+5
                while time.monotonic()<deadline:
                    if predicate():return
                    time.sleep(.05)
                self.fail('native worker lifecycle event did not arrive')
            try:
                wait(lambda:sum(m=='pane.highlight.set' for m,_ in events)>=2)
                (base/'highlight-request').write_text('DEMO-43\n')
                wait(lambda:any(m=='pane.highlight.set' and p['query']=='DEMO-43' for m,p in events))
                child.terminate();out,err=child.communicate(timeout=3)
                self.assertEqual((out,err),(b'',b''))
                self.assertEqual(events[-1][0],'pane.highlight.clear')
                self.assertEqual({m for m,_ in events},{'pane.get','pane.highlight.set','pane.highlight.clear'})
                self.assertEqual(len({p['owner'] for m,p in events if m.startswith('pane.highlight.')}),1)
            finally:
                if child.poll() is None:child.kill();child.wait()
                server.shutdown();server.server_close();thread.join()

if __name__=='__main__':unittest.main(verbosity=2)
