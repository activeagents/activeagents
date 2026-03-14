#!/usr/bin/env python3
"""
Minimal HTTP server for sandbox health checks and basic operations.

Endpoints:
  GET  /up          - Health check (returns 200)
  GET  /status      - Sandbox status and metrics
  POST /exec        - Execute a command (JSON body: {"command": "..."})
  GET  /env         - Environment variables (filtered)
"""

import http.server
import json
import os
import subprocess
import sys
import time
from urllib.parse import parse_qs, urlparse

START_TIME = time.time()


class SandboxHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/up":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")

        elif path == "/status":
            self.send_json({
                "status": "running",
                "uptime_seconds": int(time.time() - START_TIME),
                "session_id": os.environ.get("SANDBOX_SESSION_ID", "unknown"),
                "sandbox_type": os.environ.get("SANDBOX_TYPE", "base"),
                "pid": os.getpid(),
            })

        elif path == "/env":
            # Return filtered environment (no secrets)
            safe_env = {
                k: v for k, v in os.environ.items()
                if not any(secret in k.lower() for secret in ["key", "token", "secret", "password"])
            }
            self.send_json(safe_env)

        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/exec":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)

            try:
                data = json.loads(body)
                command = data.get("command", "")
                timeout = data.get("timeout", 30)

                if not command:
                    self.send_json({"error": "No command provided"}, status=400)
                    return

                # Execute command
                result = subprocess.run(
                    command,
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                    cwd="/workspace"
                )

                self.send_json({
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "exit_code": result.returncode
                })

            except json.JSONDecodeError:
                self.send_json({"error": "Invalid JSON"}, status=400)
            except subprocess.TimeoutExpired:
                self.send_json({"error": "Command timed out"}, status=408)
            except Exception as e:
                self.send_json({"error": str(e)}, status=500)

        else:
            self.send_error(404, "Not Found")

    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        # Quieter logging
        if "/up" not in args[0]:
            sys.stderr.write(f"[sandbox] {args[0]}\n")


def main():
    port = int(os.environ.get("PORT", 8080))
    server = http.server.HTTPServer(("0.0.0.0", port), SandboxHandler)

    print(f"[sandbox] Server starting on port {port}")
    print(f"[sandbox] Session ID: {os.environ.get('SANDBOX_SESSION_ID', 'unknown')}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[sandbox] Shutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
