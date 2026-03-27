#!/bin/zsh
set -euo pipefail

find_repo_root() {
  local start_dir="${1:-$PWD}"
  local dir

  dir="$(cd "$start_dir" && pwd)"

  while [ "$dir" != "/" ]; do
    if [ -f "$dir/docker-compose.yml" ] && [ -d "$dir/docker" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" && pwd)"
REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")" || {
  echo "ERROR: Could not locate repo root from ${SCRIPT_DIR}"
  exit 1
}

cd "$REPO_ROOT"
echo "Using repo root: $REPO_ROOT"

if [ ! -f .env ]; then
  echo "ERROR: Missing .env"
  exit 1
fi

RED=$'\033[1;31m'
YELLOW=$'\033[1;33m'
GREEN=$'\033[1;32m'
RESET=$'\033[0m'

CONFIRM_TOKEN="${DEV_RESET_CONFIRM_TOKEN:-DESTROY}"
FORCE_RESET="${DEV_RESET_FORCE:-0}"

echo
echo "${RED}================================================================${RESET}"
echo "${RED}DESTRUCTIVE ACTION: DEV RESET INSTALL${RESET}"
echo "${RED}================================================================${RESET}"
echo "${YELLOW}This will stop the stack and reset this project back toward a new-install state.${RESET}"
echo
echo "The reset will modify or remove local install state including:"
echo "  - mariadb/"
echo "  - data/finalize/"
echo "  - DISABLE_SETUP in .env"
echo "  - SETUP_COMPLETED in .env"
echo "  - ENCRYPTION_KEY in .env"
echo "  - ENCRYPTION_CIPHER in .env"
echo
echo "${RED}If you have local MariaDB data you care about, stop now.${RESET}"
echo "${RED}This is not a casual cleanup helper.${RESET}"
echo

if [ "$FORCE_RESET" != "1" ]; then
  printf "Type %s to continue: " "$CONFIRM_TOKEN"
  read typed_token
  if [ "$typed_token" != "$CONFIRM_TOKEN" ]; then
    echo
    echo "Aborted."
    exit 1
  fi
else
  echo "${YELLOW}DEV_RESET_FORCE=1 detected; skipping interactive confirmation.${RESET}"
fi

if command -v sudo >/dev/null 2>&1; then
  sudo -v
fi

echo
echo "${YELLOW}Stopping existing stack...${RESET}"
docker compose down --remove-orphans

python3 - <<'PY'
from pathlib import Path

env = Path(".env")
text = env.read_text()

def replace_or_append(text: str, key: str, value: str) -> str:
    lines = text.splitlines()
    replaced = False
    for i, line in enumerate(lines):
        if line.startswith(f"{key}="):
            lines[i] = f"{key}={value}"
            replaced = True
    if not replaced:
        lines.append(f"{key}={value}")
    return "\n".join(lines) + "\n"

text = replace_or_append(text, "DISABLE_SETUP", "false")
text = replace_or_append(text, "SETUP_COMPLETED", "false")
text = replace_or_append(text, "ENCRYPTION_KEY", "")
text = replace_or_append(text, "ENCRYPTION_CIPHER", "")
env.write_text(text)
PY

echo
echo "${YELLOW}Removing mariadb/ and data/finalize/...${RESET}"
if command -v sudo >/dev/null 2>&1; then
  sudo rm -rf mariadb data/finalize
else
  rm -rf mariadb data/finalize
fi

mkdir -p mariadb data/finalize data/logs
printf '%s\n' '{"state":"idle","message":"Waiting for finalize request."}' > data/finalize/status.json
: > data/finalize/finalizer.log

echo
echo "${GREEN}Handing off to ./bin/up.sh with full rebuild...${RESET}"
echo

UP_BUILD_MODE=rebuild ./bin/up.sh
