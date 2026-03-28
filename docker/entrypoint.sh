#!/bin/sh
set -eu

/usr/local/bin/validate-runtime.sh

umask 002

APP_DIR="/var/www/html"
SEED_DIR="/var/www/html_default"

CONFIG_FILE="${APP_DIR}/ipconfig.php"
CONFIG_TEMPLATE="${APP_DIR}/ipconfig.php.example"

UPLOADS_DIR="${APP_DIR}/uploads"
LOGS_DIR="${APP_DIR}/application/logs"
CONFIG_DIR="${APP_DIR}/application/config"

CSS_DIR="${APP_DIR}/assets/core/css"
VIEWS_DIR="${APP_DIR}/application/views"
LANG_DIR="${APP_DIR}/application/language/${IP_LANGUAGE}"

SETUP_COMPLETE_VIEW="${APP_DIR}/application/modules/setup/views/complete.php"
CUSTOM_COMPLETE_VIEW="${APP_DIR}/custom-complete.php"

HOST_PUID="${PUID:-1000}"
HOST_PGID="${PGID:-1000}"
HOST_GROUP_NAME=""
HOST_USER_NAME="abc"

ensure_dir() {
  mkdir -p "$1"
}

dir_empty() {
  if [ ! -d "$1" ]; then
    return 0
  fi

  if [ -z "$(find "$1" -mindepth 1 ! -name '.gitkeep' -print -quit 2>/dev/null)" ]; then
    return 0
  fi

  return 1
}

copy_dir_if_empty() {
  source_dir_path="$1"
  target_dir_path="$2"

  if [ ! -d "${source_dir_path}" ]; then
    echo "WARN: Seed source missing: ${source_dir_path}"
    return 0
  fi

  ensure_dir "${target_dir_path}"

  if dir_empty "${target_dir_path}"; then
    echo "Seeding empty directory: ${target_dir_path} <- ${source_dir_path}"
    cp -a "${source_dir_path}/." "${target_dir_path}/"
  else
    echo "Directory already populated: ${target_dir_path}"
  fi
}

copy_file_if_missing() {
  source_file_path="$1"
  target_file_path="$2"

  if [ ! -f "${source_file_path}" ]; then
    echo "WARN: Seed file missing or not a regular file: ${source_file_path}"
    return 0
  fi

  if [ ! -f "${target_file_path}" ]; then
    echo "Copying missing file: ${target_file_path}"
    cp -a "${source_file_path}" "${target_file_path}"
  fi
}

