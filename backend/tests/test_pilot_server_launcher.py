from __future__ import annotations

import json
import os
import shutil
import sqlite3
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "tools" / "deploy_pilot_server.sh"
COMPOSE = ROOT / "deploy" / "pilot" / "compose.yaml"


def add_command(bin_directory: Path, name: str, body: str) -> None:
    command = bin_directory / name
    command.write_text(f"#!/usr/bin/env bash\nset -eu\n{body}\n")
    command.chmod(0o755)


def valid_compose_model(*, langflow_ports: bool = False) -> str:
    langflow: dict[str, object] = {"networks": {"private": None}}
    if langflow_ports:
        langflow["ports"] = [{"host_ip": "0.0.0.0", "published": "7860", "target": 7860}]
    return json.dumps(
        {
            "services": {
                "backend": {
                    "ports": [{"host_ip": "127.0.0.1", "published": "8000", "target": 8000}],
                    "networks": {"private": None, "edge": None},
                },
                "langflow": langflow,
                "cloudflared": {
                    "labels": {"com.rambu.tunnel-origin": "http://backend:8000"},
                    "networks": {"edge": None},
                },
            }
        }
    )


def write_fake_docker(
    bin_directory: Path,
    compose_model: str,
    *,
    gpu_ok: bool = True,
    health: str = "healthy",
) -> None:
    add_command(
        bin_directory,
        "docker",
        'printf "%s\\n" "$*" >> "$RAMBU_TEST_DOCKER_LOG"\n'
        'if [[ "${1:-}" == "run" ]]; then\n'
        f"  exit {0 if gpu_ok else 9}\n"
        "fi\n"
        'if [[ " $* " == *" compose "* && " $* " == *" version "* ]]; then exit 0; fi\n'
        'if [[ " $* " == *" config --format json "* ]]; then\n'
        f"  printf '%s\\n' '{compose_model}'\n"
        "  exit 0\n"
        "fi\n"
        'if [[ " $* " == *" ps --status running --quiet "* ]]; then printf "%s\\n" "fake-container"; exit 0; fi\n'
        'if [[ "${1:-}" == "inspect" ]]; then printf "%s\\n" "'
        + health
        + '"; exit 0; fi\n'
        'if [[ " $* " == *" logs "* ]]; then\n'
        '  printf "%s\\n" "$LANGFLOW_API_KEY $OPENROUTER_API_KEY $LANGFLOW_SECRET_KEY"\n'
        "  exit 0\n"
        "fi\n"
        "exit 0",
    )


def prepare_pilot(
    tmp_path: Path,
    *,
    compose_model: str | None = None,
    gpu_ok: bool = True,
    health: str = "healthy",
) -> tuple[Path, Path, dict[str, str], Path]:
    repository = tmp_path / "repository"
    tools = repository / "tools"
    deployment = repository / "deploy" / "pilot"
    tools.mkdir(parents=True)
    deployment.mkdir(parents=True)
    launcher = tools / LAUNCHER.name
    if LAUNCHER.exists():
        shutil.copy2(LAUNCHER, launcher)
    shutil.copy2(COMPOSE, deployment / "compose.yaml")

    pilot_root = tmp_path / "pilot root with spaces"
    secrets = pilot_root / "secrets"
    secrets.mkdir(parents=True)
    (secrets / "AuthKey.p8").write_text("test-apns-private-key")
    (secrets / "cloudflare-tunnel-token").write_text("tunnel-SENTINEL")

    environment_file = tmp_path / "pilot secrets.env"
    environment_file.write_text(
        "RAMBU_PUBLIC_URL=https://rambu-api.sfatimah.com\n"
        "RAMBU_BIND_ADDRESS=127.0.0.1\n"
        "LANGFLOW_FLOW_ID=rambu\n"
        "LANGFLOW_API_KEY=langflow-SENTINEL\n"
        "LANGFLOW_SUPERUSER_PASSWORD=password-SENTINEL\n"
        "LANGFLOW_SECRET_KEY=secret-SENTINEL\n"
        "OPENROUTER_API_KEY=openrouter-SENTINEL\n"
        "APNS_TEAM_ID=TEAM-SENTINEL\n"
        "APNS_KEY_ID=KEY-SENTINEL\n"
        "APNS_BUNDLE_ID=id.rambu.puck\n"
        "APNS_ENVIRONMENT=production\n"
    )

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    docker_log = tmp_path / "docker.log"
    write_fake_docker(
        fake_bin,
        compose_model or valid_compose_model(),
        gpu_ok=gpu_ok,
        health=health,
    )
    add_command(fake_bin, "curl", "exit 0")

    environment = os.environ.copy()
    environment.update(
        {
            "PATH": f"{fake_bin}:{environment['PATH']}",
            "RAMBU_PILOT_ROOT": str(pilot_root),
            "RAMBU_TEST_DOCKER_LOG": str(docker_log),
            "RAMBU_MIN_FREE_KB": "1",
            "RAMBU_HEALTH_ATTEMPTS": "2",
            "RAMBU_HEALTH_INTERVAL": "0",
        }
    )
    return launcher, environment_file, environment, docker_log


