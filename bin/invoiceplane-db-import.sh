#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# InvoicePlane-DockerX
# bin/invoiceplane-db-import.sh
#
# InvoicePlane DB Import — RECONCILE ONLY / AUTHORITY REWRITE
#
# Policy:
#   - Never perform a blind direct import into the live DB
#   - Require the live InvoicePlane schema to already exist
#   - Require the InvoicePlane setup wizard to have created the live schema first
#   - Reconcile old data into the live schema with schema-aware mapping
#   - Preserve live-only columns introduced by newer versions
#   - Never import runtime/session/import bookkeeping tables
#   - Treat environment-owned and relationship-sensitive tables specially
#
# Ownership model:
#   DO_NOT_IMPORT
#     ip_sessions
#     ip_login_log
#     ip_imports
#     ip_import_details
#     ip_versions
#
#   MANUAL_REVIEW
#     ip_users
#     ip_user_custom
#     ip_user_clients
#
#   MERGE_SPECIAL
#     ip_settings
#     ip_custom_fields
#     ip_*_custom
#
#   AUTO_RECONCILE
#     everything else shared between temp and live
#
# Guarantees:
#   - no direct-import fallback
#   - no silent zero-shared-table success
#   - no silent dropping of temp-only columns from shared tables
#   - every shared table gets an explicit policy classification
###############################################################################

show_help() {
  cat <<'EOF'
invoiceplane-db-import.sh

InvoicePlane DB Import — RECONCILE ONLY / AUTHORITY REWRITE

Usage:
  bin/invoiceplane-db-import.sh --dump /path/to/file.sql
  bin/invoiceplane-db-import.sh --dump /path/to/file.sql --yes
  bin/invoiceplane-db-import.sh --dump /path/to/file.sql --dry-run
  bin/invoiceplane-db-import.sh

Options:
  --dump <file>     Path to SQL dump
  --yes             Run non-interactively
  --dry-run         Analyse only; do not mutate live tables
  --help            Show this help

Rules:
- This script is reconcile-only.
- Run the InvoicePlane setup wizard first.
- The live destination schema must already exist.
- Runtime/session/import bookkeeping tables are not imported.
- Shared tables are reconciled using schema-aware mapping.
- Live-only columns are preserved.
EOF
}

DUMP_FILE=""
ASSUME_YES=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dump)
      [ "$#" -ge 2 ] || { echo "ERROR: --dump requires a file path" >&2; exit 1; }
      DUMP_FILE="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

find_repo_root() {
  local start_dir="${1:-$PWD}"
  local current_dir
  local compose_file=""

  current_dir="$(cd "$start_dir" && pwd)"

  while [ "$current_dir" != "/" ]; do
    if [ -f "$current_dir/docker-compose.yml" ]; then
      compose_file="$current_dir/docker-compose.yml"
    elif [ -f "$current_dir/compose.yml" ]; then
      compose_file="$current_dir/compose.yml"
    else
      compose_file=""
    fi

    if [ -n "$compose_file" ] \
      && [ -f "$current_dir/.env" ] \
      && [ -d "$current_dir/bin" ]; then
      printf '%s\n' "$current_dir"
      return 0
    fi

    current_dir="$(dirname "$current_dir")"
  done

  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(find_repo_root "${SCRIPT_DIR}")" || {
  echo "ERROR: Could not locate repo root from ${SCRIPT_DIR}" >&2
  exit 1
}

cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
[ -f "${ENV_FILE}" ] || { echo "ERROR: Missing ${ENV_FILE}" >&2; exit 1; }

set -a
. "${ENV_FILE}"
set +a

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker missing" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose plugin missing" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 missing" >&2; exit 1; }

echo "Using repo root: ${REPO_ROOT}"

compose() {
  docker compose --env-file "${ENV_FILE}" "$@"
}

db_exec() {
  compose exec -T invoiceplane_db sh -lc "$1"
}

prompt_yes_no() {
  local prompt="$1"
  local reply=""
  local tty="/dev/tty"

  if [ "${ASSUME_YES}" = "1" ]; then
    return 0
  fi

  while true; do
    if [ -r "${tty}" ]; then
      printf '%s [y/n]: ' "${prompt}" > "${tty}"
      IFS= read -r reply < "${tty}"
    else
      read -r -p "${prompt} [y/n]: " reply
    fi

    case "${reply}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

trim_file() {
  local file="$1"
  if [ -f "${file}" ]; then
    awk 'NF{print}' "${file}" > "${file}.tmp" || true
    mv -f "${file}.tmp" "${file}"
  fi
}

db_client_cmd() {
  db_exec '
if command -v mariadb >/dev/null 2>&1; then
  printf "%s" "mariadb"
elif command -v mysql >/dev/null 2>&1; then
  printf "%s" "mysql"
else
  echo "ERROR: Neither mariadb nor mysql exists in invoiceplane_db" >&2
  exit 1
fi
'
}

db_dump_cmd() {
  db_exec '
if command -v mariadb-dump >/dev/null 2>&1; then
  printf "%s" "mariadb-dump"
elif command -v mysqldump >/dev/null 2>&1; then
  printf "%s" "mysqldump"
else
  echo "ERROR: Neither mariadb-dump nor mysqldump exists in invoiceplane_db" >&2
  exit 1
fi
'
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

write_sql_file() {
  local path="$1"
  local content="$2"
  printf '%s\n' "${content}" > "${path}"
}

exec_sql_file() {
  local db_name="$1"
  local sql_file="$2"
  local extra_opts="${3:-}"

  if [ -n "${db_name}" ]; then
    compose exec -T invoiceplane_db sh -lc \
      "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_CLIENT_CMD} ${extra_opts} -h 127.0.0.1 -P 3306 -u root -p\"\$MYSQL_ROOT_PASSWORD\" \"${db_name}\"" < "${sql_file}"
  else
    compose exec -T invoiceplane_db sh -lc \
      "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_CLIENT_CMD} ${extra_opts} -h 127.0.0.1 -P 3306 -u root -p\"\$MYSQL_ROOT_PASSWORD\"" < "${sql_file}"
  fi
}

exec_sql() {
  local db_name="$1"
  local sql_text="$2"
  local extra_opts="${3:-}"
  local tmp_sql
  tmp_sql="$(mktemp)"
  write_sql_file "${tmp_sql}" "${sql_text}"
  exec_sql_file "${db_name}" "${tmp_sql}" "${extra_opts}"
  rm -f "${tmp_sql}"
}

query_sql() {
  local db_name="$1"
  local sql_text="$2"
  local extra_opts="${3:--N -B}"
  local tmp_sql
  tmp_sql="$(mktemp)"
  write_sql_file "${tmp_sql}" "${sql_text}"
  exec_sql_file "${db_name}" "${tmp_sql}" "${extra_opts}" | tr -d '\r'
  rm -f "${tmp_sql}"
}

table_exists() {
  local db_name="$1"
  local table_name="$2"
  local count

  count="$(
    query_sql "${db_name}" "
SELECT COUNT(*)
FROM information_schema.tables
WHERE table_schema = '$(sql_escape "${db_name}")'
  AND table_name = '$(sql_escape "${table_name}")';
"
  )"

  [ "${count}" = "1" ]
}

column_exists() {
  local db_name="$1"
  local table_name="$2"
  local column_name="$3"
  local count

  count="$(
    query_sql "${db_name}" "
SELECT COUNT(*)
FROM information_schema.columns
WHERE table_schema = '$(sql_escape "${db_name}")'
  AND table_name = '$(sql_escape "${table_name}")'
  AND column_name = '$(sql_escape "${column_name}")';
"
  )"

  [ "${count}" = "1" ]
}

column_data_type() {
  local db_name="$1"
  local table_name="$2"
  local column_name="$3"

  query_sql "${db_name}" "
SELECT DATA_TYPE
FROM information_schema.columns
WHERE table_schema = '$(sql_escape "${db_name}")'
  AND table_name = '$(sql_escape "${table_name}")'
  AND column_name = '$(sql_escape "${column_name}")'
LIMIT 1;
"
}

