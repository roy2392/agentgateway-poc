#!/usr/bin/env python3
"""
Enterprise AI Chat UI Server
Serves the chat interface and proxies requests to AgentGateway demo endpoint
"""

import os
import json
import urllib.request
import urllib.error
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse

# Configuration
DEMO_ENDPOINT = os.environ.get('DEMO_ENDPOINT', 'http://demo-orchestrator.ai-agents.svc.cluster.local')
PORT = int(os.environ.get('PORT', '8080'))

class ChatHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Serve files from the current directory
        super().__init__(*args, directory=os.path.dirname(os.path.abspath(__file__)), **kwargs)

    def log_message(self, format, *args):
        print(f"[ChatUI] {args[0]}")

    def send_json(self, data, status=200):
        response = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(response))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(response)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == '/api/health':
            self.send_json({'status': 'healthy', 'service': 'chat-ui'})
        elif parsed.path == '/api/agents':
            # Proxy to demo endpoint
            try:
                req = urllib.request.Request(f"{DEMO_ENDPOINT}/agents")
                with urllib.request.urlopen(req, timeout=30) as resp:
                    data = json.loads(resp.read().decode())
                    self.send_json(data)
            except Exception as e:
                self.send_json({'error': str(e)}, 500)
        elif parsed.path == '/' or parsed.path == '/index.html':
            self.path = '/index.html'
            super().do_GET()
        else:
            super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == '/api/ask':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')

            try:
                request_data = json.loads(body) if body else {}
                message = request_data.get('message', '')

                if not message:
                    self.send_json({'error': 'Message is required'}, 400)
                    return

                # Forward to demo orchestrator
                data = json.dumps({'message': message}).encode('utf-8')
                req = urllib.request.Request(
                    f"{DEMO_ENDPOINT}/ask",
                    data=data,
                    headers={'Content-Type': 'application/json'}
                )

                with urllib.request.urlopen(req, timeout=120) as resp:
                    result = json.loads(resp.read().decode())
                    self.send_json(result)

            except urllib.error.URLError as e:
                self.send_json({'error': f'Backend connection failed: {str(e)}'}, 502)
            except json.JSONDecodeError:
                self.send_json({'error': 'Invalid JSON'}, 400)
            except Exception as e:
                self.send_json({'error': str(e)}, 500)
        else:
            self.send_json({'error': 'Not found'}, 404)


def main():
    print(f"=" * 50)
    print(f"  Enterprise AI Chat UI")
    print(f"  Port: {PORT}")
    print(f"  Demo Endpoint: {DEMO_ENDPOINT}")
    print(f"=" * 50)

    server = HTTPServer(('', PORT), ChatHandler)
    print(f"\nServer running at http://0.0.0.0:{PORT}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
