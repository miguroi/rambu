from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = REPOSITORY_ROOT / "tools" / "run_remote_demo.sh"


def copy_launcher(tmp_path: Path) -> Path:
    tools = tmp_path / "tools"
    tools.mkdir()
    copied = tools / LAUNCHER.name
    shutil.copy2(LAUNCHER, copied)
    return copied


def add_fake_command(bin_directory: Path, name: str, body: str = "exit 0") -> None:
    command = bin_directory / name
    command.write_text(f"#!/usr/bin/env bash\n{body}\n")
    command.chmod(0o755)


def prepare_fake_requirements(tmp_path: Path) -> tuple[Path, dict[str, str]]:
    launcher = copy_launcher(tmp_path)
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    for command in ("uv", "swift", "cloudflared", "curl"):
        add_fake_command(fake_bin, command)
    add_fake_command(fake_bin, "dig", 'printf "%s\\n" "104.16.230.132"')
    langflow = tmp_path / "langflow" / ".venv" / "bin" / "langflow"
    langflow.parent.mkdir(parents=True)
    langflow.write_text("#!/usr/bin/env bash\nexit 0\n")
    langflow.chmod(0o755)
    environment = os.environ.copy()
    environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
    return launcher, environment


def write_valid_environment(
    tmp_path: Path,
    *,
    apns_environment: str = "production",
    bundle_id: str = "id.rambu.puck",
) -> None:
    backend = tmp_path / "backend"
    backend.mkdir(exist_ok=True)
    private_key = tmp_path / "AuthKey_TEST.p8"
    private_key.write_text("test-key")
    (backend / ".env").write_text(
        "LANGFLOW_URL=http://127.0.0.1:7861\n"
        "LANGFLOW_FLOW_ID=rambu\n"
        "LANGFLOW_API_KEY=langflow-secret\n"
        "OPENROUTER_API_KEY=openrouter-secret\n"
        "APNS_TEAM_ID=TEAM123\n"
        "APNS_KEY_ID=KEY123\n"
        f"APNS_PRIVATE_KEY_PATH={private_key}\n"
        f"APNS_BUNDLE_ID={bundle_id}\n"
        f"APNS_ENVIRONMENT={apns_environment}\n"
    )


