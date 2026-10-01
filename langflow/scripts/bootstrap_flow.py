from __future__ import annotations

import argparse
import gzip
import json
import secrets
import sys
from pathlib import Path
from typing import Any, NamedTuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENV_FILE = ROOT / "backend" / ".env"
DEFAULT_FLOW_FILE = ROOT / "langflow" / "flows" / "Rambu.json"


class BootstrapError(RuntimeError):
    pass


class Settings(NamedTuple):
    langflow_url: str
    flow_id: str
    langflow_api_key: str
    openrouter_api_key: str


def load_settings(path: Path) -> Settings:
    if not path.is_file():
        raise BootstrapError(f"Environment file not found: {path}")

    values: dict[str, str] = {}
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        values[name.strip()] = value.strip().strip("\"'")

    required = (
        "LANGFLOW_URL",
        "LANGFLOW_FLOW_ID",
        "LANGFLOW_API_KEY",
        "OPENROUTER_API_KEY",
    )
    for name in required:
        if not values.get(name, "").strip():
            raise BootstrapError(f"{name} is required in {path}")

    return Settings(
        langflow_url=values["LANGFLOW_URL"].rstrip("/"),
        flow_id=values["LANGFLOW_FLOW_ID"],
        langflow_api_key=values["LANGFLOW_API_KEY"],
        openrouter_api_key=values["OPENROUTER_API_KEY"],
    )


def prepare_flow(path: Path, openrouter_api_key: str, expected_endpoint: str) -> bytes:
    try:
        flow = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise BootstrapError(f"Unable to read flow file: {path}") from error

    if flow.get("endpoint_name") != expected_endpoint:
        raise BootstrapError(
            f"Flow endpoint {flow.get('endpoint_name')!r} does not match "
            f"LANGFLOW_FLOW_ID={expected_endpoint!r}"
        )

    matching_inputs: list[dict[str, Any]] = []
    for node in flow.get("data", {}).get("nodes", []):
        template = node.get("data", {}).get("node", {}).get("template", {})
        models = template.get("model", {}).get("value", [])
        if any(model.get("provider") == "OpenRouter" for model in models if isinstance(model, dict)):
            api_key = template.get("api_key")
            if isinstance(api_key, dict):
                matching_inputs.append(api_key)

    if len(matching_inputs) != 1:
        raise BootstrapError(
            f"Expected exactly one OpenRouter API-key input, found {len(matching_inputs)}"
        )

    matching_inputs[0]["value"] = openrouter_api_key
    return json.dumps(flow, ensure_ascii=False).encode("utf-8")


def _decode_json(response: Any, endpoint: str) -> Any:
    raw = response.read()
    if response.headers.get("Content-Encoding") == "gzip" or raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    try:
        return json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BootstrapError(f"Langflow returned invalid JSON from {endpoint}") from error


def _request_json(request: Request) -> Any:
    try:
        with urlopen(request, timeout=45) as response:
            return _decode_json(response, request.full_url)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:300].strip()
        suffix = f": {detail}" if detail else ""
        raise BootstrapError(
            f"Langflow request failed with HTTP {error.code} at {request.full_url}{suffix}"
        ) from error
    except (TimeoutError, URLError, OSError) as error:
        raise BootstrapError(f"Unable to reach Langflow at {request.full_url}") from error


def _multipart_flow(flow_path: Path, flow_bytes: bytes) -> tuple[str, bytes]:
    boundary = f"----rambu-{secrets.token_hex(12)}"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{flow_path.name}"\r\n'
        "Content-Type: application/json\r\n\r\n"
    ).encode("utf-8") + flow_bytes + f"\r\n--{boundary}--\r\n".encode("utf-8")
    return boundary, body


def bootstrap_flow(
    *,
    base_url: str,
    langflow_api_key: str,
    openrouter_api_key: str,
    expected_endpoint: str,
    flow_path: Path,
) -> dict[str, str]:
    flow_bytes = prepare_flow(flow_path, openrouter_api_key, expected_endpoint)
    boundary, body = _multipart_flow(flow_path, flow_bytes)
    headers = {
        "Accept": "application/json",
        "Accept-Encoding": "identity",
        "x-api-key": langflow_api_key,
    }
    upload = Request(
        f"{base_url.rstrip('/')}/api/v1/flows/upload/",
        data=body,
        headers={**headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    _request_json(upload)

    list_request = Request(
        f"{base_url.rstrip('/')}/api/v1/flows/?get_all=true",
        headers=headers,
        method="GET",
    )
    flows = _request_json(list_request)
    if not isinstance(flows, list):
        raise BootstrapError("Langflow flow list has an unexpected response shape")

    matches = [flow for flow in flows if flow.get("endpoint_name") == expected_endpoint]
    if len(matches) != 1:
        raise BootstrapError(
            f"Expected one deployed flow with endpoint {expected_endpoint!r}, found {len(matches)}"
        )

    match = matches[0]
    return {
        "id": str(match.get("id", "")),
        "name": str(match.get("name", "")),
        "endpoint_name": str(match.get("endpoint_name", "")),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Import and configure the Rambu Langflow flow.")
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_FILE)
    parser.add_argument("--flow-file", type=Path, default=DEFAULT_FLOW_FILE)
    args = parser.parse_args()

    try:
        settings = load_settings(args.env_file)
        deployed = bootstrap_flow(
            base_url=settings.langflow_url,
            langflow_api_key=settings.langflow_api_key,
            openrouter_api_key=settings.openrouter_api_key,
            expected_endpoint=settings.flow_id,
            flow_path=args.flow_file,
        )
    except BootstrapError as error:
        print(f"Langflow bootstrap failed: {error}", file=sys.stderr)
        return 1

    print(
        f"Langflow flow ready: {deployed['name']} "
        f"({deployed['endpoint_name']}, {deployed['id']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
