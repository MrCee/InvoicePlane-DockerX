#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# InvoicePlane-DockerX
# bin/up.sh
#
# Purpose
# - Load the project .env into the current shell
# - Patch safe host/runtime values back into .env
# - Prepare host bind-mount directories
# - Validate docker compose config
# - Start database first, wait for health, then start app services
#
# Design Choice
# - .env is treated as the source of truth
# - We do NOT unset setup/encryption values here
# - Instead, we load .env into the shell so compose sees the same values
###############################################################################

###############################################################################
# Small Helpers
###############################################################################
is_integer() {
  case "${1:-}" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

###############################################################################
# Repo Root Discovery
###############################################################################
find_repo_root() {
  local start_dir="$1"
  local current_dir="$start_dir"

  while [ "${current_dir}" != "/" ]; do
    if [ -f "${current_dir}/docker-compose.yml" ] || [ -f "${current_dir}/compose.yml" ]; then
      printf '%s\n' "${current_dir}"
      return 0
    fi
    current_dir="$(dirname "${current_dir}")"
  done

  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(find_repo_root "${SCRIPT_DIR}")" || {
  echo "ERROR: Could not locate repo root from ${SCRIPT_DIR}"
  exit 1
}

cd "${REPO_ROOT}"

###############################################################################
# Core Paths
###############################################################################
ENV_FILE="${REPO_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: Missing ${ENV_FILE}"
  exit 1
fi

###############################################################################
# Docker / Compose Preflight
###############################################################################
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed or not in PATH"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin is not available"
  exit 1
fi

###############################################################################
# Load .env Into Current Shell
#
# Important:
# - This makes the current shell environment match the project .env
# - That means compose interpolation should use the values you actually want
# - This assumes the .env file is shell-safe KEY=VALUE syntax
###############################################################################
load_project_env() {
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
}

###############################################################################
# Compose Wrapper
#
# We still pass --env-file explicitly for clarity and consistency.
###############################################################################
compose() {
  docker compose --env-file "${ENV_FILE}" "$@"
}

###############################################################################
# Load Environment Early
###############################################################################
load_project_env

###############################################################################
# Detect Host UID / GID / Platform
###############################################################################
PUID="$(id -u)"
PGID="$(id -g)"

MYSQL_UID="${MYSQL_UID:-999}"
MYSQL_GID="${MYSQL_GID:-999}"

if ! is_integer "${MYSQL_UID}"; then
  MYSQL_UID=999
fi

if ! is_integer "${MYSQL_GID}"; then
  MYSQL_GID=999
fi

HOST_OS="linux"
if [ "$(uname)" = "Darwin" ]; then
  HOST_OS="macos"
fi

###############################################################################
# Resolve Workspace Path
###############################################################################
HOST_WORKSPACE="${REPO_ROOT}"

echo "========================================"
echo "InvoicePlane-DockerX :: up.sh"
echo "========================================"
echo
echo "Using repo root:"
echo "  ${REPO_ROOT}"
echo
echo "Using .env file:"
echo "  ${ENV_FILE}"
echo
echo "Using install root as HOST_WORKSPACE:"
echo "  ${HOST_WORKSPACE}"
echo

###############################################################################
# Patch .env With Safe Host / Runtime Values Only
#
# This section intentionally updates only:
# - PUID
# - PGID
# - HOST_OS
# - MYSQL_UID
# - MYSQL_GID
# - HOST_WORKSPACE
# - STACK_PREPARED_BY
#
# It does NOT touch:
# - DISABLE_SETUP
# - SETUP_COMPLETED
# - ENCRYPTION_CIPHER
# - ENCRYPTION_KEY
###############################################################################
echo "========================================"
echo "Patching .env"
echo "========================================"

TMP_ENV="${ENV_FILE}.tmp"

awk \
  -v PUID="${PUID}" \
  -v PGID="${PGID}" \
  -v HOST_OS="${HOST_OS}" \
  -v MYSQL_UID="${MYSQL_UID}" \
  -v MYSQL_GID="${MYSQL_GID}" \
  -v HOST_WORKSPACE="${HOST_WORKSPACE}" \
  -v STACK_PREPARED_BY="bin/up.sh" '
BEGIN {
  FS=OFS="="
  seen["PUID"]=0
  seen["PGID"]=0
  seen["HOST_OS"]=0
  seen["MYSQL_UID"]=0
  seen["MYSQL_GID"]=0
  seen["HOST_WORKSPACE"]=0
  seen["STACK_PREPARED_BY"]=0
}
$1=="PUID" {
  print "PUID", PUID
  seen["PUID"]=1
  next
}
$1=="PGID" {
  print "PGID", PGID
  seen["PGID"]=1
  next
}
$1=="HOST_OS" {
  print "HOST_OS", HOST_OS
  seen["HOST_OS"]=1
  next
}
$1=="MYSQL_UID" {
  print "MYSQL_UID", MYSQL_UID
  seen["MYSQL_UID"]=1
  next
}
$1=="MYSQL_GID" {
  print "MYSQL_GID", MYSQL_GID
  seen["MYSQL_GID"]=1
  next
}
$1=="HOST_WORKSPACE" {
  print "HOST_WORKSPACE", HOST_WORKSPACE
  seen["HOST_WORKSPACE"]=1
  next
}
$1=="STACK_PREPARED_BY" {
  print "STACK_PREPARED_BY", STACK_PREPARED_BY
  seen["STACK_PREPARED_BY"]=1
  next
}
{
  print
}
END {
  if (!seen["PUID"])              print "PUID", PUID
  if (!seen["PGID"])              print "PGID", PGID
  if (!seen["HOST_OS"])           print "HOST_OS", HOST_OS
  if (!seen["MYSQL_UID"])         print "MYSQL_UID", MYSQL_UID
  if (!seen["MYSQL_GID"])         print "MYSQL_GID", MYSQL_GID
  if (!seen["HOST_WORKSPACE"])    print "HOST_WORKSPACE", HOST_WORKSPACE
  if (!seen["STACK_PREPARED_BY"]) print "STACK_PREPARED_BY", STACK_PREPARED_BY
}
' "${ENV_FILE}" > "${TMP_ENV}"

chmod 664 "${ENV_FILE}" 2>/dev/null || true
chmod 664 "${TMP_ENV}" 2>/dev/null || true
mv -f "${TMP_ENV}" "${ENV_FILE}"
chmod 664 "${ENV_FILE}" 2>/dev/null || true

###############################################################################
# Reload .env After Patching
#
# This ensures the current shell picks up any fresh PUID/PGID/etc values that
# were just written back into the .env file.
###############################################################################
load_project_env

echo "✅ .env patched"
echo "   PUID=${PUID}"
echo "   PGID=${PGID}"
echo "   HOST_OS=${HOST_OS}"
echo "   MYSQL_UID=${MYSQL_UID}"
echo "   MYSQL_GID=${MYSQL_GID}"
echo "   HOST_WORKSPACE=${HOST_WORKSPACE}"
echo "   STACK_PREPARED_BY=bin/up.sh"
echo

###############################################################################
# Secret Masking Helpers
###############################################################################
mask_secret_presence() {
  local value="${1-}"
  if [ -n "${value}" ]; then
    printf "<present>\n"
  else
    printf "<empty>\n"
  fi
}

mask_env_assignment_line() {
  local line="${1-}"
  case "${line}" in
    ENCRYPTION_KEY=*)
      printf "ENCRYPTION_KEY=<present>\n"
      ;;
    ENCRYPTION_CIPHER=*)
      if [ "${line#ENCRYPTION_CIPHER=}" = "" ]; then
        printf "ENCRYPTION_CIPHER=<empty>\n"
      else
        printf "ENCRYPTION_CIPHER=<present>\n"
      fi
      ;;
    *)
      printf "%s\n" "${line}"
      ;;
  esac
}

