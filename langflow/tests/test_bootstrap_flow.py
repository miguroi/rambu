import importlib.util
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = ROOT / "langflow" / "scripts" / "bootstrap_flow.py"
FLOW_PATH = ROOT / "langflow" / "flows" / "Rambu.json"


def load_bootstrap_module():
    spec = importlib.util.spec_from_file_location("rambu_bootstrap_flow", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LangflowHandler(BaseHTTPRequestHandler):
    requests: list[dict[str, object]] = []

    def do_POST(self) -> None:
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)
        self.requests.append({"path": self.path, "headers": self.headers, "body": body})
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps([flow_summary()]).encode())

    def do_GET(self) -> None:
        self.requests.append({"path": self.path, "headers": self.headers, "body": b""})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps([flow_summary()]).encode())

    def log_message(self, format: str, *args: object) -> None:
        pass


def flow_summary() -> dict[str, str]:
    return {
        "id": "c1cb7b3c-2589-4754-ac61-8cf88df4a07e",
        "name": "Rambu",
        "endpoint_name": "rambu",
    }


def test_prepared_flow_injects_openrouter_key_without_writing_it_to_disk() -> None:
    module = load_bootstrap_module()
    original = FLOW_PATH.read_text()

    prepared = module.prepare_flow(FLOW_PATH, "sk-or-test-secret", "rambu")
    flow = json.loads(prepared)
    model = next(node for node in flow["data"]["nodes"] if node["id"].startswith("LanguageModelComponent-"))

    assert model["data"]["node"]["template"]["api_key"]["value"] == "sk-or-test-secret"
    assert FLOW_PATH.read_text() == original
    assert "sk-or-test-secret" not in original


def test_bootstrap_uploads_then_verifies_the_rambu_endpoint() -> None:
    module = load_bootstrap_module()
    LangflowHandler.requests = []
    server = ThreadingHTTPServer(("127.0.0.1", 0), LangflowHandler)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        result = module.bootstrap_flow(
            base_url=f"http://127.0.0.1:{server.server_port}",
            langflow_api_key="sk-langflow-test",
            openrouter_api_key="sk-or-test-secret",
            expected_endpoint="rambu",
            flow_path=FLOW_PATH,
        )
    finally:
        server.shutdown()
        thread.join()
        server.server_close()

    assert result == flow_summary()
    assert [request["path"] for request in LangflowHandler.requests] == [
        "/api/v1/flows/upload/",
        "/api/v1/flows/?get_all=true",
    ]
    assert all(
        request["headers"]["x-api-key"] == "sk-langflow-test"
        for request in LangflowHandler.requests
    )
    assert b"sk-or-test-secret" in LangflowHandler.requests[0]["body"]


def test_settings_fail_before_upload_when_openrouter_key_is_missing(tmp_path: Path) -> None:
    module = load_bootstrap_module()
    env_file = tmp_path / ".env"
    env_file.write_text(
        "LANGFLOW_URL=http://127.0.0.1:7861\n"
        "LANGFLOW_FLOW_ID=rambu\n"
        "LANGFLOW_API_KEY=sk-langflow-test\n"
    )

    with pytest.raises(module.BootstrapError, match="OPENROUTER_API_KEY is required"):
        module.load_settings(env_file)