sync_language_dir_preserve_custom() {
  lang_source_dir="${SEED_DIR}/application/language/${IP_LANGUAGE}"
  lang_target_dir="${APP_DIR}/application/language/${IP_LANGUAGE}"

  if [ ! -d "${lang_source_dir}" ]; then
    echo "WARN: Language seed source missing: ${lang_source_dir}"
    return 0
  fi

  ensure_dir "${lang_target_dir}"

  if dir_empty "${lang_target_dir}"; then
    echo "Seeding empty language directory: ${lang_target_dir} <- ${lang_source_dir}"
    cp -a "${lang_source_dir}/." "${lang_target_dir}/"
    return 0
  fi

  echo "Syncing language directory without overwriting custom files: ${lang_target_dir}"
  for lang_item in "${lang_source_dir}"/*; do
    [ -e "${lang_item}" ] || continue

    item_base_name="$(basename "${lang_item}")"

    if [ "${item_base_name}" = "custom_lang.php" ] && [ -f "${lang_target_dir}/${item_base_name}" ]; then
      echo "Preserving existing custom language file: ${lang_target_dir}/${item_base_name}"
      continue
    fi

    copy_file_if_missing "${lang_item}" "${lang_target_dir}/${item_base_name}"
  done
}

ensure_runtime_dirs() {
  ensure_dir "${UPLOADS_DIR}"
  ensure_dir "${UPLOADS_DIR}/archive"
  ensure_dir "${UPLOADS_DIR}/customer_files"
  ensure_dir "${UPLOADS_DIR}/temp"
  ensure_dir "${UPLOADS_DIR}/temp/mpdf"
  ensure_dir "${LOGS_DIR}"
  ensure_dir "${CONFIG_DIR}"
}

install_custom_setup_complete_view() {
  if [ -f "${CUSTOM_COMPLETE_VIEW}" ]; then
    echo "Installing custom setup completion view..."
    ensure_dir "$(dirname "${SETUP_COMPLETE_VIEW}")"
    cp -f "${CUSTOM_COMPLETE_VIEW}" "${SETUP_COMPLETE_VIEW}"
  else
    echo "WARN: Custom completion view missing: ${CUSTOM_COMPLETE_VIEW}"
  fi
}

ensure_host_group_and_user() {
  existing_group_line="$(getent group "${HOST_PGID}" || true)"

  if [ -n "${existing_group_line}" ]; then
    HOST_GROUP_NAME="$(printf '%s' "${existing_group_line}" | cut -d: -f1)"
  else
    HOST_GROUP_NAME="hostgrp"
    groupadd -g "${HOST_PGID}" "${HOST_GROUP_NAME}"
  fi

  if id -u "${HOST_USER_NAME}" >/dev/null 2>&1; then
    current_uid="$(id -u "${HOST_USER_NAME}")"
    current_gid="$(id -g "${HOST_USER_NAME}")"

    if [ "${current_uid}" != "${HOST_PUID}" ]; then
      usermod -u "${HOST_PUID}" "${HOST_USER_NAME}"
    fi

    if [ "${current_gid}" != "${HOST_PGID}" ]; then
      usermod -g "${HOST_PGID}" "${HOST_USER_NAME}"
    fi
  else
    useradd -u "${HOST_PUID}" -g "${HOST_PGID}" -M -N -r -s /usr/sbin/nologin "${HOST_USER_NAME}"
  fi

  usermod -a -G "${HOST_GROUP_NAME}" www-data 2>/dev/null || true
}

set_group_writable_tree() {
  target_path="$1"

  if [ -e "${target_path}" ]; then
    chown -R "${HOST_PUID}:${HOST_PGID}" "${target_path}" 2>/dev/null || true
    find "${target_path}" -type d -exec chmod 2775 {} \; 2>/dev/null || true
    find "${target_path}" -type f -exec chmod 664 {} \; 2>/dev/null || true
  fi
}

set_runtime_permissions() {
  set_group_writable_tree "${UPLOADS_DIR}"
  set_group_writable_tree "${LOGS_DIR}"
  set_group_writable_tree "${CSS_DIR}"
  set_group_writable_tree "${VIEWS_DIR}"
  set_group_writable_tree "${LANG_DIR}"

  chown -R "${HOST_PUID}:${HOST_PGID}" "${CONFIG_DIR}" 2>/dev/null || true
  find "${CONFIG_DIR}" -type d -exec chmod 2775 {} \; 2>/dev/null || true
  find "${CONFIG_DIR}" -type f -exec chmod 664 {} \; 2>/dev/null || true

  chown www-data:"${HOST_GROUP_NAME}" "${APP_DIR}/.htaccess" 2>/dev/null || true
  chmod 664 "${APP_DIR}/.htaccess" 2>/dev/null || true

  chown www-data:"${HOST_GROUP_NAME}" "${SETUP_COMPLETE_VIEW}" 2>/dev/null || true
  chmod 664 "${SETUP_COMPLETE_VIEW}" 2>/dev/null || true

  chown www-data:"${HOST_GROUP_NAME}" "${CUSTOM_COMPLETE_VIEW}" 2>/dev/null || true
  chmod 664 "${CUSTOM_COMPLETE_VIEW}" 2>/dev/null || true
}

finalize_config_permissions() {
  chown www-data:"${HOST_GROUP_NAME}" "${CONFIG_FILE}" 2>/dev/null || true
  chmod 664 "${CONFIG_FILE}" 2>/dev/null || true
}

escape_squote_value() {
  printf "%s" "$1" | sed "s/[\\\\]/\\\\\\\\/g; s/'/'\\\\''/g"
}

format_ipconfig_value() {
  raw_value="${1:-}"

  case "${raw_value}" in
    true|false|TRUE|FALSE)
      printf "%s" "${raw_value}"
      ;;
    ''|*[!0-9]*)
      escaped_value="$(escape_squote_value "${raw_value}")"
      printf "'%s'" "${escaped_value}"
      ;;
    *)
      printf "%s" "${raw_value}"
      ;;
  esac
}

update_config() {
  config_key_name="$1"
  raw_value="${2:-}"
  formatted_value="$(format_ipconfig_value "${raw_value}")"
  tmp_config="${CONFIG_FILE}.tmp.$$"

  awk -v key="${config_key_name}" -v value="${formatted_value}" '
    BEGIN {
      updated = 0
    }
    $0 ~ "^[[:space:]]*" key "=" {
      print key "=" value
      updated = 1
      next
    }
    {
      print
    }
    END {
      if (!updated) {
        print key "=" value
      }
    }
  ' "${CONFIG_FILE}" > "${tmp_config}"

  mv "${tmp_config}" "${CONFIG_FILE}"
}

if [ -f "${APP_DIR}/htaccess" ] && [ ! -f "${APP_DIR}/.htaccess" ]; then
  echo "Renaming htaccess to .htaccess..."
  mv "${APP_DIR}/htaccess" "${APP_DIR}/.htaccess"
fi

copy_dir_if_empty "${SEED_DIR}/assets/core/css" "${CSS_DIR}"
copy_dir_if_empty "${SEED_DIR}/application/views" "${VIEWS_DIR}"
sync_language_dir_preserve_custom

ensure_runtime_dirs
install_custom_setup_complete_view
ensure_host_group_and_user

if [ ! -f "${CONFIG_FILE}" ]; then
  if [ ! -f "${CONFIG_TEMPLATE}" ]; then
    echo "ERROR: Missing template ${CONFIG_TEMPLATE}"
    ls -la "${APP_DIR}"
    exit 1
  fi

  echo "Creating ipconfig.php from template..."
  cp "${CONFIG_TEMPLATE}" "${CONFIG_FILE}"
fi

set_runtime_permissions

update_config "IP_URL" "${IP_URL}"
update_config "ENABLE_DEBUG" "${ENABLE_DEBUG}"
update_config "DISABLE_SETUP" "${DISABLE_SETUP}"
update_config "REMOVE_INDEXPHP" "${REMOVE_INDEXPHP}"

update_config "DB_HOSTNAME" "${MYSQL_HOST}"
update_config "DB_USERNAME" "${MYSQL_USER}"
update_config "DB_PASSWORD" "${MYSQL_PASSWORD}"
update_config "DB_DATABASE" "${MYSQL_DATABASE}"
update_config "DB_PORT" "${MYSQL_PORT}"

update_config "SESS_EXPIRATION" "${SESS_EXPIRATION}"
update_config "SESS_MATCH_IP" "${SESS_MATCH_IP}"
update_config "ENABLE_INVOICE_DELETION" "${ENABLE_INVOICE_DELETION}"
update_config "DISABLE_READ_ONLY" "${DISABLE_READ_ONLY}"

if [ -n "${SETUP_COMPLETED:-}" ]; then
  update_config "SETUP_COMPLETED" "${SETUP_COMPLETED}"
fi

if [ -n "${ENCRYPTION_CIPHER:-}" ]; then
  update_config "ENCRYPTION_CIPHER" "${ENCRYPTION_CIPHER}"
fi

if [ -n "${ENCRYPTION_KEY:-}" ]; then
  update_config "ENCRYPTION_KEY" "${ENCRYPTION_KEY}"
fi

finalize_config_permissions

export SEED_DIR CSS_DIR VIEWS_DIR LANG_DIR IP_LANGUAGE
bash /usr/local/bin/compare_seeded_bind_mounts || true

exec "$@"

