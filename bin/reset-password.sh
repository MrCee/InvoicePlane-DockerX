#!/usr/bin/env bash
set -euo pipefail

APP_SERVICE="${APP_SERVICE:-invoiceplane_app}"
DB_SERVICE="${DB_SERVICE:-invoiceplane_db}"
DB_NAME="${DB_NAME:-invoiceplane}"
USER_ID="${USER_ID:-}"
USER_EMAIL="${USER_EMAIL:-}"
TEMP_PASSWORD="${TEMP_PASSWORD:-}"
ADMIN_BOOTSTRAP="${ADMIN_BOOTSTRAP:-false}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${PROJECT_ROOT}/.backup"

TMP_VALUES=""
SQL_FILE=""

cleanup() {
  [ -n "${TMP_VALUES}" ] && [ -f "${TMP_VALUES}" ] && rm -f "${TMP_VALUES}"
  [ -n "${SQL_FILE}" ] && [ -f "${SQL_FILE}" ] && rm -f "${SQL_FILE}"
}
trap cleanup EXIT

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  local secret="${3:-false}"
  local current_value="${!var_name:-}"

  if [ -n "${current_value}" ]; then
    return 0
  fi

  if [ "${secret}" = "true" ]; then
    read -r -s -p "${prompt_text}: " "${var_name}"
    echo
  else
    read -r -p "${prompt_text}: " "${var_name}"
  fi

  if [ -z "${!var_name}" ]; then
    echo "ERROR: ${var_name} cannot be empty" >&2
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

run_db_query() {
  local sql="$1"
  docker compose exec -T "${DB_SERVICE}" sh -lc \
    'mariadb -N -B -uroot -p"$MYSQL_ROOT_PASSWORD" "'"${DB_NAME}"'" -e "$1"' sh "${sql}"
}

require_command docker
require_command mktemp
require_command sed
require_command date

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin is not available" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

echo "=== verifying services ==="
docker compose ps --status running "${APP_SERVICE}" "${DB_SERVICE}" >/dev/null

if [ -n "${USER_ID}" ]; then
  case "${USER_ID}" in
    ''|*[!0-9]*)
      echo "ERROR: USER_ID must be numeric" >&2
      exit 1
      ;;
  esac
fi

if [ -n "${USER_ID}" ] && [ -n "${USER_EMAIL}" ]; then
  :
elif [ -n "${USER_ID}" ]; then
  echo "=== resolving email from USER_ID ==="
  USER_EMAIL="$(run_db_query "SELECT user_email FROM ip_users WHERE user_id = ${USER_ID} LIMIT 1;")"
  if [ -z "${USER_EMAIL}" ]; then
    echo "ERROR: no user found for USER_ID=${USER_ID}" >&2
    exit 1
  fi
elif [ -n "${USER_EMAIL}" ]; then
  USER_EMAIL_SQL="$(sql_escape "${USER_EMAIL}")"
  echo "=== resolving user_id from USER_EMAIL ==="
  USER_ID="$(run_db_query "SELECT user_id FROM ip_users WHERE user_email = '${USER_EMAIL_SQL}' LIMIT 1;")"
  if [ -z "${USER_ID}" ]; then
    echo "ERROR: no user found for USER_EMAIL=${USER_EMAIL}" >&2
    exit 1
  fi
else
  if [ "${ADMIN_BOOTSTRAP}" != "true" ]; then
    echo "ERROR: provide USER_ID or USER_EMAIL, or set ADMIN_BOOTSTRAP=true" >&2
    exit 1
  fi

  echo "=== admin bootstrap mode ==="
  USER_ROW="$(run_db_query "SELECT user_id, user_email FROM ip_users WHERE user_type = 1 ORDER BY user_id ASC LIMIT 1;")"
  if [ -z "${USER_ROW}" ]; then
    echo "ERROR: no admin user found" >&2
    exit 1
  fi

  USER_ID="$(printf "%s" "${USER_ROW}" | awk '{print $1}')"
  USER_EMAIL="$(printf "%s" "${USER_ROW}" | awk '{print $2}')"

  echo "Admin account selected:"
  echo "  USER_ID=${USER_ID}"
  echo "  USER_EMAIL=${USER_EMAIL}"
  read -r -p 'Type RESET to continue: ' CONFIRM_RESET
  if [ "${CONFIRM_RESET}" != "RESET" ]; then
    echo "Aborted."
    exit 1
  fi
