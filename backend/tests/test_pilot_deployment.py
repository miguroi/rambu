from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENT = ROOT / "deploy" / "pilot"
COMPOSE = DEPLOYMENT / "compose.yaml"
BACKEND_DOCKERFILE = DEPLOYMENT / "backend.Dockerfile"
LANGFLOW_DOCKERFILE = DEPLOYMENT / "langflow.Dockerfile"
EXAMPLE_ENVIRONMENT = DEPLOYMENT / ".env.example"
GITIGNORE = ROOT / ".gitignore"


def _service_blocks(compose: str) -> dict[str, str]:
    lines = compose.splitlines()
    services_index = lines.index("services:")
    blocks: dict[str, list[str]] = {}
    current: str | None = None

    for line in lines[services_index + 1 :]:
        if line and not line.startswith(" "):
            break
        if line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
            current = line.strip()[:-1]
            blocks[current] = []
        elif current is not None:
            blocks[current].append(line)

    return {name: "\n".join(content) for name, content in blocks.items()}


def test_compose_exposes_only_the_backend_to_host_and_tunnel() -> None:
    blocks = _service_blocks(COMPOSE.read_text())

    assert set(blocks) == {"backend", "langflow", "cloudflared"}
    assert '${RAMBU_BIND_ADDRESS:-127.0.0.1}:${RAMBU_BIND_PORT:-8000}:8000' in blocks["backend"]
    assert "ports:" not in blocks["langflow"]
    assert "ports:" not in blocks["cloudflared"]
    assert "- private" in blocks["backend"]
    assert "- edge" in blocks["backend"]
    assert "- private" in blocks["langflow"]
    assert "- edge" not in blocks["langflow"]
    assert "- edge" in blocks["cloudflared"]
    assert "- private" not in blocks["cloudflared"]


def test_compose_pins_runtime_images_and_gpu_zero() -> None:
    compose = COMPOSE.read_text()
    blocks = _service_blocks(compose)

    assert all("platform: linux/amd64" in blocks[name] for name in blocks)
    assert "restart: unless-stopped" in blocks["backend"]
    assert "restart: unless-stopped" in blocks["langflow"]
    assert "restart: unless-stopped" in blocks["cloudflared"]
    assert "device_ids: [\"0\"]" in blocks["backend"]
    assert "NVIDIA_VISIBLE_DEVICES: \"0\"" in blocks["backend"]
    assert "RAMBU_WHISPER_DEVICE: cuda" in blocks["backend"]
    assert "RAMBU_WHISPER_COMPUTE_TYPE: float16" in blocks["backend"]
    assert "RAMBU_WHISPER_DEVICE_INDEX: \"0\"" in blocks["backend"]
    assert "image: cloudflare/cloudflared:2025.11.1" in blocks["cloudflared"]
    assert "--token-file" in blocks["cloudflared"]
    assert 'com.rambu.tunnel-origin: "http://backend:8000"' in blocks["cloudflared"]
    assert 'com.rambu.tunnel-health: "http://backend:8000/health"' in blocks["cloudflared"]


def test_compose_persists_data_and_mounts_credentials_read_only() -> None:
    blocks = _service_blocks(COMPOSE.read_text())

    assert "/srv/rambu/data:/app/backend/data" in blocks["backend"]
    assert "RAMBU_DATABASE_PATH: /app/backend/data/rambu.sqlite3" in blocks["backend"]
    assert "/srv/rambu/secrets/AuthKey.p8:/run/secrets/AuthKey.p8:ro" in blocks["backend"]
    assert "APNS_PRIVATE_KEY_PATH: /run/secrets/AuthKey.p8" in blocks["backend"]
    assert "/srv/rambu/secrets/cloudflare-tunnel-token:/run/secrets/cloudflare-tunnel-token:ro" in blocks[
        "cloudflared"
    ]


def test_images_are_reproducible_and_copy_only_required_sources() -> None:
    backend = BACKEND_DOCKERFILE.read_text()
    langflow = LANGFLOW_DOCKERFILE.read_text()

    assert backend.startswith("FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04")
    assert "COPY backend/pyproject.toml backend/uv.lock" in backend
    assert "uv sync --frozen --no-dev" in backend
    assert "CMD [\"uvicorn\", \"rambu_api.app:app\", \"--host\", \"0.0.0.0\", \"--port\", \"8000\"]" in backend
    assert langflow.startswith("FROM langflowai/langflow:1.12.3")
    assert "COPY langflow/flows/Rambu.json" in langflow
    assert "COPY langflow/scripts/bootstrap_flow.py" in langflow
    assert "COPY ." not in backend
    assert "COPY ." not in langflow


def test_deployment_secrets_and_generated_state_are_ignored() -> None:
    ignored = GITIGNORE.read_text()

    for pattern in (
        "deploy/pilot/.env",
        "*tunnel-token*",
        "*.p8",
        "*.sqlite3",
        "*.sqlite3-*",
        "backups/",
        "model-cache/",
        "*.app",
    ):
        assert pattern in ignored


def test_example_environment_contains_placeholders_only() -> None:
    example = EXAMPLE_ENVIRONMENT.read_text()

    assert "LANGFLOW_URL=http://langflow:7860" in example
    assert "LANGFLOW_FLOW_ID=rambu" in example
    assert "RAMBU_PUBLIC_URL=https://api.rambu.sfatimah.com" in example
    assert "APNS_ENVIRONMENT=production" in example
    assert "replace-with-" in example
    assert "sk-or-" not in example
    assert "eyJ" not in example
