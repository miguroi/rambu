#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: tools/run_remote_demo.sh [--check]

Start the Rambu remote-demo stack in one terminal:
  Langflow, backend, a public Cloudflare Quick Tunnel, and the Mac puck.

After the public URL is ready, the launcher asks for the six-digit family invitation code.

Options:
  --check   Validate local requirements without starting services.
  -h, --help
            Show this help.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

environment_value() {
  awk -F= -v key="$1" '
    $1 == key {
      sub(/^[^=]*=/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      if (($0 ~ /^".*"$/) || ($0 ~ /^\047.*\047$/)) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "${REPOSITORY_ROOT}/backend/.env"
}

check_requirements() {
  local command
  local private_key_path
  local variable
  for command in uv swift cloudflared curl dig; do
    command -v "${command}" >/dev/null 2>&1 || fail "${command} is not installed or not on PATH."
  done

  [[ -f "${REPOSITORY_ROOT}/backend/.env" ]] || fail "backend/.env is missing. Copy backend/.env.example and configure it first."
  [[ -x "${REPOSITORY_ROOT}/langflow/.venv/bin/langflow" ]] || fail "langflow/.venv is missing. Follow the Langflow setup in README.md first."

  for variable in \
    LANGFLOW_URL LANGFLOW_FLOW_ID LANGFLOW_API_KEY OPENROUTER_API_KEY \
    APNS_TEAM_ID APNS_KEY_ID APNS_PRIVATE_KEY_PATH APNS_BUNDLE_ID APNS_ENVIRONMENT; do
    [[ -n "$(environment_value "${variable}")" ]] || fail "${variable} is missing from backend/.env."
  done

  [[ "$(environment_value APNS_ENVIRONMENT)" == "production" ]] || \
    fail "APNS_ENVIRONMENT must be production for TestFlight devices."
  [[ "$(environment_value APNS_BUNDLE_ID)" == "id.rambu.puck" ]] || \
    fail "APNS_BUNDLE_ID must be id.rambu.puck for this TestFlight build."

  private_key_path="$(environment_value APNS_PRIVATE_KEY_PATH)"
  if [[ "${private_key_path}" != /* ]]; then
    private_key_path="${REPOSITORY_ROOT}/${private_key_path}"
  fi
  [[ -f "${private_key_path}" ]] || fail "APNS private key file does not exist at the configured path."
}

service_is_ready() {
  curl --fail --silent --show-error --max-time 2 "$1" >/dev/null 2>&1
}

OWNED_PIDS=""
LAST_STARTED_PID=""
LOG_DIRECTORY=""
PUBLIC_TUNNEL_MAX_ATTEMPTS=2
PUBLIC_TUNNEL_WAIT_SECONDS=120

start_background_process() {
  local log_file="$1"
  shift
  "$@" >"${log_file}" 2>&1 &
  LAST_STARTED_PID=$!
  OWNED_PIDS="${LAST_STARTED_PID} ${OWNED_PIDS}"
}

show_log_tail() {
  local log_file="$1"
  if [[ -f "${log_file}" ]]; then
    printf '\nLast output from %s:\n' "${log_file}" >&2
    tail -n 20 "${log_file}" >&2 || true
  fi
}

stop_background_process() {
  local pid="$1"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
  fi
  wait "${pid}" 2>/dev/null || true
}

wait_for_service() {
  local label="$1"
  local url="$2"
  local pid="$3"
  local log_file="$4"
  local attempt

  for attempt in $(seq 1 60); do
    if service_is_ready "${url}"; then
      return 0
    fi
    if [[ -n "${pid}" ]] && ! kill -0 "${pid}" 2>/dev/null; then
      show_log_tail "${log_file}"
      fail "${label} stopped before it became ready."
    fi
    sleep 0.5
  done

  show_log_tail "${log_file}"
  fail "Timed out waiting for ${label}."
}

cleanup() {
  local exit_status=$?
  local pid
  trap - EXIT INT TERM
  for pid in ${OWNED_PIDS}; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
  for pid in ${OWNED_PIDS}; do
    wait "${pid}" 2>/dev/null || true
  done
  if [[ -n "${LOG_DIRECTORY}" ]]; then
    printf '\nRambu demo stopped. Logs: %s\n' "${LOG_DIRECTORY}"
  fi
  exit "${exit_status}"
}

extract_tunnel_url() {
  sed -nE 's|.*(https://[A-Za-z0-9-]+\.trycloudflare\.com).*|\1|p' "$1" | head -n 1
}

wait_for_tunnel_url() {
  local pid="$1"
  local log_file="$2"
  local attempt
  local tunnel_url

  for attempt in $(seq 1 60); do
    tunnel_url="$(extract_tunnel_url "${log_file}")"
    if [[ -n "${tunnel_url}" ]]; then
      printf '%s\n' "${tunnel_url}"
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      show_log_tail "${log_file}"
      return 1
    fi
    sleep 0.5
  done

  show_log_tail "${log_file}"
  return 1
}

resolve_public_tunnel_ipv4() {
  local hostname="$1"
  local ip_address
  local resolver
  local response

  for resolver in 1.1.1.1 8.8.8.8; do
    response="$(dig +time=2 +tries=1 "@${resolver}" "${hostname}" A +short 2>/dev/null)" || \
      response=""
    ip_address="$({ printf '%s\n' "${response}"; } | awk '
      /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && !found { print; found = 1 }
    ')"
    if [[ -n "${ip_address}" ]]; then
      printf '%s\n' "${ip_address}"
      return 0
    fi
  done

  return 1
}

wait_for_public_tunnel() {
  local url="$1"
  local pid="$2"
  local probe_log="$3"
  local deadline=$((SECONDS + PUBLIC_TUNNEL_WAIT_SECONDS))
  local hostname="${url#https://}"
  local next_progress=$((SECONDS + 15))
  local public_ip
  local remaining

  hostname="${hostname%%/*}"
  printf 'Waiting for Cloudflare public DNS and backend health (up to %ss)...\n' \
    "${PUBLIC_TUNNEL_WAIT_SECONDS}" >&2

  while true; do
    if public_ip="$(resolve_public_tunnel_ipv4 "${hostname}")"; then
      if curl --fail --silent --show-error --max-time 3 \
        --resolve "${hostname}:443:${public_ip}" "${url}" \
        >/dev/null 2>"${probe_log}"; then
        return 0
      fi
    else
      printf 'Public DNS has not published %s yet.\n' "${hostname}" >"${probe_log}"
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      break
    fi
    if (( SECONDS >= deadline )); then
      break
    fi
    if (( SECONDS >= next_progress )); then
      remaining=$((deadline - SECONDS))
      printf '  Still waiting for the tunnel (%ss remaining)...\n' "${remaining}" >&2
      next_progress=$((SECONDS + 15))
    fi
    sleep 1
  done

  if [[ -s "${probe_log}" ]]; then
    printf '\nLast public tunnel readiness error:\n' >&2
    tail -n 5 "${probe_log}" >&2 || true
  fi
  return 1
}

prompt_for_family_code() {
  local family_code
  while true; do
    printf '\nEnter the six-digit family invitation code: ' >&2
    if ! IFS= read -r family_code; then
      fail "No family invitation code was provided."
    fi
    if [[ "${family_code}" =~ ^[0-9]{6}$ ]]; then
      printf '%s\n' "${family_code}"
      return 0
    fi
    printf 'The code must contain exactly six digits.\n' >&2
  done
}

run_demo() {
  local backend_log
  local bootstrap_log
  local family_code
  local langflow_log
  local puck_log
  local puck_token
  local tunnel_log
  local tunnel_attempt
  local tunnel_pid
  local tunnel_probe_log
  local tunnel_ready
  local tunnel_url

  check_requirements
  cd "${REPOSITORY_ROOT}"

  LOG_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/rambu-demo.XXXXXX")"
  langflow_log="${LOG_DIRECTORY}/langflow.log"
  bootstrap_log="${LOG_DIRECTORY}/bootstrap.log"
  backend_log="${LOG_DIRECTORY}/backend.log"
  tunnel_log="${LOG_DIRECTORY}/cloudflared.log"
  tunnel_probe_log="${LOG_DIRECTORY}/cloudflared-readiness.log"
  puck_log="${LOG_DIRECTORY}/puck.log"
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  printf 'Starting Rambu remote-demo stack...\n'

  if service_is_ready "http://127.0.0.1:7861/health"; then
    printf '✓ Langflow is already running.\n'
  else
    start_background_process "${langflow_log}" \
      "${REPOSITORY_ROOT}/langflow/.venv/bin/langflow" run --host 127.0.0.1 --port 7861
    wait_for_service "Langflow" "http://127.0.0.1:7861/health" "${LAST_STARTED_PID}" "${langflow_log}"
    printf '✓ Langflow is ready.\n'
  fi

  printf 'Checking the Rambu Langflow flow...\n'
  if ! uv run --project backend --env-file backend/.env \
    python langflow/scripts/bootstrap_flow.py >"${bootstrap_log}" 2>&1; then
    show_log_tail "${bootstrap_log}"
    fail "Langflow flow bootstrap failed."
  fi
  printf '✓ Langflow flow is ready.\n'

  if service_is_ready "http://127.0.0.1:8000/health"; then
    printf '✓ Backend is already running.\n'
  else
    start_background_process "${backend_log}" \
      uv run --project backend uvicorn rambu_api.app:app \
      --host 127.0.0.1 --port 8000 --env-file backend/.env
    wait_for_service "backend" "http://127.0.0.1:8000/health" "${LAST_STARTED_PID}" "${backend_log}"
    printf '✓ Backend is ready.\n'
  fi

  tunnel_ready=""
  for tunnel_attempt in $(seq 1 "${PUBLIC_TUNNEL_MAX_ATTEMPTS}"); do
    if (( tunnel_attempt > 1 )); then
      printf '\nRetrying Cloudflare Quick Tunnel (%s/%s)...\n' \
        "${tunnel_attempt}" "${PUBLIC_TUNNEL_MAX_ATTEMPTS}" >&2
    fi

    start_background_process "${tunnel_log}" \
      cloudflared tunnel --url http://127.0.0.1:8000
    tunnel_pid="${LAST_STARTED_PID}"

    if tunnel_url="$(wait_for_tunnel_url "${tunnel_pid}" "${tunnel_log}")" && \
      wait_for_public_tunnel "${tunnel_url}/health" "${tunnel_pid}" "${tunnel_probe_log}"; then
      tunnel_ready="yes"
      break
    fi

    stop_background_process "${tunnel_pid}"
  done

  if [[ -z "${tunnel_ready}" ]]; then
    show_log_tail "${tunnel_log}"
    fail "Cloudflare Quick Tunnel did not become publicly reachable after ${PUBLIC_TUNNEL_MAX_ATTEMPTS} attempts."
  fi

  printf '\nPublic server URL for both iPhones:\n%s\n' "${tunnel_url}"
  printf '\nKeep this terminal open. Anyone with this temporary URL can reach the demo backend.\n'
  printf 'On both iPhones, open Profile → Pilot keluarga and use the URL above.\n'
  printf 'Create the family on the parent iPhone, then enter its invitation code here.\n'

  family_code="$(prompt_for_family_code)"
  if ! puck_token="$(
    RAMBU_SERVER_URL="http://127.0.0.1:8000" \
      swift run --package-path tools/rambu-puck-agent \
      rambu-puck-agent pair --code "${family_code}" --name "Mac puck" \
      2>>"${puck_log}"
  )"; then
    show_log_tail "${puck_log}"
    fail "Mac puck pairing failed. Check that the invitation code is current."
  fi
  [[ -n "${puck_token}" ]] || fail "Mac puck pairing returned an empty token."

  printf '\n✓ Mac puck paired. Demo controls are ready. Press Ctrl+C to stop everything.\n\n'
  RAMBU_SERVER_URL="http://127.0.0.1:8000" \
    RAMBU_PUCK_TOKEN="${puck_token}" \
    swift run --package-path tools/rambu-puck-agent rambu-puck-agent listen --manual \
    2> >(tee -a "${puck_log}" >&2)
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --check)
    check_requirements
    printf 'Rambu remote-demo prerequisites are ready.\n'
    exit 0
    ;;
  "")
    run_demo
    ;;
  *)
    usage >&2
    fail "Unknown option: $1"
    ;;
esac