def test_help_describes_the_single_terminal_workflow() -> None:
    result = subprocess.run(
        ["bash", str(LAUNCHER), "--help"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "run_remote_demo.sh" in result.stdout
    assert "--check" in result.stdout
    assert "six-digit family invitation code" in result.stdout


def test_check_rejects_a_missing_backend_environment(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)

    result = subprocess.run(
        ["bash", str(launcher), "--check"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "backend/.env is missing" in result.stderr


def test_check_rejects_incomplete_testflight_push_configuration(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    backend = tmp_path / "backend"
    backend.mkdir()
    (backend / ".env").write_text(
        "LANGFLOW_URL=http://127.0.0.1:7861\n"
        "LANGFLOW_FLOW_ID=rambu\n"
        "LANGFLOW_API_KEY=langflow-secret\n"
        "OPENROUTER_API_KEY=openrouter-secret\n"
        "APNS_ENVIRONMENT=production\n"
    )

    result = subprocess.run(
        ["bash", str(launcher), "--check"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "APNS_TEAM_ID is missing" in result.stderr


def test_check_requires_production_apns_for_testflight(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path, apns_environment="sandbox")

    result = subprocess.run(
        ["bash", str(launcher), "--check"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "APNS_ENVIRONMENT must be production" in result.stderr


def test_check_requires_push_credentials_for_the_testflight_bundle(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path, bundle_id="id.example.wrong")

    result = subprocess.run(
        ["bash", str(launcher), "--check"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "APNS_BUNDLE_ID must be id.rambu.puck" in result.stderr


def test_check_rejects_a_missing_apns_private_key_file(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path)
    (tmp_path / "AuthKey_TEST.p8").unlink()

    result = subprocess.run(
        ["bash", str(launcher), "--check"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "APNS private key file does not exist" in result.stderr


def test_launcher_prints_tunnel_url_and_keeps_puck_on_local_backend(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path)
    capture = tmp_path / "puck-environment.txt"
    tunnel_pid = tmp_path / "tunnel.pid"
    environment["RAMBU_TEST_CAPTURE"] = str(capture)
    environment["RAMBU_TEST_TUNNEL_PID"] = str(tunnel_pid)
    fake_bin = tmp_path / "bin"
    add_fake_command(fake_bin, "curl")
    add_fake_command(
        fake_bin,
        "cloudflared",
        'printf "%s\\n" "Quick Tunnel: https://demo-test.trycloudflare.com" >&2\n'
        'printf "%s\\n" "$$" > "$RAMBU_TEST_TUNNEL_PID"\n'
        "trap 'exit 0' TERM INT\n"
        "while :; do sleep 1; done",
    )
    add_fake_command(
        fake_bin,
        "swift",
        'case " $* " in\n'
        '  *" pair "*)\n'
        '    case " $* " in *" --code 123456 "*) printf "%s\\n" "paired-token" ;; *) exit 9 ;; esac\n'
        "    ;;\n"
        '  *" listen --manual "*) printf "%s\\n%s\\n" "$RAMBU_SERVER_URL" "$RAMBU_PUCK_TOKEN" > "$RAMBU_TEST_CAPTURE" ;;\n'
        '  *" listen --detect-audio "*) exit 8 ;;\n'
        '  *" listen "*) exit 7 ;;\n'
        "  *) exit 2 ;;\n"
        "esac",
    )

    result = subprocess.run(
        ["bash", str(launcher)],
        cwd=tmp_path,
        env=environment,
        input="123456\n",
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
    assert "https://demo-test.trycloudflare.com" in result.stdout
    assert capture.read_text().splitlines() == [
        "http://127.0.0.1:8000",
        "paired-token",
    ]
    with pytest.raises(ProcessLookupError):
        os.kill(int(tunnel_pid.read_text().strip()), 0)


def test_launcher_binds_started_backend_to_loopback(tmp_path: Path) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path)
    fake_bin = tmp_path / "bin"
    backend_ready = tmp_path / "backend.ready"
    backend_arguments = tmp_path / "backend-arguments.txt"
    environment["RAMBU_TEST_BACKEND_READY"] = str(backend_ready)
    environment["RAMBU_TEST_BACKEND_ARGUMENTS"] = str(backend_arguments)
    add_fake_command(
        fake_bin,
        "curl",
        'case "$*" in\n'
        '  *"127.0.0.1:7861"*) exit 0 ;;\n'
        '  *"127.0.0.1:8000"*) test -f "$RAMBU_TEST_BACKEND_READY" ;;\n'
        '  *"trycloudflare.com"*) exit 0 ;;\n'
        '  *) exit 1 ;;\n'
        "esac",
    )
    add_fake_command(
        fake_bin,
        "uv",
        'case " $* " in\n'
        '  *" python langflow/scripts/bootstrap_flow.py "*) exit 0 ;;\n'
        '  *" uvicorn rambu_api.app:app "*)\n'
        '    printf "%s\\n" "$*" > "$RAMBU_TEST_BACKEND_ARGUMENTS"\n'
        '    touch "$RAMBU_TEST_BACKEND_READY"\n'
        "    trap 'exit 0' TERM INT\n"
        '    while :; do sleep 1; done ;;\n'
        '  *) exit 2 ;;\n'
        "esac",
    )
    add_fake_command(
        fake_bin,
        "cloudflared",
        'printf "%s\\n" "Quick Tunnel: https://demo-test.trycloudflare.com" >&2\n'
        "trap 'exit 0' TERM INT\n"
        "while :; do sleep 1; done",
    )
    add_fake_command(
        fake_bin,
        "swift",
        'case " $* " in\n'
        '  *" pair "*) printf "%s\\n" "paired-token" ;;\n'
        '  *" listen "*) exit 0 ;;\n'
        '  *) exit 2 ;;\n'
        "esac",
    )

    result = subprocess.run(
        ["bash", str(launcher)],
        cwd=tmp_path,
        env=environment,
        input="123456\n",
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
    assert "--host 127.0.0.1" in backend_arguments.read_text()
    assert "--host 0.0.0.0" not in backend_arguments.read_text()


def test_launcher_retries_when_the_first_quick_tunnel_never_becomes_ready(
    tmp_path: Path,
) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path)
    fake_bin = tmp_path / "bin"
    tunnel_attempts = tmp_path / "tunnel-attempts.txt"
    environment["RAMBU_TEST_TUNNEL_ATTEMPTS"] = str(tunnel_attempts)
    add_fake_command(
        fake_bin,
        "curl",
        'case "$*" in\n'
        '  *"127.0.0.1"*) exit 0 ;;\n'
        '  *"first-test.trycloudflare.com"*)\n'
        '    printf "%s\\n" "curl: (6) Could not resolve host: first-test.trycloudflare.com" >&2\n'
        "    exit 6 ;;\n"
        '  *"second-test.trycloudflare.com"*) exit 0 ;;\n'
        "  *) exit 1 ;;\n"
        "esac",
    )
    add_fake_command(
        fake_bin,
        "cloudflared",
        'attempt=0\n'
        'if test -f "$RAMBU_TEST_TUNNEL_ATTEMPTS"; then attempt="$(cat "$RAMBU_TEST_TUNNEL_ATTEMPTS")"; fi\n'
        'attempt=$((attempt + 1))\n'
        'printf "%s\\n" "$attempt" > "$RAMBU_TEST_TUNNEL_ATTEMPTS"\n'
        'if test "$attempt" -eq 1; then\n'
        '  printf "%s\\n" "Quick Tunnel: https://first-test.trycloudflare.com" >&2\n'
        "  exit 1\n"
        "fi\n"
        'printf "%s\\n" "Quick Tunnel: https://second-test.trycloudflare.com" >&2\n'
        "trap 'exit 0' TERM INT\n"
        "while :; do sleep 1; done",
    )
    add_fake_command(
        fake_bin,
        "swift",
        'case " $* " in\n'
        '  *" pair "*) printf "%s\\n" "paired-token" ;;\n'
        '  *" listen "*) exit 0 ;;\n'
        '  *) exit 2 ;;\n'
        "esac",
    )

    result = subprocess.run(
        ["bash", str(launcher)],
        cwd=tmp_path,
        env=environment,
        input="123456\n",
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
    assert tunnel_attempts.read_text().strip() == "2"
    assert "Retrying Cloudflare Quick Tunnel (2/2)" in result.stderr
    assert "Could not resolve host: first-test.trycloudflare.com" in result.stderr
    assert "https://second-test.trycloudflare.com" in result.stdout


def test_launcher_uses_public_dns_when_local_dns_has_cached_not_found(
    tmp_path: Path,
) -> None:
    launcher, environment = prepare_fake_requirements(tmp_path)
    write_valid_environment(tmp_path)
    fake_bin = tmp_path / "bin"
    curl_arguments = tmp_path / "public-curl-arguments.txt"
    environment["RAMBU_TEST_CURL_ARGUMENTS"] = str(curl_arguments)
    add_fake_command(
        fake_bin,
        "curl",
        'case "$*" in\n'
        '  *"127.0.0.1"*) exit 0 ;;\n'
        '  *"public-dns-test.trycloudflare.com"*)\n'
        '    printf "%s\\n" "$*" > "$RAMBU_TEST_CURL_ARGUMENTS"\n'
        '    case "$*" in\n'
        '      *"--resolve public-dns-test.trycloudflare.com:443:104.16.230.132"*) exit 0 ;;\n'
        "      *)\n"
        '        printf "%s\\n" "curl: (6) Could not resolve host: public-dns-test.trycloudflare.com" >&2\n'
        "        exit 6 ;;\n"
        "    esac ;;\n"
        "  *) exit 1 ;;\n"
        "esac",
    )
    add_fake_command(
        fake_bin,
        "cloudflared",
        'printf "%s\\n" "Quick Tunnel: https://public-dns-test.trycloudflare.com" >&2\n'
        "sleep 1\n"
        "exit 1",
    )
    add_fake_command(
        fake_bin,
        "swift",
        'case " $* " in\n'
        '  *" pair "*) printf "%s\\n" "paired-token" ;;\n'
        '  *" listen "*) exit 0 ;;\n'
        '  *) exit 2 ;;\n'
        "esac",
    )

    result = subprocess.run(
        ["bash", str(launcher)],
        cwd=tmp_path,
        env=environment,
        input="123456\n",
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
    assert (
        "--resolve public-dns-test.trycloudflare.com:443:104.16.230.132"
        in curl_arguments.read_text()
    )
    assert "https://public-dns-test.trycloudflare.com" in result.stdout