###############################################################################
# Show Critical Setup Flags
###############################################################################
echo "========================================"
echo "Critical setup flags from current shell"
echo "========================================"
printf 'DISABLE_SETUP=%s\n' "${DISABLE_SETUP-}"
printf 'SETUP_COMPLETED=%s\n' "${SETUP_COMPLETED-}"
printf 'ENCRYPTION_CIPHER=%s\n' "$(mask_secret_presence "${ENCRYPTION_CIPHER-}")"
printf 'ENCRYPTION_KEY=%s\n' "$(mask_secret_presence "${ENCRYPTION_KEY-}")"
echo

echo "========================================"
echo "Critical setup flags from .env"
echo "========================================"
while IFS= read -r line; do
  mask_env_assignment_line "${line}"
done < <(grep -E '^(DISABLE_SETUP|SETUP_COMPLETED|ENCRYPTION_CIPHER|ENCRYPTION_KEY)=' "${ENV_FILE}" || true)
echo

###############################################################################
# Privilege Helper
###############################################################################
need_sudo="false"
if [ "${HOST_OS}" = "linux" ] && command -v sudo >/dev/null 2>&1; then
  need_sudo="true"
fi

run_maybe_sudo() {
  if [ "${need_sudo}" = "true" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

###############################################################################
# Filesystem Helpers
###############################################################################
ensure_dir() {
  local dir="$1"
  mkdir -p "${REPO_ROOT}/${dir}"
  echo "✅ Ensured: ${dir}"
}

assert_dir_writable() {
  local dir="$1"
  local probe="${REPO_ROOT}/${dir}/.write-test.$$"

  if ! : > "${probe}" 2>/dev/null; then
    echo "ERROR: Host directory is not writable: ${REPO_ROOT}/${dir}"
    ls -ld "${REPO_ROOT}/${dir}" || true
    exit 1
  fi

  rm -f "${probe}"
}

prepare_host_shared_app_dir() {
  local dir="$1"

  ensure_dir "${dir}"

  if [ "${HOST_OS}" = "linux" ]; then
    run_maybe_sudo chown -R "${PUID}:${PGID}" "${REPO_ROOT}/${dir}"
    run_maybe_sudo chmod 775 "${REPO_ROOT}/${dir}"
    run_maybe_sudo find "${REPO_ROOT}/${dir}" -type d -exec chmod 775 {} \; 2>/dev/null || true
    run_maybe_sudo find "${REPO_ROOT}/${dir}" -type f -exec chmod 664 {} \; 2>/dev/null || true
  else
    chmod 775 "${REPO_ROOT}/${dir}"
    find "${REPO_ROOT}/${dir}" -type d -exec chmod 775 {} \; 2>/dev/null || true
    find "${REPO_ROOT}/${dir}" -type f -exec chmod 664 {} \; 2>/dev/null || true
  fi

  assert_dir_writable "${dir}"
}

prepare_host_metadata_dir() {
  local dir="$1"

  ensure_dir "${dir}"

  if [ "${HOST_OS}" = "linux" ]; then
    run_maybe_sudo chown -R "${PUID}:${PGID}" "${REPO_ROOT}/${dir}"
    run_maybe_sudo chmod 775 "${REPO_ROOT}/${dir}"
    run_maybe_sudo find "${REPO_ROOT}/${dir}" -type d -exec chmod 775 {} \; 2>/dev/null || true
    run_maybe_sudo find "${REPO_ROOT}/${dir}" -type f -exec chmod 664 {} \; 2>/dev/null || true
  else
    chmod 775 "${REPO_ROOT}/${dir}"
    find "${REPO_ROOT}/${dir}" -type d -exec chmod 775 {} \; 2>/dev/null || true
    find "${REPO_ROOT}/${dir}" -type f -exec chmod 664 {} \; 2>/dev/null || true
  fi

  assert_dir_writable "${dir}"
}

prepare_finalize_dir() {
  local dir="${REPO_ROOT}/data/finalize"

  ensure_dir "data/finalize"

  if [ "${HOST_OS}" = "linux" ]; then
    run_maybe_sudo chown -R "${PUID}:${PGID}" "${dir}"
    run_maybe_sudo chmod 777 "${dir}"
    run_maybe_sudo find "${dir}" -type d -exec chmod 777 {} \; 2>/dev/null || true
    run_maybe_sudo find "${dir}" -type f -exec chmod 666 {} \; 2>/dev/null || true
  else
    chmod 777 "${dir}"
    find "${dir}" -type d -exec chmod 777 {} \; 2>/dev/null || true
    find "${dir}" -type f -exec chmod 666 {} \; 2>/dev/null || true
  fi

  assert_dir_writable "data/finalize"
}

prepare_mariadb_dir() {
  local dir="${REPO_ROOT}/mariadb"

  ensure_dir "mariadb"

  if [ "${HOST_OS}" = "linux" ]; then
    run_maybe_sudo chown -R "${MYSQL_UID}:${MYSQL_GID}" "${dir}"
    run_maybe_sudo chmod 777 "${dir}"
    run_maybe_sudo find "${dir}" -type d -exec chmod 777 {} \; 2>/dev/null || true
    run_maybe_sudo find "${dir}" -type f -exec chmod 666 {} \; 2>/dev/null || true
  else
    chmod 777 "${dir}"
    find "${dir}" -type d -exec chmod 777 {} \; 2>/dev/null || true
    find "${dir}" -type f -exec chmod 666 {} \; 2>/dev/null || true
  fi

  assert_dir_writable "mariadb"
}

bootstrap_bind_mounted_helper_file() {
  local rel_dir="invoiceplane_helpers"
  local rel_file="${rel_dir}/mpdf_helper.php"
  local abs_dir="${REPO_ROOT}/${rel_dir}"
  local abs_file="${REPO_ROOT}/${rel_file}"
  local image_ref="${IP_IMAGE}:${IP_VERSION}"

  ensure_dir "${rel_dir}"

  if [ -f "${abs_file}" ]; then
    echo "✅ Helper override already present: ${rel_file}"
    return 0
  fi

  echo "⏳ Bootstrapping ${rel_file} from pristine image source..."

  case "${UP_BUILD_MODE:-rebuild}" in
    none)
      echo "ERROR: ${rel_file} is missing, but UP_BUILD_MODE=none prevents building the image needed to extract it"
      echo "Either create ${rel_file} manually first, or rerun with UP_BUILD_MODE=pull or UP_BUILD_MODE=rebuild"
      exit 1
      ;;
    pull)
      compose pull invoiceplane_app
      ;;
    rebuild)
      compose build --no-cache --pull invoiceplane_app
      ;;
    *)
      echo "ERROR: Unsupported UP_BUILD_MODE=${UP_BUILD_MODE}"
      echo "Valid values: none, pull, rebuild"
      exit 1
      ;;
  esac

  if ! docker run --rm \
      --entrypoint sh \
      "${image_ref}" \
      -lc 'cat /var/www/html_default/application/helpers/mpdf_helper.php' \
      > "${abs_file}"; then
    rm -f "${abs_file}"
    echo "ERROR: Failed to bootstrap ${rel_file} from ${image_ref}"
    exit 1
  fi

  if [ "${HOST_OS}" = "linux" ]; then
    run_maybe_sudo chown "${PUID}:${PGID}" "${abs_file}"
    run_maybe_sudo chmod 664 "${abs_file}"
  else
    chmod 664 "${abs_file}"
  fi

  if [ ! -s "${abs_file}" ]; then
    rm -f "${abs_file}"
    echo "ERROR: Bootstrapped ${rel_file} is empty"
    exit 1
  fi

  echo "✅ Bootstrapped ${rel_file}"
}

