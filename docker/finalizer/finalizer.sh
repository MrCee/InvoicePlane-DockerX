#!/bin/sh
set -eu

STATE_DIR="${STATE_DIR:-/state}"
WORKSPACE="${WORKSPACE:-/workspace}"
REQUEST_FILE="${STATE_DIR}/finalize.request"
STATUS_FILE="${STATE_DIR}/status.json"
LOG_FILE="${STATE_DIR}/finalizer.log"
LOCK_DIR="${STATE_DIR}/finalizer.lock"
COMPOSE_FILE="${COMPOSE_FILE:-${WORKSPACE}/docker-compose.yml}"
COMPOSE_PROJECT_DIR="${COMPOSE_PROJECT_DIR:-${WORKSPACE}}"
ENV_FILE="${COMPOSE_PROJECT_DIR}/.env"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-invoiceplane_app}"
APP_URL="${APP_URL:-http://invoiceplane_app/}"
READINESS_URL="${READINESS_URL:-${APP_URL}}"

READINESS_MAX_SECONDS="${READINESS_MAX_SECONDS:-300}"
READINESS_INTERVAL_SECONDS="${READINESS_INTERVAL_SECONDS:-2}"

mkdir -p "${STATE_DIR}"
touch "${LOG_FILE}"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_line() {
  line="${1:-}"
  printf '[%s] %s\n' "$(timestamp_utc)" "${line}" >> "${LOG_FILE}"
}

write_status() {
  state="${1:-unknown}"
  message="${2:-}"

  python3 - "$STATUS_FILE" "$state" "$message" <<'PY'
import json
import sys
from datetime import datetime, timezone

status_file, state, message = sys.argv[1:4]
payload = {
    "state": state,
    "message": message,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
with open(status_file, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
PY
}

resolve_host_workspace() {
  self_name=""

  if [ -n "${IP_CONTAINER_NAME:-}" ]; then
    self_name="${IP_CONTAINER_NAME}_finalizer"
  elif [ -n "${HOSTNAME:-}" ]; then
    self_name="${HOSTNAME}"
  fi

  [ -n "${self_name}" ] || return 1

  docker inspect --format '{{range .Mounts}}{{println .Destination "=" .Source}}{{end}}' "${self_name}" 2>/dev/null \
    | awk -F ' = ' -v workspace="${WORKSPACE}" '$1 == workspace { print $2; exit }'
}

HOST_WORKSPACE="$(resolve_host_workspace || true)"
if [ -n "${HOST_WORKSPACE}" ]; then
  COMPOSE_PROJECT_DIR="${HOST_WORKSPACE}"
  COMPOSE_FILE="${HOST_WORKSPACE}/docker-compose.yml"
  ENV_FILE="${COMPOSE_PROJECT_DIR}/.env"
else
  log_line "[warn] Could not resolve host workspace; falling back to ${COMPOSE_PROJECT_DIR}"
fi

append_normalized_file() {
  src="${1:-}"
  [ -f "${src}" ] || return 0
  tr '\r' '\n' < "${src}" >> "${LOG_FILE}"
}

read_env_value() {
  env_key="${1:-}"
  env_file="${2:-}"
  [ -n "${env_key}" ] || return 1
  [ -f "${env_file}" ] || return 1

  grep -E "^${env_key}=" "${env_file}" \
    | tail -n 1 \
    | cut -d '=' -f 2- \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

upsert_env_value() {
  env_key="${1:-}"
  env_value="${2:-}"
  env_file="${3:-}"

  [ -n "${env_key}" ] || return 1
  [ -n "${env_file}" ] || return 1
  [ -f "${env_file}" ] || return 1

  escaped_value="$(printf '%s' "${env_value}" | sed 's/[\/&]/\\&/g')"

  if grep -q "^${env_key}=" "${env_file}"; then
    sed -i.bak "s/^${env_key}=.*/${env_key}=${escaped_value}/" "${env_file}" && rm -f "${env_file}.bak"
  else
    printf '%s=%s\n' "${env_key}" "${env_value}" >> "${env_file}"
  fi
}

generate_encryption_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi

  python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
}

ensure_encryption_values() {
  cipher="$(read_env_value "ENCRYPTION_CIPHER" "${ENV_FILE}" || true)"
  key="$(read_env_value "ENCRYPTION_KEY" "${ENV_FILE}" || true)"

  if [ -z "${cipher}" ]; then
    cipher="AES-256"
    upsert_env_value "ENCRYPTION_CIPHER" "${cipher}" "${ENV_FILE}"
    log_line "[encryption] Set ENCRYPTION_CIPHER=${cipher} in ${ENV_FILE}"
  else
    log_line "[encryption] Preserving existing ENCRYPTION_CIPHER in ${ENV_FILE}"
  fi

  if [ -z "${key}" ]; then
    key="$(generate_encryption_key)"
    upsert_env_value "ENCRYPTION_KEY" "${key}" "${ENV_FILE}"
    log_line "[encryption] Generated ENCRYPTION_KEY in ${ENV_FILE}"
  else
    log_line "[encryption] Preserving existing ENCRYPTION_KEY in ${ENV_FILE}"
  fi
}

HTTP_READY_CODE=""
HTTP_READY_FINAL_URL=""

http_ready() {
  url="${1:-}"

  HTTP_READY_CODE=""
  HTTP_READY_FINAL_URL=""

  command -v curl >/dev/null 2>&1 || return 1

  tmp_i=0
  tmp_meta=""

  while [ "${tmp_i}" -lt 100 ]; do
    candidate="${STATE_DIR}/http-ready.$$.$(date +%s).${tmp_i}.tmp"
    if ( set -C; : > "${candidate}" ) 2>/dev/null; then
      tmp_meta="${candidate}"
      break
    fi
    tmp_i=$((tmp_i + 1))
  done

  [ -n "${tmp_meta}" ] || return 1

  if curl -sS -L -o /dev/null \
      --max-time 10 \
      -w '%{http_code}\n%{url_effective}\n' \
      "${url}" > "${tmp_meta}" 2>/dev/null; then
    :
  else
    rm -f "${tmp_meta}"
    return 1
  fi

  HTTP_READY_CODE="$(sed -n '1p' "${tmp_meta}" 2>/dev/null || true)"
  HTTP_READY_FINAL_URL="$(sed -n '2p' "${tmp_meta}" 2>/dev/null || true)"
  rm -f "${tmp_meta}"

  case "${HTTP_READY_CODE}" in
    200|301|302|303|307|308)
      return 0
      ;;
  esac

  return 1
}

verify_container_env() {
  check_key="${1:-}"
  [ -n "${check_key}" ] || return 1

  docker compose -f "${COMPOSE_FILE}" --project-directory "${COMPOSE_PROJECT_DIR}" exec -T "${COMPOSE_SERVICE}" sh -lc "printenv ${check_key}" 2>/dev/null | tail -n 1
}



mask_env_assignment_line() {
  line="${1:-}"
  case "${line}" in
    ENCRYPTION_KEY=)
      printf "ENCRYPTION_KEY=<blank>\n"
      ;;
    ENCRYPTION_KEY=*)
      printf "ENCRYPTION_KEY=<present>\n"
      ;;
    ENCRYPTION_CIPHER=)
      printf "ENCRYPTION_CIPHER=<blank>\n"
      ;;
    ENCRYPTION_CIPHER=*)
      printf "ENCRYPTION_CIPHER=<present>\n"
      ;;
    *)
      printf "%s\n" "${line}"
      ;;
  esac
}