def run_launcher(
    launcher: Path,
    command: str,
    environment_file: Path,
    environment: dict[str, str],
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(launcher), command, "--env-file", str(environment_file)],
        cwd=launcher.parents[1],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )


def test_check_rejects_a_missing_environment_file(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path)
    environment_file.unlink()

    result = run_launcher(launcher, "check", environment_file, environment)

    assert result.returncode != 0
    assert "Environment file is missing" in result.stderr


def test_check_rejects_a_blank_required_secret_without_printing_other_secrets(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path)
    environment_file.write_text(
        environment_file.read_text().replace(
            "LANGFLOW_API_KEY=langflow-SENTINEL",
            "LANGFLOW_API_KEY=   ",
        )
    )

    result = run_launcher(launcher, "check", environment_file, environment)

    assert result.returncode != 0
    assert "LANGFLOW_API_KEY is missing" in result.stderr
    assert "SENTINEL" not in result.stdout + result.stderr


def test_check_rejects_insufficient_root_disk_space(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path)
    environment["RAMBU_MIN_FREE_KB"] = "200"
    add_command(
        Path(environment["PATH"].split(":", 1)[0]),
        "df",
        'printf "%s\\n" "Filesystem 1024-blocks Used Available Capacity Mounted on"\n'
        'printf "%s\\n" "/dev/test 1000 900 100 90% /"',
    )

    result = run_launcher(launcher, "check", environment_file, environment)

    assert result.returncode != 0
    assert "Insufficient free space" in result.stderr


def test_check_rejects_failed_gpu_probe(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path, gpu_ok=False)

    result = run_launcher(launcher, "check", environment_file, environment)

    assert result.returncode != 0
    assert "GPU 0 is unavailable" in result.stderr


def test_check_rejects_a_public_langflow_binding(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(
        tmp_path,
        compose_model=valid_compose_model(langflow_ports=True),
    )

    result = run_launcher(launcher, "check", environment_file, environment)

    assert result.returncode != 0
    assert "unsafe network configuration" in result.stderr


def test_logs_redact_every_configured_secret(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path)

    result = run_launcher(launcher, "logs", environment_file, environment)

    assert result.returncode == 0
    assert result.stdout.count("[REDACTED]") == 3
    assert "SENTINEL" not in result.stdout + result.stderr


def test_backup_is_consistent_when_the_pilot_path_contains_spaces(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path)
    database = Path(environment["RAMBU_PILOT_ROOT"]) / "data" / "rambu.sqlite3"
    database.parent.mkdir()
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE families (name TEXT NOT NULL)")
        connection.execute("INSERT INTO families VALUES ('Richard')")

    result = run_launcher(launcher, "backup", environment_file, environment)

    assert result.returncode == 0
    backups = list((Path(environment["RAMBU_PILOT_ROOT"]) / "backups").glob("rambu-*.sqlite3"))
    assert len(backups) == 1
    with sqlite3.connect(backups[0]) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        assert connection.execute("SELECT name FROM families").fetchone() == ("Richard",)


def test_deploy_checks_backs_up_bootstraps_then_starts_public_services(tmp_path: Path) -> None:
    launcher, environment_file, environment, docker_log = prepare_pilot(tmp_path)
    database = Path(environment["RAMBU_PILOT_ROOT"]) / "data" / "rambu.sqlite3"
    database.parent.mkdir()
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE marker (value TEXT)")

    result = run_launcher(launcher, "deploy", environment_file, environment)

    assert result.returncode == 0
    commands = docker_log.read_text()
    assert "compose" in commands
    assert "build backend langflow" in commands
    assert "up -d langflow" in commands
    assert "exec -T langflow python /opt/rambu/scripts/bootstrap_flow.py" in commands
    assert "up -d backend" in commands
    assert "up -d cloudflared" in commands
    assert commands.index("up -d langflow") < commands.index("bootstrap_flow.py") < commands.index("up -d backend")
    assert len(list((Path(environment["RAMBU_PILOT_ROOT"]) / "backups").glob("rambu-*.sqlite3"))) == 1


def test_deploy_fails_when_langflow_never_becomes_healthy(tmp_path: Path) -> None:
    launcher, environment_file, environment, _ = prepare_pilot(tmp_path, health="starting")

    result = run_launcher(launcher, "deploy", environment_file, environment)

    assert result.returncode != 0
    assert "Timed out waiting for langflow health" in result.stderr