is_textual_data_type() {
  local data_type="${1,,}"
  case "${data_type}" in
    char|varchar|tinytext|text|mediumtext|longtext|enum|set)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

normalized_text_expr() {
  local alias="$1"
  local column_name="$2"
  printf "CONVERT(%s.\`%s\` USING utf8mb4) COLLATE utf8mb4_unicode_ci" "${alias}" "${column_name}"
}

safe_equality_expr() {
  local db_left="$1"
  local table_left="$2"
  local alias_left="$3"
  local db_right="$4"
  local table_right="$5"
  local alias_right="$6"
  local column_name="$7"

  local left_type
  local right_type

  left_type="$(column_data_type "${db_left}" "${table_left}" "${column_name}")"
  right_type="$(column_data_type "${db_right}" "${table_right}" "${column_name}")"

  if is_textual_data_type "${left_type}" || is_textual_data_type "${right_type}"; then
    printf "%s = %s" \
      "$(normalized_text_expr "${alias_left}" "${column_name}")" \
      "$(normalized_text_expr "${alias_right}" "${column_name}")"
  else
    printf "%s.\`%s\` = %s.\`%s\`" "${alias_left}" "${column_name}" "${alias_right}" "${column_name}"
  fi
}

table_row_count_or_dash() {
  local db_name="$1"
  local table="$2"

  if table_exists "${db_name}" "${table}"; then
    query_sql "${db_name}" "SELECT COUNT(*) FROM \`${table}\`;"
  else
    printf '%s\n' "-"
  fi
}

fetch_columns_meta() {
  local db_name="$1"
  local table_name="$2"

  query_sql "${db_name}" "
SELECT
  COLUMN_NAME,
  COLUMN_TYPE,
  IS_NULLABLE,
  COALESCE(COLUMN_DEFAULT, '[[[NULL_DEFAULT]]]'),
  EXTRA,
  ORDINAL_POSITION
FROM information_schema.columns
WHERE table_schema = '$(sql_escape "${db_name}")'
  AND table_name = '$(sql_escape "${table_name}")'
ORDER BY ORDINAL_POSITION;
"
}

fetch_indexes_meta() {
  local db_name="$1"
  local table_name="$2"

  query_sql "${db_name}" "
SELECT
  INDEX_NAME,
  NON_UNIQUE,
  SEQ_IN_INDEX,
  COLUMN_NAME
FROM information_schema.statistics
WHERE table_schema = '$(sql_escape "${db_name}")'
  AND table_name = '$(sql_escape "${table_name}")'
ORDER BY INDEX_NAME, SEQ_IN_INDEX;
"
}

primary_key_file() {
  local table="$1"
  local pk_file="${WORK_DIR}/primary-key-${table}.txt"

  query_sql "${LIVE_DB}" "
SELECT COLUMN_NAME
FROM information_schema.statistics
WHERE table_schema = '$(sql_escape "${LIVE_DB}")'
  AND table_name = '$(sql_escape "${table}")'
  AND index_name = 'PRIMARY'
ORDER BY SEQ_IN_INDEX;
" > "${pk_file}" || true

  trim_file "${pk_file}"
  printf '%s\n' "${pk_file}"
}

has_primary_key() {
  local table="$1"
  local pk_file
  pk_file="$(primary_key_file "${table}")"
  [ -s "${pk_file}" ]
}

build_common_column_file() {
  local table_name="$1"
  local common_file="${WORK_DIR}/common-columns-${table_name}.txt"

  python3 - "${WORK_DIR}/schema-${table_name}-temp-cols.tsv" "${WORK_DIR}/schema-${table_name}-live-cols.tsv" "${common_file}" <<'PY'
import sys

temp_cols_file, live_cols_file, out_file = sys.argv[1:]

def load_names(path):
    names = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            names.append(line.split("\t")[0])
    return names

temp_names = load_names(temp_cols_file)
live_names = set(load_names(live_cols_file))

with open(out_file, "w", encoding="utf-8") as out:
    for name in temp_names:
        if name in live_names:
            out.write(name + "\n")
PY

  printf '%s\n' "${common_file}"
}