###############################################################################
# Wait For MariaDB Health
###############################################################################
wait_for_db_health() {
  local db_cid=""
  local max_wait=90
  local i=0
  local health=""

  db_cid="$(compose ps -q invoiceplane_db)"

  if [ -z "${db_cid}" ]; then
    echo "ERROR: Could not resolve container ID for invoiceplane_db"
    compose ps || true
    exit 1
  fi

  echo "⏳ Waiting for invoiceplane_db to become healthy..."

  while [ "${i}" -lt "${max_wait}" ]; do
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${db_cid}" 2>/dev/null || true)"

    case "${health}" in
      healthy)
        echo "✅ invoiceplane_db is healthy"
        return 0
        ;;
      running|starting|created)
        ;;
      unhealthy|exited|dead)
        echo "ERROR: invoiceplane_db entered bad state: ${health}"
        echo
        echo "=== docker compose ps ==="
        compose ps || true
        echo
        echo "=== invoiceplane_db logs ==="
        compose logs --tail=200 invoiceplane_db || true
        exit 1
        ;;
      *)
        ;;
    esac

    i=$((i + 1))
    sleep 1
  done

  echo "ERROR: Timed out waiting for invoiceplane_db to become healthy"
  echo
  echo "=== docker compose ps ==="
  compose ps || true
  echo
  echo "=== invoiceplane_db logs ==="
  compose logs --tail=200 invoiceplane_db || true
  exit 1
}

