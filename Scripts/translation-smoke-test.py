#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


BINARY = Path(__file__).resolve().parents[1] / ".build/release/zoomcc-translate-genai"
TRANSLATION = "\ud30c\ud2b8\ub108\ub294 \ud06c\ub808\ub527\uc744 \uc0ac\uc6a9\ud560 \uc218 \uc788\uc2b5\ub2c8\ub2e4."
requests = []


def completed(text=TRANSLATION, status="completed"):
    return {
        "status": status,
        "output": [{"type": "message", "content": [{"type": "output_text", "text": text}]}],
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        requests.append((self.path, body, self.headers.get("Authorization")))
        mode = self.path.split("/")[1]
        if mode == "http-error":
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"message":"invalid test key"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json" if mode.startswith("json") or mode.startswith("chat") else "text/event-stream")
        self.end_headers()
        if mode.startswith("json"):
            result = completed(status="incomplete" if mode == "json-incomplete" else "completed")
            self.wfile.write(json.dumps(result).encode())
            return
        if mode.startswith("chat"):
            result = {"choices": [{"message": {"content": TRANSLATION}, "finish_reason": "length" if mode == "chat-incomplete" else "stop"}]}
            self.wfile.write(json.dumps(result).encode())
            return

        def event(value):
            payload = json.dumps(value, ensure_ascii=False).encode()
            self.wfile.write(b": heartbeat\r\nevent: message\r\ndata: " + payload + b"\r\n\r\n")
            self.wfile.flush()

        event({"type": "response.created", "response": {"status": "in_progress"}})
        event({"type": "response.reasoning_summary_text.delta", "delta": "DO NOT DISPLAY REASONING"})
        for delta in [TRANSLATION[:5], TRANSLATION[5:]]:
            event({"type": "response.output_text.delta", "delta": delta})
        if mode == "truncated":
            return
        if mode == "failed":
            event({"type": "response.failed", "response": {"status": "failed"}})
            return
        if mode == "incomplete":
            event({"type": "response.incomplete", "response": completed(status="incomplete")})
            return
        event({"type": "response.completed", "response": completed()})
        self.wfile.write(b"data: [DONE]\n\n")


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    cases = [(mode, None) for mode in ["stream", "json", "chat", "http-error", "truncated", "failed", "incomplete", "json-incomplete", "chat-incomplete"]]
    cases += [("stream", "xai.grok-4.6"), ("chat", "xai.grok-4.6")]
    for mode, model in cases:
        environment = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("OCI_", "GENAI_", "GPT_MODEL"))
        }
        environment.update({
            "OCI_GENAI_API_KEY": "test-key",
            "OCI_GENAI_API_URL": f"http://127.0.0.1:{server.server_port}/{mode}/responses",
            "OCI_GENAI_API_MODE": "chat" if mode.startswith("chat") else "responses",
        })
        if model:
            environment["GPT_MODEL"] = model
        result = subprocess.run(
            [str(BINARY), "--provider", "oci", "--translate-text", "Partners can use credits.", "--debug"],
            env=environment, capture_output=True, text=True, timeout=10,
        )
        success = mode in ("stream", "json", "chat")
        assert (result.returncode == 0) == success, (mode, result.stderr)
        assert result.stdout.strip() == (TRANSLATION if success else ""), (mode, result.stdout)
        assert "DO NOT DISPLAY REASONING" not in result.stdout
        if mode == "stream":
            assert "api_first_text=" in result.stderr
        if success:
            assert "api_total=" in result.stderr
        if mode == "http-error":
            assert "HTTP 401" in result.stderr

        _, body, authorization = requests[-1]
        assert authorization == "Bearer test-key"
        assert body["model"] == (model or "xai.grok-4.20-non-reasoning")
        if mode.startswith("chat"):
            if model == "xai.grok-4.6":
                assert body["reasoning_effort"] == "low"
            else:
                assert "reasoning_effort" not in body
            data = json.loads(body["messages"][-1]["content"])
        else:
            assert body["stream"] is True
            if model == "xai.grok-4.6":
                assert body["reasoning"] == {"effort": "low"}
            else:
                assert "reasoning" not in body
            data = json.loads(body["input"])
        assert data == {"caption": "Partners can use credits.", "context": [], "is_complete": True}
    print(f"translation transport tests passed ({len(cases)} cases)")
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)