build_mutable_common_column_file() {
  local table="$1"
  local pk_file
  local common_file
  local out_file="${WORK_DIR}/mutable-columns-${table}.txt"

  pk_file="$(primary_key_file "${table}")"
  common_file="$(build_common_column_file "${table}")"

  python3 - "${common_file}" "${pk_file}" "${WORK_DIR}/schema-${table}-live-cols.tsv" "${out_file}" <<'PY'
import sys

common_file, pk_file, live_cols_file, out_file = sys.argv[1:]

pk = set()
with open(pk_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            pk.add(line)

extra_map = {}
with open(live_cols_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        extra_map[parts[0]] = parts[4].lower()

with open(out_file, "w", encoding="utf-8") as out:
    with open(common_file, "r", encoding="utf-8") as f:
        for line in f:
            col = line.strip()
            if not col or col in pk:
                continue
            if "auto_increment" in extra_map.get(col, ""):
                continue
            out.write(col + "\n")
PY

  printf '%s\n' "${out_file}"
}

build_join_condition_from_file() {
  local db_left="$1"
  local table_left="$2"
  local alias_left="$3"
  local db_right="$4"
  local table_right="$5"
  local alias_right="$6"
  local file="$7"

  local first=1
  local col
  while IFS= read -r col; do
    [ -n "${col}" ] || continue
    if [ "${first}" -eq 1 ]; then
      first=0
    else
      printf " AND "
    fi
    safe_equality_expr "${db_left}" "${table_left}" "${alias_left}" "${db_right}" "${table_right}" "${alias_right}" "${col}"
  done < "${file}"
  printf "\n"
}

build_column_list_from_file() {
  local file="$1"

  awk '
    NF {
      gsub(/`/, "``", $0)
      printf "%s`%s`", (NR==1 ? "" : ","), $0
    }
    END { print "" }
  ' "${file}"
}

build_select_list_from_file() {
  local alias="$1"
  local file="$2"

  awk -v a="${alias}" '
    NF {
      gsub(/`/, "``", $0)
      printf "%s%s.`%s`", (NR==1 ? "" : ","), a, $0
    }
    END { print "" }
  ' "${file}"
}

build_update_assignments_from_file() {
  local live_alias="$1"
  local temp_alias="$2"
  local file="$3"

  awk -v l="${live_alias}" -v t="${temp_alias}" '
    NF {
      gsub(/`/, "``", $0)
      printf "%s%s.`%s` = %s.`%s`", (NR==1 ? "" : ","), l, $0, t, $0
    }
    END { print "" }
  ' "${file}"
}

classify_table_schema() {
  local table_name="$1"
  local temp_cols_file="${WORK_DIR}/schema-${table_name}-temp-cols.tsv"
  local live_cols_file="${WORK_DIR}/schema-${table_name}-live-cols.tsv"
  local temp_idx_file="${WORK_DIR}/schema-${table_name}-temp-idx.tsv"
  local live_idx_file="${WORK_DIR}/schema-${table_name}-live-idx.tsv"

  fetch_columns_meta "${TEMP_DB}" "${table_name}" > "${temp_cols_file}"
  fetch_columns_meta "${LIVE_DB}" "${table_name}" > "${live_cols_file}"
  fetch_indexes_meta "${TEMP_DB}" "${table_name}" > "${temp_idx_file}"
  fetch_indexes_meta "${LIVE_DB}" "${table_name}" > "${live_idx_file}"

  python3 - "${table_name}" "${temp_cols_file}" "${live_cols_file}" "${temp_idx_file}" "${live_idx_file}" <<'PY'
import sys

table_name, temp_cols_file, live_cols_file, temp_idx_file, live_idx_file = sys.argv[1:]

def load_cols(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 6:
                print("INCOMPATIBLE")
                print(f"bad-column-metadata\t{path}\t{line}")
                sys.exit(0)
            name, coltype, nullable, default, extra, ordinal = parts
            rows.append({
                "name": name,
                "type": coltype.lower(),
                "nullable": nullable,
                "default": default,
                "extra": extra.lower(),
                "ordinal": int(ordinal),
            })
    return rows

def load_idx(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                print("INCOMPATIBLE")
                print(f"bad-index-metadata\t{path}\t{line}")
                sys.exit(0)
            rows.append(tuple(parts))
    return rows

temp_cols = load_cols(temp_cols_file)
live_cols = load_cols(live_cols_file)
temp_idx = load_idx(temp_idx_file)
live_idx = load_idx(live_idx_file)

temp_names = [c["name"] for c in temp_cols]
live_names = [c["name"] for c in live_cols]
temp_map = {c["name"]: c for c in temp_cols}
live_map = {c["name"]: c for c in live_cols}

if temp_names == live_names:
    exact_ok = True
    for name in temp_names:
        t = temp_map[name]
        l = live_map[name]
        if (
            t["type"] != l["type"]
            or t["nullable"] != l["nullable"]
            or t["default"] != l["default"]
            or t["extra"] != l["extra"]
        ):
            exact_ok = False
            break

    if exact_ok and temp_idx == live_idx:
        print("EXACT")
        print("temp_only_columns\t(none)")
        print("live_only_columns\t(none)")
        sys.exit(0)

temp_only = sorted(set(temp_names) - set(live_names))
live_only = sorted(set(live_names) - set(temp_names))

for name in sorted(set(temp_names) & set(live_names)):
    t = temp_map[name]
    l = live_map[name]

    if t["type"] != l["type"]:
        print("INCOMPATIBLE")
        print(f"type-mismatch\t{name}\t{t['type']}\t{l['type']}")
        print("temp_only_columns\t" + (",".join(temp_only) if temp_only else "(none)"))
        print("live_only_columns\t" + (",".join(live_only) if live_only else "(none)"))
        sys.exit(0)

    if t["nullable"] == "YES" and l["nullable"] == "NO" and l["default"] == "[[[NULL_DEFAULT]]]":
        print("INCOMPATIBLE")
        print(f"nullable-source-into-required-live\t{name}")
        print("temp_only_columns\t" + (",".join(temp_only) if temp_only else "(none)"))
        print("live_only_columns\t" + (",".join(live_only) if live_only else "(none)"))
        sys.exit(0)

for name in live_only:
    l = live_map[name]
    has_default = l["default"] != "[[[NULL_DEFAULT]]]"
    nullable = l["nullable"] == "YES"
    autoish = "auto_increment" in l["extra"]

    if not (has_default or nullable or autoish):
        print("INCOMPATIBLE")
        print(f"new-required-live-column\t{name}")
        print("temp_only_columns\t" + (",".join(temp_only) if temp_only else "(none)"))
        print("live_only_columns\t" + (",".join(live_only) if live_only else "(none)"))
        sys.exit(0)

print("ADDITIVE_COMPATIBLE")
print("temp_only_columns\t" + (",".join(temp_only) if temp_only else "(none)"))
print("live_only_columns\t" + (",".join(live_only) if live_only else "(none)"))
PY
}

declare -A TABLE_POLICY
declare -A TABLE_SCHEMA_CLASS
declare -A TABLE_NOTES
declare -A LIVE_BEFORE_COUNTS

record_policy() {
  local table="$1"
  local policy="$2"
  local schema_class="$3"
  local action="$4"
  local notes="$5"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "${table}" "${policy}" "${schema_class}" "${action}" "${notes}" \
    >> "${POLICY_REPORT_FILE}"
}

record_execution() {
  local table="$1"
  local policy="$2"
  local schema_class="$3"
  local planned_action="$4"
  local attempted_methods="$5"
  local winning_method="$6"
  local final_status="$7"
  local notes="$8"
  local temp_count
  local live_before
  local live_after

  temp_count="$(table_row_count_or_dash "${TEMP_DB}" "${table}")"
  live_before="${LIVE_BEFORE_COUNTS[${table}]:--}"
  live_after="$(table_row_count_or_dash "${LIVE_DB}" "${table}")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${table}" \
    "${policy}" \
    "${schema_class}" \
    "${planned_action}" \
    "${attempted_methods}" \
    "${winning_method}" \
    "${final_status}" \
    "${temp_count}" \
    "${live_before}" \
    "${live_after}" \
    "${notes}" \
    >> "${EXECUTION_REPORT_FILE}"
}

record_column_diff() {
  local table="$1"
  local schema_class="$2"
  local detail_file="${WORK_DIR}/schema-detail-${table}.txt"
  local temp_only_columns="(none)"
  local live_only_columns="(none)"

  if [ -f "${detail_file}" ]; then
    temp_only_columns="$(awk -F '\t' '$1=="temp_only_columns"{print $2}' "${detail_file}" | tail -n1)"
    live_only_columns="$(awk -F '\t' '$1=="live_only_columns"{print $2}' "${detail_file}" | tail -n1)"
    [ -n "${temp_only_columns}" ] || temp_only_columns="(none)"
    [ -n "${live_only_columns}" ] || live_only_columns="(none)"
  fi

  printf '%s\t%s\t%s\t%s\n' \
    "${table}" "${schema_class}" "${temp_only_columns}" "${live_only_columns}" \
    >> "${COLUMN_DIFF_REPORT_FILE}"
}

backup_table_name() {
  local table="$1"
  printf '__ipheal_backup_%s\n' "${table}"
}

snapshot_live_table() {
  local table="$1"
  local backup_table
  backup_table="$(backup_table_name "${table}")"

  exec_sql "${LIVE_DB}" "
DROP TABLE IF EXISTS \`${backup_table}\`;
CREATE TABLE \`${backup_table}\` LIKE \`${table}\`;
INSERT INTO \`${backup_table}\` SELECT * FROM \`${table}\`;
"
}

restore_live_table_snapshot() {
  local table="$1"
  local backup_table
  backup_table="$(backup_table_name "${table}")"

  if table_exists "${LIVE_DB}" "${backup_table}"; then
    exec_sql "${LIVE_DB}" "
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE \`${table}\`;
INSERT INTO \`${table}\` SELECT * FROM \`${backup_table}\`;
SET FOREIGN_KEY_CHECKS=1;
"
  fi
}

drop_live_table_snapshot() {
  local table="$1"
  local backup_table
  backup_table="$(backup_table_name "${table}")"

  exec_sql "${LIVE_DB}" "DROP TABLE IF EXISTS \`${backup_table}\`;"
}

verify_replace_success() {
  local table="$1"
  local temp_count
  local live_count

  temp_count="$(query_sql "${TEMP_DB}" "SELECT COUNT(*) FROM \`${table}\`;")"
  live_count="$(query_sql "${LIVE_DB}" "SELECT COUNT(*) FROM \`${table}\`;")"

  [ "${temp_count}" = "${live_count}" ]
}

verify_pk_coverage_success() {
  local table="$1"
  local pk_file
  local join_cond
  local pk_first
  local missing_count

  pk_file="$(primary_key_file "${table}")"
  [ -s "${pk_file}" ] || return 1

  join_cond="$(build_join_condition_from_file "${TEMP_DB}" "${table}" "t" "${LIVE_DB}" "${table}" "l" "${pk_file}")"
  pk_first="$(head -n1 "${pk_file}")"

  missing_count="$(
    query_sql "${LIVE_DB}" "
SELECT COUNT(*)
FROM \`${TEMP_DB}\`.\`${table}\` t
LEFT JOIN \`${table}\` l
  ON ${join_cond}
WHERE l.\`${pk_first}\` IS NULL;
"
  )"

  [ "${missing_count}" = "0" ]
}

method_exact_replace_dump_pipe() {
  local table="$1"

  exec_sql "${LIVE_DB}" "
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE \`${table}\`;
SET FOREIGN_KEY_CHECKS=1;
"

  db_exec "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_DUMP_CMD} -h 127.0.0.1 -P 3306 --no-create-info --skip-triggers -u root -p\"\$MYSQL_ROOT_PASSWORD\" \"${TEMP_DB}\" \"${table}\"" \
    | compose exec -T invoiceplane_db sh -lc \
        "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_CLIENT_CMD} -h 127.0.0.1 -P 3306 -u root -p\"\$MYSQL_ROOT_PASSWORD\" \"${LIVE_DB}\""
}

method_mapped_replace() {
  local table="$1"
  local common_file
  local insert_cols
  local select_cols

  common_file="$(build_common_column_file "${table}")"
  [ -s "${common_file}" ] || return 1

  insert_cols="$(build_column_list_from_file "${common_file}")"
  select_cols="$(build_select_list_from_file "t" "${common_file}")"

  exec_sql "${LIVE_DB}" "
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE \`${table}\`;
INSERT INTO \`${table}\` (${insert_cols})
SELECT ${select_cols}
FROM \`${TEMP_DB}\`.\`${table}\` t;
SET FOREIGN_KEY_CHECKS=1;
"
}

method_pk_merge_upsert() {
  local table="$1"
  local pk_file
  local common_file
  local mutable_file
  local join_cond
  local update_assign
  local insert_cols
  local select_cols
  local pk_first

  pk_file="$(primary_key_file "${table}")"
  [ -s "${pk_file}" ] || return 1

  common_file="$(build_common_column_file "${table}")"
  [ -s "${common_file}" ] || return 1

  mutable_file="$(build_mutable_common_column_file "${table}")"
  join_cond="$(build_join_condition_from_file "${LIVE_DB}" "${table}" "l" "${TEMP_DB}" "${table}" "t" "${pk_file}")"
  update_assign="$(build_update_assignments_from_file "l" "t" "${mutable_file}")"
  insert_cols="$(build_column_list_from_file "${common_file}")"
  select_cols="$(build_select_list_from_file "t" "${common_file}")"
  pk_first="$(head -n1 "${pk_file}")"

  if [ -n "${update_assign}" ]; then
    exec_sql "${LIVE_DB}" "
UPDATE \`${table}\` l
JOIN \`${TEMP_DB}\`.\`${table}\` t
  ON ${join_cond}
SET ${update_assign};
"
  fi

  exec_sql "${LIVE_DB}" "
INSERT INTO \`${table}\` (${insert_cols})
SELECT ${select_cols}
FROM \`${TEMP_DB}\`.\`${table}\` t
LEFT JOIN \`${table}\` l
  ON ${join_cond}
WHERE l.\`${pk_first}\` IS NULL;
"
}

method_pk_insert_only() {
  local table="$1"
  local pk_file
  local common_file
  local join_cond
  local insert_cols
  local select_cols
  local pk_first

  pk_file="$(primary_key_file "${table}")"
  [ -s "${pk_file}" ] || return 1

  common_file="$(build_common_column_file "${table}")"
  [ -s "${common_file}" ] || return 1

  join_cond="$(build_join_condition_from_file "${LIVE_DB}" "${table}" "l" "${TEMP_DB}" "${table}" "t" "${pk_file}")"
  insert_cols="$(build_column_list_from_file "${common_file}")"
  select_cols="$(build_select_list_from_file "t" "${common_file}")"
  pk_first="$(head -n1 "${pk_file}")"

  exec_sql "${LIVE_DB}" "
INSERT INTO \`${table}\` (${insert_cols})
SELECT ${select_cols}
FROM \`${TEMP_DB}\`.\`${table}\` t
LEFT JOIN \`${table}\` l
  ON ${join_cond}
WHERE l.\`${pk_first}\` IS NULL;
"
}

run_method() {
  local method="$1"
  local table="$2"

  case "${method}" in
    exact_replace_dump_pipe) method_exact_replace_dump_pipe "${table}" ;;
    mapped_replace) method_mapped_replace "${table}" ;;
    pk_merge_upsert) method_pk_merge_upsert "${table}" ;;
    pk_insert_only) method_pk_insert_only "${table}" ;;
    *)
      echo "ERROR: Unknown method ${method}" >&2
      return 1
      ;;
  esac
}

is_do_not_import_table() {
  local table="$1"
  case "${table}" in
    ip_sessions|ip_login_log|ip_imports|ip_import_details|ip_versions)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_manual_review_table() {
  local table="$1"
  case "${table}" in
    ip_users|ip_user_custom|ip_user_clients)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_special_merge_table() {
  local table="$1"
  case "${table}" in
    ip_settings|ip_custom_fields)
      return 0
      ;;
  esac

  if printf '%s\n' "${table}" | grep -Eq '^ip_.*_custom$'; then
    return 0
  fi

  return 1
}

planned_action_for_auto_table() {
  local table="$1"
  local class
  class="$(printf '%s\n' "${TABLE_SCHEMA_CLASS[${table}]}" | awk 'NR==1 {print $1}')"

  case "${class}" in
    EXACT) printf '%s\n' "REPLACE_EXACT" ;;
    ADDITIVE_COMPATIBLE) printf '%s\n' "REPLACE_MAPPED" ;;
    *)
      if has_primary_key "${table}"; then
        printf '%s\n' "MERGE_BY_PK"
      else
        printf '%s\n' "MANUAL_REVIEW"
      fi
      ;;
  esac
}

policy_for_table() {
  local table="$1"

  if is_do_not_import_table "${table}"; then
    printf '%s\n' "DO_NOT_IMPORT"
  elif is_manual_review_table "${table}"; then
    printf '%s\n' "MANUAL_REVIEW"
  elif is_special_merge_table "${table}"; then
    printf '%s\n' "MERGE_SPECIAL"
  else
    printf '%s\n' "AUTO_RECONCILE"
  fi
}

plan_table() {
  local table="$1"
  local policy
  local schema_class
  local action
  local notes

  policy="$(policy_for_table "${table}")"
  schema_class="$(printf '%s\n' "${TABLE_SCHEMA_CLASS[${table}]}" | awk 'NR==1 {print $1}')"
  [ -n "${schema_class}" ] || schema_class="UNCLASSIFIED"

  case "${policy}" in
    DO_NOT_IMPORT)
      action="SKIP_RUNTIME_STATE"
      notes="runtime/log/import/version state belongs to the new live instance"
      ;;
    MANUAL_REVIEW)
      action="MANUAL_REVIEW"
      notes="security/ownership-sensitive table; not blindly imported"
      printf '%s\n' "${table}" >> "${MANUAL_REVIEW_TABLES_FILE}"
      ;;
    MERGE_SPECIAL)
      case "${table}" in
        ip_settings)
          action="MERGE_SETTINGS_BY_KEY"
          notes="environment-owned key/value settings; merge carefully by setting_key"
          ;;
        ip_custom_fields)
          action="MERGE_CUSTOM_FIELD_DEFS"
          notes="custom field definitions must preserve live schema and missing definitions"
          ;;
        *)
          action="MERGE_CUSTOM_VALUES"
          notes="custom values merged by owner id + field id"
          ;;
      esac
      ;;
    AUTO_RECONCILE)
      action="$(planned_action_for_auto_table "${table}")"
      case "${action}" in
        REPLACE_EXACT)
          notes="exact schema compatible"
          ;;
        REPLACE_MAPPED)
          notes="additive-compatible; shared columns only; live-only columns preserved"
          ;;
        MERGE_BY_PK)
          notes="schema drift prevents replace; merge by primary key using shared columns"
          ;;
        MANUAL_REVIEW)
          notes="no safe generic method available"
          printf '%s\n' "${table}" >> "${MANUAL_REVIEW_TABLES_FILE}"
          ;;
        *)
          notes="unexpected auto reconcile action"
          ;;
      esac
      ;;
    *)
      action="MANUAL_REVIEW"
      notes="unknown policy classification"
      printf '%s\n' "${table}" >> "${MANUAL_REVIEW_TABLES_FILE}"
      ;;
  esac

  TABLE_POLICY["${table}"]="${policy}"
  TABLE_NOTES["${table}"]="${notes}"

  record_policy "${table}" "${policy}" "${schema_class}" "${action}" "${notes}"
}

verify_settings_success() {
  local key
  while IFS= read -r key; do
    [ -n "${key}" ] || continue

    local temp_val
    local live_val

    temp_val="$(
      query_sql "${TEMP_DB}" "
SELECT setting_value
FROM ip_settings
WHERE CONVERT(setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci =
      CONVERT('$(sql_escape "${key}")' USING utf8mb4) COLLATE utf8mb4_unicode_ci;
"
    )"

    live_val="$(
      query_sql "${LIVE_DB}" "
SELECT setting_value
FROM ip_settings
WHERE CONVERT(setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci =
      CONVERT('$(sql_escape "${key}")' USING utf8mb4) COLLATE utf8mb4_unicode_ci;
"
    )"

    [ "${temp_val}" = "${live_val}" ] || return 1
  done < "${SETTINGS_SAFE_KEYS_FILE}"

  return 0
}

merge_ip_settings() {
  LIVE_BEFORE_COUNTS["ip_settings"]="$(table_row_count_or_dash "${LIVE_DB}" "ip_settings")"

  if ! table_exists "${TEMP_DB}" "ip_settings" || ! table_exists "${LIVE_DB}" "ip_settings"; then
    record_execution "ip_settings" "MERGE_SPECIAL" "SPECIAL" "MERGE_SETTINGS_BY_KEY" "-" "-" "WARNING_SKIPPED" "table not present in both DBs"
    return
  fi

  query_sql "${TEMP_DB}" "SELECT setting_key FROM ip_settings ORDER BY setting_key;" > "${SETTINGS_TEMP_KEYS_FILE}"
  query_sql "${LIVE_DB}" "SELECT setting_key FROM ip_settings ORDER BY setting_key;" > "${SETTINGS_LIVE_KEYS_FILE}"

  sort -u "${SETTINGS_TEMP_KEYS_FILE}" -o "${SETTINGS_TEMP_KEYS_FILE}"
  sort -u "${SETTINGS_LIVE_KEYS_FILE}" -o "${SETTINGS_LIVE_KEYS_FILE}"

  cat > "${SETTINGS_SKIP_KEYS_FILE}" <<'EOF'
cron_key
EOF

  : > "${SETTINGS_SAFE_KEYS_FILE}"

  while IFS= read -r key; do
    [ -n "${key}" ] || continue
    if grep -qx "${key}" "${SETTINGS_SKIP_KEYS_FILE}"; then
      continue
    fi
    printf '%s\n' "${key}" >> "${SETTINGS_SAFE_KEYS_FILE}"
  done < "${SETTINGS_TEMP_KEYS_FILE}"

  trim_file "${SETTINGS_SAFE_KEYS_FILE}"

  if [ "${DRY_RUN}" = "1" ]; then
    record_execution "ip_settings" "MERGE_SPECIAL" "SPECIAL" "MERGE_SETTINGS_BY_KEY" "insert_missing_then_update_existing" "-" "DRY_RUN" "planned only"
    return
  fi

  exec_sql "${LIVE_DB}" "
INSERT INTO ip_settings (setting_key, setting_value)
SELECT t.setting_key, t.setting_value
FROM \`${TEMP_DB}\`.ip_settings t
LEFT JOIN ip_settings l
  ON CONVERT(l.setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci =
     CONVERT(t.setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
WHERE l.setting_key IS NULL
  AND CONVERT(t.setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci <>
      CONVERT('cron_key' USING utf8mb4) COLLATE utf8mb4_unicode_ci;

UPDATE ip_settings l
JOIN \`${TEMP_DB}\`.ip_settings t
  ON CONVERT(l.setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci =
     CONVERT(t.setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
SET l.setting_value = t.setting_value
WHERE CONVERT(l.setting_key USING utf8mb4) COLLATE utf8mb4_unicode_ci <>
      CONVERT('cron_key' USING utf8mb4) COLLATE utf8mb4_unicode_ci;
"

  if verify_settings_success; then
    record_execution "ip_settings" "MERGE_SPECIAL" "SPECIAL" "MERGE_SETTINGS_BY_KEY" "insert_missing_then_update_existing" "insert_missing_then_update_existing" "SUCCESS" "settings merged and verified"
  else
    record_execution "ip_settings" "MERGE_SPECIAL" "SPECIAL" "MERGE_SETTINGS_BY_KEY" "insert_missing_then_update_existing" "insert_missing_then_update_existing" "FAILED_REQUIRES_REVIEW" "settings verification failed"
    printf '%s\n' "ip_settings" >> "${FAILED_TABLES_FILE}"
  fi
}

build_custom_table_columns() {
  local table="$1"
  local prefix

  prefix="${table#ip_}"
  prefix="${prefix%_custom}"

  CUSTOM_PK_COL="${prefix}_custom_id"
  CUSTOM_OWNER_ID_COL="${prefix}_id"
  CUSTOM_FIELD_ID_COL="${prefix}_custom_fieldid"
  CUSTOM_VALUE_COL="${prefix}_custom_fieldvalue"
}

restore_custom_field_definitions() {
  LIVE_BEFORE_COUNTS["ip_custom_fields"]="$(table_row_count_or_dash "${LIVE_DB}" "ip_custom_fields")"

  if ! table_exists "${TEMP_DB}" "ip_custom_fields" || ! table_exists "${LIVE_DB}" "ip_custom_fields"; then
    record_execution "ip_custom_fields" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_FIELD_DEFS" "-" "-" "WARNING_SKIPPED" "table not present in both DBs"
    return
  fi

  if [ "${DRY_RUN}" = "1" ]; then
    record_execution "ip_custom_fields" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_FIELD_DEFS" "merge_by_custom_field_id" "-" "DRY_RUN" "planned only"
    return
  fi

  exec_sql "${LIVE_DB}" "
INSERT INTO ip_custom_fields
(custom_field_id, custom_field_table, custom_field_label, custom_field_type, custom_field_location, custom_field_order)
SELECT
  t.custom_field_id,
  t.custom_field_table,
  t.custom_field_label,
  t.custom_field_type,
  t.custom_field_location,
  t.custom_field_order
FROM \`${TEMP_DB}\`.ip_custom_fields t
LEFT JOIN ip_custom_fields l
  ON l.custom_field_id = t.custom_field_id
WHERE l.custom_field_id IS NULL;

UPDATE ip_custom_fields l
JOIN \`${TEMP_DB}\`.ip_custom_fields t
  ON l.custom_field_id = t.custom_field_id
SET
  l.custom_field_table = t.custom_field_table,
  l.custom_field_label = t.custom_field_label,
  l.custom_field_type = t.custom_field_type,
  l.custom_field_location = t.custom_field_location,
  l.custom_field_order = t.custom_field_order;
"

  record_execution "ip_custom_fields" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_FIELD_DEFS" "merge_by_custom_field_id" "merge_by_custom_field_id" "SUCCESS" "custom field definitions merged"
}

verify_custom_table_success() {
  local table="$1"
  local owner_eq
  local field_eq
  local missing_count

  build_custom_table_columns "${table}"

  owner_eq="$(safe_equality_expr "${LIVE_DB}" "${table}" "l" "${TEMP_DB}" "${table}" "t" "${CUSTOM_OWNER_ID_COL}")"
  field_eq="$(safe_equality_expr "${LIVE_DB}" "${table}" "l" "${TEMP_DB}" "${table}" "t" "${CUSTOM_FIELD_ID_COL}")"

  missing_count="$(
    query_sql "${LIVE_DB}" "
SELECT COUNT(*)
FROM \`${TEMP_DB}\`.\`${table}\` t
LEFT JOIN \`${table}\` l
  ON ${owner_eq}
 AND ${field_eq}
WHERE t.\`${CUSTOM_VALUE_COL}\` IS NOT NULL
  AND TRIM(CAST(t.\`${CUSTOM_VALUE_COL}\` AS CHAR)) <> ''
  AND l.\`${CUSTOM_PK_COL}\` IS NULL;
"
  )"

  [ "${missing_count}" = "0" ]
}

migrate_custom_tables() {
  : > "${CUSTOM_TABLES_FILE}"
  grep -E '^ip_.*_custom$' "${TEMP_TABLES_FILE}" | grep -v '^ip_custom_fields$' | sort -u > "${CUSTOM_TABLES_FILE}" || true

  while IFS= read -r table <&3; do
    [ -n "${table}" ] || continue
    LIVE_BEFORE_COUNTS["${table}"]="$(table_row_count_or_dash "${LIVE_DB}" "${table}")"

    if ! table_exists "${LIVE_DB}" "${table}"; then
      record_execution "${table}" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_VALUES" "-" "-" "WARNING_SKIPPED" "custom table not present in live DB"
      continue
    fi

    build_custom_table_columns "${table}"

    if ! column_exists "${TEMP_DB}" "${table}" "${CUSTOM_PK_COL}" \
      || ! column_exists "${TEMP_DB}" "${table}" "${CUSTOM_OWNER_ID_COL}" \
      || ! column_exists "${TEMP_DB}" "${table}" "${CUSTOM_FIELD_ID_COL}" \
      || ! column_exists "${TEMP_DB}" "${table}" "${CUSTOM_VALUE_COL}" \
      || ! column_exists "${LIVE_DB}" "${table}" "${CUSTOM_PK_COL}" \
      || ! column_exists "${LIVE_DB}" "${table}" "${CUSTOM_OWNER_ID_COL}" \
      || ! column_exists "${LIVE_DB}" "${table}" "${CUSTOM_FIELD_ID_COL}" \
      || ! column_exists "${LIVE_DB}" "${table}" "${CUSTOM_VALUE_COL}"; then
      record_execution "${table}" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_VALUES" "-" "-" "FAILED_REQUIRES_REVIEW" "unsupported custom table shape"
      printf '%s\n' "${table}" >> "${FAILED_TABLES_FILE}"
      continue
    fi

    local owner_eq
    local field_eq
    owner_eq="$(safe_equality_expr "${LIVE_DB}" "${table}" "l" "${TEMP_DB}" "${table}" "t" "${CUSTOM_OWNER_ID_COL}")"
    field_eq="$(safe_equality_expr "${LIVE_DB}" "${table}" "l" "${TEMP_DB}" "${table}" "t" "${CUSTOM_FIELD_ID_COL}")"

    if [ "${DRY_RUN}" = "1" ]; then
      record_execution "${table}" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_VALUES" "upsert_owner_field" "-" "DRY_RUN" "planned only"
      continue
    fi

    exec_sql "${LIVE_DB}" "
UPDATE \`${table}\` l
JOIN \`${TEMP_DB}\`.\`${table}\` t
  ON ${owner_eq}
 AND ${field_eq}
SET l.\`${CUSTOM_VALUE_COL}\` = t.\`${CUSTOM_VALUE_COL}\`
WHERE t.\`${CUSTOM_VALUE_COL}\` IS NOT NULL
  AND TRIM(CAST(t.\`${CUSTOM_VALUE_COL}\` AS CHAR)) <> '';

INSERT INTO \`${table}\`
(\`${CUSTOM_OWNER_ID_COL}\`, \`${CUSTOM_FIELD_ID_COL}\`, \`${CUSTOM_VALUE_COL}\`)
SELECT
  t.\`${CUSTOM_OWNER_ID_COL}\`,
  t.\`${CUSTOM_FIELD_ID_COL}\`,
  t.\`${CUSTOM_VALUE_COL}\`
FROM \`${TEMP_DB}\`.\`${table}\` t
LEFT JOIN \`${table}\` l
  ON ${owner_eq}
 AND ${field_eq}
WHERE t.\`${CUSTOM_VALUE_COL}\` IS NOT NULL
  AND TRIM(CAST(t.\`${CUSTOM_VALUE_COL}\` AS CHAR)) <> ''
  AND l.\`${CUSTOM_PK_COL}\` IS NULL;
"

    if verify_custom_table_success "${table}"; then
      record_execution "${table}" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_VALUES" "upsert_owner_field" "upsert_owner_field" "SUCCESS" "custom values merged"
    else
      record_execution "${table}" "MERGE_SPECIAL" "SPECIAL" "MERGE_CUSTOM_VALUES" "upsert_owner_field" "upsert_owner_field" "FAILED_REQUIRES_REVIEW" "custom value verification failed"
      printf '%s\n' "${table}" >> "${FAILED_TABLES_FILE}"
    fi
  done 3< "${CUSTOM_TABLES_FILE}"
}

execute_auto_table() {
  local table="$1"
  local policy="${TABLE_POLICY[${table}]}"
  local schema_class
  local action
  local attempted_methods=""
  local winning_method=""
  local final_status="FAILED_REQUIRES_REVIEW"
  local notes="${TABLE_NOTES[${table}]}"
  local methods=()

  LIVE_BEFORE_COUNTS["${table}"]="$(table_row_count_or_dash "${LIVE_DB}" "${table}")"
  schema_class="$(printf '%s\n' "${TABLE_SCHEMA_CLASS[${table}]}" | awk 'NR==1 {print $1}')"
  action="$(planned_action_for_auto_table "${table}")"

  case "${action}" in
    REPLACE_EXACT) methods=("exact_replace_dump_pipe") ;;
    REPLACE_MAPPED) methods=("mapped_replace") ;;
    MERGE_BY_PK) methods=("pk_merge_upsert" "pk_insert_only") ;;
    MANUAL_REVIEW)
      record_execution "${table}" "${policy}" "${schema_class}" "${action}" "-" "-" "MANUAL_REVIEW" "${notes}"
      return
      ;;
    *)
      record_execution "${table}" "${policy}" "${schema_class}" "${action}" "-" "-" "FAILED_REQUIRES_REVIEW" "unknown auto action"
      printf '%s\n' "${table}" >> "${FAILED_TABLES_FILE}"
      return
      ;;
  esac

  if [ "${DRY_RUN}" = "1" ]; then
    record_execution "${table}" "${policy}" "${schema_class}" "${action}" "$(IFS=,; echo "${methods[*]}")" "-" "DRY_RUN" "planned only"
    return
  fi

  snapshot_live_table "${table}"

  local method
  local method_rc
  for method in "${methods[@]}"; do
    attempted_methods="${attempted_methods}${attempted_methods:+,}${method}"

    set +e
    run_method "${method}" "${table}"
    method_rc=$?
    set -e

    if [ "${method_rc}" -eq 0 ]; then
      case "${action}" in
        REPLACE_EXACT|REPLACE_MAPPED)
          if verify_replace_success "${table}"; then
            winning_method="${method}"
            final_status="SUCCESS"
            notes="verified by row count match"
            break
          fi
          ;;
        MERGE_BY_PK)
          if verify_pk_coverage_success "${table}"; then
            winning_method="${method}"
            final_status="SUCCESS"
            notes="verified by PK coverage"
            break
          fi
          ;;
      esac
    fi

    restore_live_table_snapshot "${table}"
  done

  if [ -n "${winning_method}" ]; then
    drop_live_table_snapshot "${table}"
  else
    restore_live_table_snapshot "${table}"
    drop_live_table_snapshot "${table}"
    printf '%s\n' "${table}" >> "${FAILED_TABLES_FILE}"
  fi

  record_execution "${table}" "${policy}" "${schema_class}" "${action}" "${attempted_methods:-"-"}" "${winning_method:-"-"}" "${final_status}" "${notes}"
}

echo "========================================"
echo "Checking database container"
echo "========================================"
compose up -d invoiceplane_db >/dev/null 2>&1
echo
echo "✅ invoiceplane_db is available"
echo

DB_CLIENT_CMD="$(db_client_cmd)"
DB_DUMP_CMD="$(db_dump_cmd)"

echo "========================================"
echo "Detecting database tools"
echo "========================================"
echo "✅ Client tool detected:"
echo "   ${DB_CLIENT_CMD}"
echo "✅ Dump tool detected:"
echo "   ${DB_DUMP_CMD}"
echo

LIVE_DB="$(db_exec 'printf "%s" "$MYSQL_DATABASE"')"
[ -n "${LIVE_DB}" ] || { echo "ERROR: Could not resolve MYSQL_DATABASE from invoiceplane_db" >&2; exit 1; }

MYSQL_ROOT_PASSWORD_VALUE="$(db_exec 'printf "%s" "$MYSQL_ROOT_PASSWORD"')"
[ -n "${MYSQL_ROOT_PASSWORD_VALUE}" ] || { echo "ERROR: Could not resolve MYSQL_ROOT_PASSWORD from invoiceplane_db" >&2; exit 1; }

TEMP_DB="invoiceplane_import_tmp"

echo "========================================"
echo "Waiting for MariaDB readiness"
echo "========================================"

READY=0
for i in $(seq 1 60); do
  if compose exec -T invoiceplane_db sh -lc \
    "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_CLIENT_CMD} -h 127.0.0.1 -P 3306 -u root -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1' >/dev/null 2>&1"; then
    READY=1
    break
  fi
  sleep 2
done

if [ "${READY}" -ne 1 ]; then
  echo "ERROR: MariaDB did not become ready in time" >&2
  exit 1
fi

echo "✅ MariaDB is accepting connections"
echo

echo "========================================"
echo "Preflight database admin check"
echo "========================================"
exec_sql "" "
DROP DATABASE IF EXISTS \`${TEMP_DB}\`;
CREATE DATABASE \`${TEMP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP DATABASE \`${TEMP_DB}\`;
"
echo "✅ Root privileges verified for temp DB create/drop"
echo

echo "========================================"
echo "InvoicePlane DB Import — RECONCILE ONLY"
echo "========================================"
echo
echo "Live database : ${LIVE_DB}"
echo "Temp database : ${TEMP_DB}"
echo "Mode          : $( [ "${DRY_RUN}" = "1" ] && echo "DRY RUN" || echo "LIVE EXECUTION" )"
echo
echo "Policy:"
echo "  - live schema must already exist"
echo "  - setup wizard must be completed first"
echo "  - runtime/session/import/version tables are not imported"
echo "  - shared business tables are schema-mapped into live"
echo "  - text joins are normalized for collation safety"
echo

if [ -z "${DUMP_FILE}" ]; then
  DEFAULT_DUMP_DIR="/docker/AAA_IMPORTANT_BACKUPS/"
  DUMP_FILE="${DEFAULT_DUMP_DIR}"
  read -e -r -p "Enter full path to old SQL dump: " -i "${DUMP_FILE}" DUMP_FILE
fi

[ -n "${DUMP_FILE}" ] || { echo "ERROR: No dump path provided" >&2; exit 1; }
[ -f "${DUMP_FILE}" ] || { echo "ERROR: Dump file not found: ${DUMP_FILE}" >&2; exit 1; }

echo "Using dump file:"
echo "  ${DUMP_FILE}"
echo

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${REPO_ROOT}/.backup"
BACKUP_FILE="${BACKUP_DIR}/backup-live-before-import-${TIMESTAMP}.sql"
WORK_DIR="${REPO_ROOT}/.invoiceplane-db-import"

mkdir -p "${BACKUP_DIR}" "${WORK_DIR}"

TEMP_TABLES_FILE="${WORK_DIR}/temp_tables.txt"
LIVE_TABLES_FILE="${WORK_DIR}/live_tables.txt"
SHARED_TABLES_FILE="${WORK_DIR}/shared_tables.txt"
TEMP_ONLY_FILE="${WORK_DIR}/temp_only_tables.txt"
LIVE_ONLY_FILE="${WORK_DIR}/live_only_tables.txt"
CUSTOM_TABLES_FILE="${WORK_DIR}/custom_tables.txt"

POLICY_REPORT_FILE="${WORK_DIR}/policy_report.tsv"
EXECUTION_REPORT_FILE="${WORK_DIR}/execution_report.tsv"
COLUMN_DIFF_REPORT_FILE="${WORK_DIR}/column_diff_report.tsv"
FAILED_TABLES_FILE="${WORK_DIR}/failed_tables.txt"
MANUAL_REVIEW_TABLES_FILE="${WORK_DIR}/manual_review_tables.txt"
SETTINGS_TEMP_KEYS_FILE="${WORK_DIR}/settings_temp_keys.txt"
SETTINGS_LIVE_KEYS_FILE="${WORK_DIR}/settings_live_keys.txt"
SETTINGS_SKIP_KEYS_FILE="${WORK_DIR}/settings_skip_keys.txt"
SETTINGS_SAFE_KEYS_FILE="${WORK_DIR}/settings_safe_keys.txt"

: > "${FAILED_TABLES_FILE}"
: > "${MANUAL_REVIEW_TABLES_FILE}"

printf 'table_name\tpolicy\tschema_class\tplanned_action\tnotes\n' > "${POLICY_REPORT_FILE}"
printf 'table_name\tpolicy\tschema_class\tplanned_action\tattempted_methods\twinning_method\tfinal_status\ttemp_row_count\tlive_row_count_before\tlive_row_count_after\tnotes\n' > "${EXECUTION_REPORT_FILE}"
printf 'table_name\tschema_class\ttemp_only_columns\tlive_only_columns\n' > "${COLUMN_DIFF_REPORT_FILE}"

if [ "${DRY_RUN}" = "1" ]; then
  echo "========================================"
  echo "DRY RUN"
  echo "========================================"
  echo "DRY RUN: skipping live DB backup"
  echo
else
  echo "========================================"
  echo "Backing up current live DB"
  echo "========================================"
  db_exec "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_DUMP_CMD} -h 127.0.0.1 -P 3306 -u root -p\"\$MYSQL_ROOT_PASSWORD\" --databases \"${LIVE_DB}\"" > "${BACKUP_FILE}"
  echo "✅ Live DB backup saved to:"
  echo "   ${BACKUP_FILE}"
  echo
fi

echo "========================================"
echo "Recreating temp DB"
echo "========================================"
exec_sql "" "
DROP DATABASE IF EXISTS \`${TEMP_DB}\`;
CREATE DATABASE \`${TEMP_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
"
echo "✅ Temp DB ready: ${TEMP_DB}"
echo

echo "========================================"
echo "Importing old dump into temp DB"
echo "========================================"
sed 's/^USE[[:space:]]\+`\\\?invoiceplane`\\\?;/USE `'"${TEMP_DB}"'`;/I' "${DUMP_FILE}" \
  | compose exec -T invoiceplane_db sh -lc \
      "unset MYSQL_HOST MYSQL_TCP_PORT; ${DB_CLIENT_CMD} -h 127.0.0.1 -P 3306 -u root -p\"\$MYSQL_ROOT_PASSWORD\" \"${TEMP_DB}\""
echo "✅ Dump imported into temp DB"
echo

query_sql "${TEMP_DB}" "SHOW TABLES;" > "${TEMP_TABLES_FILE}"
query_sql "${LIVE_DB}" "SHOW TABLES;" > "${LIVE_TABLES_FILE}"

sort -u "${TEMP_TABLES_FILE}" -o "${TEMP_TABLES_FILE}"
sort -u "${LIVE_TABLES_FILE}" -o "${LIVE_TABLES_FILE}"

comm -12 "${TEMP_TABLES_FILE}" "${LIVE_TABLES_FILE}" > "${SHARED_TABLES_FILE}" || true
comm -23 "${TEMP_TABLES_FILE}" "${LIVE_TABLES_FILE}" > "${TEMP_ONLY_FILE}" || true
comm -13 "${TEMP_TABLES_FILE}" "${LIVE_TABLES_FILE}" > "${LIVE_ONLY_FILE}" || true

echo "========================================"
echo "Validating live InvoicePlane schema"
echo "========================================"

SHARED_COUNT="$(wc -l < "${SHARED_TABLES_FILE}" | tr -d ' ')"
TEMP_ONLY_COUNT="$(wc -l < "${TEMP_ONLY_FILE}" | tr -d ' ')"
LIVE_ONLY_COUNT="$(wc -l < "${LIVE_ONLY_FILE}" | tr -d ' ')"

echo "Shared tables     : ${SHARED_COUNT}"
echo "Temp-only tables  : ${TEMP_ONLY_COUNT}"
echo "Live-only tables  : ${LIVE_ONLY_COUNT}"
echo

REQUIRED_TABLES=(
  ip_clients
  ip_invoices
  ip_invoice_items
  ip_settings
)

MISSING_REQUIRED=0
for t in "${REQUIRED_TABLES[@]}"; do
  if ! grep -qx "${t}" "${LIVE_TABLES_FILE}"; then
    echo "❌ Missing required table in live DB: ${t}"
    MISSING_REQUIRED=1
  fi
done

if [ "${SHARED_COUNT}" -eq 0 ] && [ "${TEMP_ONLY_COUNT}" -gt 0 ] && [ "${LIVE_ONLY_COUNT}" -eq 0 ]; then
  echo
  echo "❌ Live InvoicePlane schema not initialized."
  echo "Run the setup wizard first, confirm the live app works, then rerun."
  echo
  exit 1
fi

if [ "${MISSING_REQUIRED}" -eq 1 ]; then
  echo
  echo "❌ Live InvoicePlane schema incomplete or not created by setup wizard."
  echo
  exit 1
fi

echo "✅ Live schema validation passed"
echo

echo "========================================"
echo "Classifying shared tables"
echo "========================================"

while IFS= read -r table <&3; do
  [ -n "${table}" ] || continue

  result="$(classify_table_schema "${table}")"
  TABLE_SCHEMA_CLASS["${table}"]="${result}"

  printf '%s\n' "${result}" > "${WORK_DIR}/schema-detail-${table}.txt"

  plan_table "${table}"
  record_column_diff "${table}" "$(printf '%s\n' "${result}" | awk 'NR==1{print $1}')"
done 3< "${SHARED_TABLES_FILE}"

echo "========================================"
echo "Planning summary"
echo "========================================"
echo "Shared tables     : ${SHARED_COUNT}"
echo "Temp-only tables  : ${TEMP_ONLY_COUNT}"
echo "Live-only tables  : ${LIVE_ONLY_COUNT}"
echo
echo "Policies:"
awk -F '\t' 'NR>1 {count[$2]++} END {for (k in count) printf "  %-22s %s\n", k, count[k]}' "${POLICY_REPORT_FILE}" | sort
echo
echo "Policy report:"
echo "  ${POLICY_REPORT_FILE}"
echo "Column diff report:"
echo "  ${COLUMN_DIFF_REPORT_FILE}"
echo "Temp-only tables report:"
echo "  ${TEMP_ONLY_FILE}"
echo "Live-only tables report:"
echo "  ${LIVE_ONLY_FILE}"
echo "Manual review tables report:"
echo "  ${MANUAL_REVIEW_TABLES_FILE}"
echo

if [ "${DRY_RUN}" = "1" ]; then
  echo "========================================"
  echo "DRY RUN"
  echo "========================================"
  echo "DRY RUN: no live changes applied"
  echo
else
  if ! prompt_yes_no "Run full InvoicePlane reconcile now?"; then
    echo "Cancelled before live execution."
    exit 0
  fi

  echo
  echo "========================================"
  echo "Executing live reconcile"
  echo "========================================"
fi

while IFS= read -r table <&3; do
  [ -n "${table}" ] || continue

  policy="${TABLE_POLICY[${table}]}"
  schema_class="$(printf '%s\n' "${TABLE_SCHEMA_CLASS[${table}]}" | awk 'NR==1{print $1}')"
  planned_action="$(awk -F '\t' -v t="${table}" 'NR>1 && $1==t {print $4}' "${POLICY_REPORT_FILE}" | tail -n1)"
  LIVE_BEFORE_COUNTS["${table}"]="$(table_row_count_or_dash "${LIVE_DB}" "${table}")"

  case "${policy}" in
    DO_NOT_IMPORT)
      record_execution "${table}" "${policy}" "${schema_class}" "${planned_action}" "-" "-" "$( [ "${DRY_RUN}" = "1" ] && printf DRY_RUN || printf WARNING_SKIPPED )" "${TABLE_NOTES[${table}]}"
      ;;
    MANUAL_REVIEW)
      record_execution "${table}" "${policy}" "${schema_class}" "${planned_action}" "-" "-" "MANUAL_REVIEW" "${TABLE_NOTES[${table}]}"
      ;;
    MERGE_SPECIAL)
      case "${table}" in
        ip_settings)
          echo "→ processing special merge: ${table}"
          merge_ip_settings
          ;;
        ip_custom_fields)
          echo "→ processing special merge: ${table}"
          restore_custom_field_definitions
          ;;
        *)
          :
          ;;
      esac
      ;;
    AUTO_RECONCILE)
      echo "→ processing auto reconcile: ${table} [${planned_action}]"
      execute_auto_table "${table}"
      ;;
    *)
      record_execution "${table}" "UNKNOWN" "${schema_class}" "UNKNOWN" "-" "-" "FAILED_REQUIRES_REVIEW" "unknown policy at execution time"
      printf '%s\n' "${table}" >> "${FAILED_TABLES_FILE}"
      ;;
  esac
done 3< "${SHARED_TABLES_FILE}"

echo "→ processing special merge: ip_*_custom"
migrate_custom_tables

SUCCESS_COUNT="$(awk -F '\t' 'NR>1 && $7=="SUCCESS" {c++} END {print c+0}' "${EXECUTION_REPORT_FILE}")"
WARNING_COUNT="$(awk -F '\t' 'NR>1 && ($7=="WARNING_SKIPPED") {c++} END {print c+0}' "${EXECUTION_REPORT_FILE}")"
MANUAL_COUNT="$(awk -F '\t' 'NR>1 && $7=="MANUAL_REVIEW" {c++} END {print c+0}' "${EXECUTION_REPORT_FILE}")"
FAILED_COUNT="$(awk -F '\t' 'NR>1 && $7=="FAILED_REQUIRES_REVIEW" {c++} END {print c+0}' "${EXECUTION_REPORT_FILE}")"
DRY_COUNT="$(awk -F '\t' 'NR>1 && $7=="DRY_RUN" {c++} END {print c+0}' "${EXECUTION_REPORT_FILE}")"

echo
echo "========================================"
echo "Exit summary"
echo "========================================"
echo "Mode                 : $( [ "${DRY_RUN}" = "1" ] && echo "DRY RUN" || echo "LIVE EXECUTION" )"
if [ "${DRY_RUN}" = "1" ]; then
  echo "Live DB backup       : skipped in dry-run mode"
else
  echo "Live DB backup       : ${BACKUP_FILE}"
fi
echo "Temp DB              : ${TEMP_DB}"
echo "Policy report        : ${POLICY_REPORT_FILE}"
echo "Execution report     : ${EXECUTION_REPORT_FILE}"
echo "Column diff report   : ${COLUMN_DIFF_REPORT_FILE}"
echo "Temp-only tables     : ${TEMP_ONLY_FILE}"
echo "Live-only tables     : ${LIVE_ONLY_FILE}"
echo "Manual review tables : ${MANUAL_REVIEW_TABLES_FILE}"
echo "Failed tables        : ${FAILED_TABLES_FILE}"
echo
echo "Final statuses:"
printf '  %-22s %s\n' "SUCCESS" "${SUCCESS_COUNT}"
printf '  %-22s %s\n' "WARNING_SKIPPED" "${WARNING_COUNT}"
printf '  %-22s %s\n' "MANUAL_REVIEW" "${MANUAL_COUNT}"
printf '  %-22s %s\n' "FAILED_REQUIRES_REVIEW" "${FAILED_COUNT}"
printf '  %-22s %s\n' "DRY_RUN" "${DRY_COUNT}"
echo

if [ "${DRY_RUN}" = "1" ]; then
  echo "DRY RUN: no live changes applied"
elif [ "${FAILED_COUNT}" -gt 0 ]; then
  echo "One or more tables require review."
  exit 1
fi

echo "Done."