fi

prompt_value TEMP_PASSWORD "Temporary password to set" true

USER_EMAIL_SQL="$(sql_escape "${USER_EMAIL}")"

echo "=== verifying target user exists ==="
MATCH_COUNT="$(run_db_query "SELECT COUNT(*) FROM ip_users WHERE user_id = ${USER_ID} AND user_email = '${USER_EMAIL_SQL}';")"

if [ "${MATCH_COUNT}" != "1" ]; then
  echo "ERROR: expected exactly 1 matching user for user_id=${USER_ID}, user_email=${USER_EMAIL}" >&2
  exit 1
fi

echo "=== generating hash and psalt ==="
TMP_VALUES="$(mktemp)"

printf '%s' "${TEMP_PASSWORD}" | docker compose exec -T "${APP_SERVICE}" php -r '
$pw = stream_get_contents(STDIN);
if ($pw === false) {
    fwrite(STDERR, "Failed to read password from STDIN\n");
    exit(1);
}
$pw = rtrim($pw, "\r\n");
if ($pw === "") {
    fwrite(STDERR, "Password cannot be empty\n");
    exit(1);
}
$hash = password_hash($pw, PASSWORD_BCRYPT);
if ($hash === false) {
    fwrite(STDERR, "password_hash() failed\n");
    exit(1);
}
$psalt = bin2hex(random_bytes(16));
echo $hash, PHP_EOL, $psalt, PHP_EOL;
' > "${TMP_VALUES}"

NEW_HASH="$(sed -n '1p' "${TMP_VALUES}")"
NEW_PSALT="$(sed -n '2p' "${TMP_VALUES}")"

if [ -z "${NEW_HASH}" ] || [ -z "${NEW_PSALT}" ]; then
  echo "ERROR: failed to generate hash/psalt" >&2
  exit 1
fi

NEW_HASH_SQL="$(sql_escape "${NEW_HASH}")"
NEW_PSALT_SQL="$(sql_escape "${NEW_PSALT}")"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/ip_user_${USER_ID}_backup_${TIMESTAMP}.txt"

echo "=== backing up current user row ==="
docker compose exec -T "${DB_SERVICE}" sh -lc \
  'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" "'"${DB_NAME}"'" -e "SELECT * FROM ip_users WHERE user_id = '"${USER_ID}"'\G"' \
  > "${BACKUP_FILE}"

SQL_FILE="$(mktemp)"
cat > "${SQL_FILE}" <<SQL
UPDATE ip_users
SET user_password = '${NEW_HASH_SQL}',
    user_psalt    = '${NEW_PSALT_SQL}'
WHERE user_id = ${USER_ID}
  AND user_email = '${USER_EMAIL_SQL}';

SELECT ROW_COUNT() AS updated_rows;

TRUNCATE TABLE ip_sessions;

SELECT user_id,
       user_email,
       LENGTH(user_password) AS password_len,
       user_psalt
FROM ip_users
WHERE user_id = ${USER_ID}
  AND user_email = '${USER_EMAIL_SQL}';
SQL

echo "=== applying reset ==="
docker compose exec -T "${DB_SERVICE}" sh -lc \
  'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" "'"${DB_NAME}"'"' \
  < "${SQL_FILE}"

echo
echo "=== DONE ==="
echo "User ID:   ${USER_ID}"
echo "Email:     ${USER_EMAIL}"
echo "Backup:    ${BACKUP_FILE}"
echo "Password:  [hidden]"
echo
echo "Now sign in using a private/incognito browser window."