verify_ipconfig_flags() {
  docker compose -f "${COMPOSE_FILE}" --project-directory "${COMPOSE_PROJECT_DIR}" exec -T "${COMPOSE_SERVICE}" sh -lc '
    if [ -f /var/www/html/ipconfig.php ]; then
      grep -E "^(SETUP_COMPLETED|DISABLE_SETUP|ENCRYPTION_CIPHER|ENCRYPTION_KEY)=" /var/www/html/ipconfig.php || true
    else
      true
    fi
  ' 2>/dev/null
}

run_finalize() {
  tmp_i=0
  TMP_COMPOSE_OUTPUT=""

  while [ "${tmp_i}" -lt 100 ]; do
    candidate="${STATE_DIR}/compose.out.$$.$(date +%s).${tmp_i}.tmp"
    if ( set -C; : > "${candidate}" ) 2>/dev/null; then
      TMP_COMPOSE_OUTPUT="${candidate}"
      break
    fi
    tmp_i=$((tmp_i + 1))
  done

  if [ -z "${TMP_COMPOSE_OUTPUT}" ] || [ ! -f "${TMP_COMPOSE_OUTPUT}" ]; then
    log_line "[error] Failed to create temporary compose output file in ${STATE_DIR}"
    write_status "error" "Failed to create temporary compose output file."
    return 1
  fi

  trap 'rm -f "${TMP_COMPOSE_OUTPUT}"' EXIT INT TERM

  : > "${TMP_COMPOSE_OUTPUT}"

  write_status "updating" "Updating ${ENV_FILE} before container recreate."
  log_line "Finalize request detected."
  log_line "Using workspace: ${WORKSPACE}"
  log_line "Using host workspace: ${COMPOSE_PROJECT_DIR}"
  log_line "Using compose file: ${COMPOSE_FILE}"
  log_line "Using compose service: ${COMPOSE_SERVICE}"

  if [ ! -f "${ENV_FILE}" ]; then
    write_status "error" "Missing ${ENV_FILE}"
    log_line "[error] Missing ${ENV_FILE}"
    return 1
  fi

  upsert_env_value "DISABLE_SETUP" "true" "${ENV_FILE}"
  upsert_env_value "SETUP_COMPLETED" "true" "${ENV_FILE}"
  ensure_encryption_values

  log_line "Updated ${ENV_FILE}."
  log_line "Current .env flags:"
  {
    grep -E '^(DISABLE_SETUP|SETUP_COMPLETED|ENCRYPTION_CIPHER|ENCRYPTION_KEY)=' "${ENV_FILE}" || true
  } | while IFS= read -r line; do
    masked="$(mask_env_assignment_line "${line}")"
    log_line "${masked}"
  done

  write_status "recreating" "Recreating ${COMPOSE_SERVICE} so Compose picks up ${ENV_FILE}."
  log_line "[recreate] Starting docker compose up -d --force-recreate ${COMPOSE_SERVICE}"

  if env -u DISABLE_SETUP -u SETUP_COMPLETED -u ENCRYPTION_CIPHER -u ENCRYPTION_KEY \
      docker compose -f "${COMPOSE_FILE}" --project-directory "${COMPOSE_PROJECT_DIR}" \
      up -d --force-recreate --no-deps "${COMPOSE_SERVICE}" > "${TMP_COMPOSE_OUTPUT}" 2>&1; then
    append_normalized_file "${TMP_COMPOSE_OUTPUT}"
    log_line "[recreate] compose recreate command completed successfully"
  else
    append_normalized_file "${TMP_COMPOSE_OUTPUT}"
    log_line "[error] compose recreate command failed"
    write_status "error" "Docker Compose recreate failed. Review the terminal log."
    return 1
  fi

  write_status "waiting" "Waiting for app readiness."
  log_line "[readiness] Probing ${READINESS_URL}"

  deadline=$(( $(date +%s) + READINESS_MAX_SECONDS ))
  ready=0
  attempt=0

  while [ "$(date +%s)" -le "${deadline}" ]; do
    attempt=$((attempt + 1))

    if http_ready "${READINESS_URL}"; then
      ready=1
      if [ -n "${HTTP_READY_FINAL_URL}" ]; then
        log_line "[readiness] Attempt ${attempt}: HTTP ${HTTP_READY_CODE:-unknown} from ${HTTP_READY_FINAL_URL}"
      else
        log_line "[readiness] Attempt ${attempt}: HTTP ${HTTP_READY_CODE:-unknown}"
      fi
      log_line "[readiness] HTTP probe succeeded for ${READINESS_URL}"
      break
    fi

    if [ -n "${HTTP_READY_FINAL_URL}" ]; then
      log_line "[readiness] Attempt ${attempt}: HTTP ${HTTP_READY_CODE:-unavailable} from ${HTTP_READY_FINAL_URL}; retrying in ${READINESS_INTERVAL_SECONDS}s"
    elif [ -n "${HTTP_READY_CODE}" ]; then
      log_line "[readiness] Attempt ${attempt}: HTTP ${HTTP_READY_CODE}; retrying in ${READINESS_INTERVAL_SECONDS}s"
    else
      log_line "[readiness] Attempt ${attempt}: no successful HTTP response; retrying in ${READINESS_INTERVAL_SECONDS}s"
    fi

    sleep "${READINESS_INTERVAL_SECONDS}"
  done

  if [ "${ready}" -ne 1 ]; then
    log_line "[error] HTTP readiness timed out after ${READINESS_MAX_SECONDS}s while probing ${READINESS_URL}"
    write_status "error" "App did not become reachable before timeout."
    return 1
  fi

  log_line "[verify] Checking env inside recreated container"
  for verify_key in DISABLE_SETUP SETUP_COMPLETED ENCRYPTION_CIPHER ENCRYPTION_KEY; do
    value="$(verify_container_env "${verify_key}" || true)"
    if [ -n "${value}" ]; then
      if [ "${verify_key}" = "ENCRYPTION_KEY" ]; then
        log_line "[verify] container ${verify_key}=<present>"
      else
        log_line "[verify] container ${verify_key}=${value}"
      fi
    else
      log_line "[verify] container ${verify_key}=<unavailable>"
    fi
  done

  log_line "[verify] Checking ipconfig flags inside container"
  verify_ipconfig_flags | while IFS= read -r line; do
    case "${line}" in
      ENCRYPTION_KEY=)
        log_line "[verify] ENCRYPTION_KEY=<blank>"
        ;;
      ENCRYPTION_KEY=*)
        log_line "[verify] ENCRYPTION_KEY=<present>"
        ;;
      *)
        if [ -n "${line}" ]; then
          log_line "[verify] ${line}"
        fi
        ;;
    esac
  done

  log_line "[complete] Finalizer finished successfully"
  write_status "complete" "InvoicePlane finalizer completed successfully."
  return 0
}

main_loop() {
  if [ ! -f "${STATUS_FILE}" ]; then
    write_status "idle" "Waiting for finalize request."
  fi

  log_line "Finalizer started."

  while :; do
    if mkdir "${LOCK_DIR}" 2>/dev/null; then
      if [ -f "${REQUEST_FILE}" ]; then
        rm -f "${REQUEST_FILE}"
        if ! run_finalize; then
          :
        fi
      fi
      rmdir "${LOCK_DIR}" 2>/dev/null || true
    fi
    sleep 1
  done
}

main_loop
