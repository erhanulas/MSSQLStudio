#!/usr/bin/env python3
"""Run core/live/Keychain tests with an ephemeral local AI fixture."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import subprocess
import threading

class Mock(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path == '/redirect':
            self.send_response(307)
            self.send_header('Location', '/chat/completions')
            self.end_headers()
            return
        if (self.headers.get('Authorization') != 'Bearer test-only-token'
                or data.get('model') != 'test' or not data.get('messages')):
            self.send_response(400)
            self.end_headers()
            return
        body = json.dumps({'choices': [{'message': {'content': '```sql\nSELECT 1 AS Sample;\n```'}}]}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = ThreadingHTTPServer(('127.0.0.1', 0), Mock)
threading.Thread(target=server.serve_forever, daemon=True).start()
env = dict(os.environ, MSSQL_MOCK_URL=f'http://127.0.0.1:{server.server_port}', MSSQL_KEYCHAIN_TEST='1')
try:
    result = subprocess.run([str(Path(__file__).resolve().parent / 'test.sh')], env=env)
finally:
    server.shutdown()
    server.server_close()
raise SystemExit(result.returncode)
