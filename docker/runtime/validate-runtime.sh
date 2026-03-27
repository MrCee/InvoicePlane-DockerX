#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo
  echo "❌ Runtime validation failed: $*"
  echo
  echo "This stack was not prepared correctly."
  echo "Run ./bin/up.sh from the project root before starting the stack."
  echo
  exit 1
}

info() {
  echo "🔎 $*"
}

require_nonempty() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  [ -n "${var_value}" ] || fail "${var_name} is blank"
}

require_dir() {
  local dir_path="$1"
  [ -d "${dir_path}" ] || fail "Required directory missing: ${dir_path}"
}

require_file() {
  local file_path="$1"
  [ -f "${file_path}" ] || fail "Required file missing: ${file_path}"
}

require_writable_dir() {
  local dir_path="$1"
  local test_file="${dir_path}/.validate-runtime.$$"

  if ! touch "${test_file}" 2>/dev/null; then
    fail "Directory is not writable: ${dir_path}"
  fi

  rm -f "${test_file}" 2>/dev/null || true
}

require_numeric() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  case "${var_value}" in
    ''|*[!0-9]*)
      fail "${var_name} must be numeric, got: ${var_value:-<blank>}"
      ;;
  esac
}

SCRIPT_NAME="${0##*/}"

info "Starting runtime validation (${SCRIPT_NAME})..."

# ============================================================
# Required environment variables
# ============================================================
require_nonempty "PUID"
require_nonempty "PGID"
require_nonempty "HOST_OS"
require_nonempty "HOST_WORKSPACE"
require_nonempty "MYSQL_UID"
require_nonempty "MYSQL_GID"

require_numeric "PUID"
require_numeric "PGID"
require_numeric "MYSQL_UID"
require_numeric "MYSQL_GID"

case "${HOST_OS}" in
  linux|macos)
    ;;
  *)
    fail "HOST_OS must be 'linux' or 'macos', got: ${HOST_OS}"
    ;;
esac

info "System-managed environment values are present."

# ============================================================
# Detect mode
# ============================================================
# Workspace mode:
#   Full host workspace is visible here (host shell or finalizer-style mount)
#
# App mode:
#   Only app-visible bind mounts exist here
WORKSPACE_MODE=false
if [ -d "${HOST_WORKSPACE}" ] && [ -f "${HOST_WORKSPACE}/docker-compose.yml" ] && [ -f "${HOST_WORKSPACE}/.env" ]; then
  WORKSPACE_MODE=true
fi

if [ "${WORKSPACE_MODE}" = "true" ]; then
  info "Validation mode: workspace/full-install-root"

  require_dir "${HOST_WORKSPACE}"
  require_file "${HOST_WORKSPACE}/docker-compose.yml"
  require_file "${HOST_WORKSPACE}/.env"

  REQUIRED_DIRS=(
    "${HOST_WORKSPACE}/invoiceplane_uploads"
    "${HOST_WORKSPACE}/invoiceplane_css"
    "${HOST_WORKSPACE}/invoiceplane_views"
    "${HOST_WORKSPACE}/invoiceplane_language"
    "${HOST_WORKSPACE}/mariadb"
    "${HOST_WORKSPACE}/data"
    "${HOST_WORKSPACE}/data/logs"
    "${HOST_WORKSPACE}/data/finalize"
  )

  for dir in "${REQUIRED_DIRS[@]}"; do
    require_dir "${dir}"
  done

  WRITABLE_DIRS=(
    "${HOST_WORKSPACE}/invoiceplane_uploads"
    "${HOST_WORKSPACE}/invoiceplane_css"
    "${HOST_WORKSPACE}/invoiceplane_views"
    "${HOST_WORKSPACE}/invoiceplane_language"
    "${HOST_WORKSPACE}/data/logs"
    "${HOST_WORKSPACE}/data/finalize"
  )

  for dir in "${WRITABLE_DIRS[@]}"; do
    require_writable_dir "${dir}"
  done

  info "Workspace structure and writable bind sources look good."
else
  info "Validation mode: app-runtime/container-visible-paths"

  APP_ROOT="/var/www/html"
  STATE_DIR="/state"

  require_dir "${APP_ROOT}"
  require_dir "${STATE_DIR}"

  REQUIRED_DIRS=(
    "${APP_ROOT}/uploads"
    "${APP_ROOT}/assets/core/css"
    "${APP_ROOT}/application/views"
    "${APP_ROOT}/application/language"
    "${APP_ROOT}/application/logs"
  )

  for dir in "${REQUIRED_DIRS[@]}"; do
    require_dir "${dir}"
  done

  require_file "${APP_ROOT}/index.php"

  WRITABLE_DIRS=(
    "${APP_ROOT}/uploads"
    "${APP_ROOT}/assets/core/css"
    "${APP_ROOT}/application/views"
    "${APP_ROOT}/application/language"
    "${APP_ROOT}/application/logs"
    "${STATE_DIR}"
  )

  for dir in "${WRITABLE_DIRS[@]}"; do
    require_writable_dir "${dir}"
  done

  info "App-visible bind mounts and writable paths look good."
fi

# ============================================================
# Optional validation marker
# ============================================================
if [ -n "${STACK_PREPARED_BY:-}" ]; then
  if [ "${STACK_PREPARED_BY}" != "bin/up.sh" ]; then
    fail "STACK_PREPARED_BY is invalid: ${STACK_PREPARED_BY}"
  fi
  info "Preparation marker present: ${STACK_PREPARED_BY}"
else
  info "Preparation marker not set; continuing."
fi

echo
echo "✅ Runtime validation passed"
echo "   PUID=${PUID}"
echo "   PGID=${PGID}"
echo "   HOST_OS=${HOST_OS}"
echo "   HOST_WORKSPACE=${HOST_WORKSPACE}"
echo "   MYSQL_UID=${MYSQL_UID}"
echo "   MYSQL_GID=${MYSQL_GID}"
echo "   MODE=$([ "${WORKSPACE_MODE}" = "true" ] && echo workspace || echo app-runtime)"
echo