###############################################################################
# Prepare Host Volume Directories
###############################################################################
echo "========================================"
echo "Preparing host volume directories"
echo "========================================"

prepare_host_shared_app_dir "invoiceplane_uploads"
prepare_host_shared_app_dir "invoiceplane_css"
prepare_host_shared_app_dir "invoiceplane_views"
prepare_host_shared_app_dir "invoiceplane_language"
prepare_host_shared_app_dir "invoiceplane_helpers"
prepare_host_metadata_dir "data"
prepare_host_shared_app_dir "data/logs"
prepare_finalize_dir
prepare_mariadb_dir
echo

###############################################################################
# Sync CSS Overrides (non-destructive backfill)
###############################################################################
echo "========================================"
echo "Syncing CSS overrides"
echo "========================================"

CSS_SRC="${REPO_ROOT}/docker/overrides/invoiceplane_css"
CSS_DST="${REPO_ROOT}/invoiceplane_css"

if [ -d "${CSS_SRC}" ]; then
  find "${CSS_SRC}" -type f | while IFS= read -r src; do
    rel="${src#${CSS_SRC}/}"
    dst="${CSS_DST}/${rel}"

    if [ ! -e "${dst}" ]; then
      mkdir -p "$(dirname "${dst}")"
      cp -p "${src}" "${dst}"
      echo "➕ CSS added: ${rel}"
    else
      echo "✔ CSS exists: ${rel}"
    fi
  done
else
  echo "ℹ️ No CSS override source found at ${CSS_SRC}"
fi

echo

###############################################################################
# Bootstrap Required Direct File Bind Mounts
###############################################################################
echo "========================================"
echo "Bootstrapping direct file bind mounts"
echo "========================================"

bootstrap_bind_mounted_helper_file
echo

###############################################################################
# Prepare Finalizer State Files
###############################################################################
echo "========================================"
echo "Preparing finalizer state files"
echo "========================================"

printf '%s\n' '{"state":"idle","message":"Waiting for finalize request."}' > "${REPO_ROOT}/data/finalize/status.json"
: > "${REPO_ROOT}/data/finalize/finalizer.log"

if [ "${HOST_OS}" = "linux" ]; then
  run_maybe_sudo chown "${PUID}:${PGID}" "${REPO_ROOT}/data/finalize/status.json"
  run_maybe_sudo chown "${PUID}:${PGID}" "${REPO_ROOT}/data/finalize/finalizer.log"
  run_maybe_sudo chmod 666 "${REPO_ROOT}/data/finalize/status.json"
  run_maybe_sudo chmod 666 "${REPO_ROOT}/data/finalize/finalizer.log"
else
  chmod 666 "${REPO_ROOT}/data/finalize/status.json"
  chmod 666 "${REPO_ROOT}/data/finalize/finalizer.log"
fi

assert_dir_writable "data/finalize"
echo

###############################################################################
# Validate Compose Config
###############################################################################
echo "========================================"
echo "Validating docker compose config"
echo "========================================"
compose config >/dev/null
echo "✅ docker compose config is valid"
echo

###############################################################################
# Show Resolved Critical Values
###############################################################################
echo "========================================"
echo "Resolved critical setup values"
echo "========================================"
while IFS= read -r line; do
  mask_env_assignment_line "${line}"
done < <(compose config | grep -E 'DISABLE_SETUP|SETUP_COMPLETED|ENCRYPTION_CIPHER|ENCRYPTION_KEY' || true)
echo

###############################################################################
# Optional Build Modes
#
# Supported:
# - none
# - pull
# - rebuild
###############################################################################
UP_BUILD_MODE="${UP_BUILD_MODE:-none}"

echo "========================================"
echo "Build mode"
echo "========================================"

case "${UP_BUILD_MODE}" in
  none)
    echo "ℹ️ Build mode: none"
    ;;
  pull)
    echo "🏗️ Build mode: pull"
    compose build --pull
    ;;
  rebuild)
    echo "🏗️ Build mode: rebuild"
    compose build --no-cache --pull
    ;;
  *)
    echo "ERROR: Unsupported UP_BUILD_MODE=${UP_BUILD_MODE}"
    echo "Valid values: none, pull, rebuild"
    exit 1
    ;;
esac
echo

###############################################################################
# Stop Existing Stack
###############################################################################
echo "========================================"
echo "Stopping existing stack"
echo "========================================"
compose down --remove-orphans
echo

###############################################################################
# Start Database First
###############################################################################
echo "========================================"
echo "Starting database first"
echo "========================================"
compose up -d invoiceplane_db

wait_for_db_health
echo

###############################################################################
# Start App Services
###############################################################################
echo "========================================"
echo "Starting app services"
echo "========================================"
compose up -d invoiceplane_app invoiceplane_finalizer
echo

###############################################################################
# Final Status Summary
###############################################################################
echo "========================================"
echo "Stack started"
echo "========================================"
echo
echo "✅ Stack started cleanly."
echo
echo "=== docker compose ps ==="
compose ps || true
echo
echo "=== finalize status ==="
cat "${REPO_ROOT}/data/finalize/status.json" || true
echo
echo "=== bind mount perms ==="
ls -ld \
  "${REPO_ROOT}/invoiceplane_uploads" \
  "${REPO_ROOT}/invoiceplane_css" \
  "${REPO_ROOT}/invoiceplane_views" \
  "${REPO_ROOT}/invoiceplane_language" \
  "${REPO_ROOT}/invoiceplane_helpers" \
  "${REPO_ROOT}/invoiceplane_helpers/mpdf_helper.php" \
  "${REPO_ROOT}/data/logs" \
  "${REPO_ROOT}/data/finalize" \
  "${REPO_ROOT}/mariadb" || true
echo
echo "Useful checks:"
echo "  docker compose --env-file \"${ENV_FILE}\" logs --tail=200 invoiceplane_db"
echo "  docker compose --env-file \"${ENV_FILE}\" logs --tail=200 invoiceplane_app"
echo "  docker compose --env-file \"${ENV_FILE}\" logs --tail=200 invoiceplane_finalizer"

