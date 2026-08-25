#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env (gitignored) — copy .env.example to .env and configure
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  echo "[!] .env not found. Copy .env.example to .env and configure." >&2
  exit 1
fi

# Resolve sync connection — allow SYNC_MYSQL_* overrides, otherwise reuse MYSQL_* (docker) vars
SYNC_HOST="${SYNC_MYSQL_HOST:-${MYSQL_HOST:-127.0.0.1}}"
SYNC_PORT="${SYNC_MYSQL_PORT:-${MYSQL_PORT:-3308}}"
SYNC_USER="${SYNC_MYSQL_USER:-${MYSQL_USER:?Set MYSQL_USER in .env}}"
SYNC_PASS="${SYNC_MYSQL_PASSWORD:-${SYNC_MYSQL_PASS:-${MYSQL_PASSWORD:-${MYSQL_PASS:-}}}}"
if [[ -z "${SYNC_PASS:-}" ]]; then
  echo "[!] Set MYSQL_PASSWORD (or SYNC_MYSQL_PASSWORD) in .env" >&2
  exit 1
fi
SYNC_DB="${SYNC_MYSQL_DB:-${MYSQL_DB:?Set MYSQL_DB in .env}}"

TMP_DIR="${TMP_DIR:-./kodi_db_tmp}"
ADB_TARGET="${ADB_TARGET:?Set ADB_TARGET in .env}"
KODI_REMOTE_DB_PATTERN="${KODI_REMOTE_DB_PATTERN:-/sdcard/Android/data/org.xbmc.kodi/files/.kodi/userdata/Database/MyVideos*.db}"
SQLITE_DB_FILENAME="${SQLITE_DB_FILENAME:-}"

mkdir -p "$TMP_DIR"
# Work inside TMP_DIR but keep paths absolute via SCRIPT_DIR
pushd "$TMP_DIR" >/dev/null

rm -f ./*.db

if ! command -v adb >/dev/null 2>&1; then
  echo "[!] adb not found in PATH" >&2
  exit 1
fi

adb connect "$ADB_TARGET"

# Pull all remote DBs
# shellcheck disable=SC2016
adb shell "ls $KODI_REMOTE_DB_PATTERN" | tr -d '\r' | xargs -n1 adb pull || {
  echo "[!] adb pull failed" >&2
  exit 1
}

# Resolve SQLite DB to feed to update-db.py
SQLITE_PATH=""
if [[ -n "$SQLITE_DB_FILENAME" ]]; then
  SQLITE_PATH="$SCRIPT_DIR/$TMP_DIR/$SQLITE_DB_FILENAME"
  if [[ ! -f "$SQLITE_PATH" ]]; then
    echo "[!] Expected SQLite DB not found: $SQLITE_PATH" >&2
    echo "    Available:" >&2
    ls -1 ./*.db >&2 || true
    exit 1
  fi
else
  # Pick newest MyVideos*.db if no explicit filename
  SQLITE_PATH="$(ls -t ./*.db 2>/dev/null | head -n1 || true)"
  if [[ -z "$SQLITE_PATH" ]]; then
    echo "[!] No .db files pulled" >&2
    exit 1
  fi
  SQLITE_PATH="$SCRIPT_DIR/$TMP_DIR/$(basename "$SQLITE_PATH")"
fi

popd >/dev/null

# Run sync — forward any extra args (e.g. --dry-run --search "...")
python3 "$SCRIPT_DIR/update-db.py" \
  --sqlite "$SQLITE_PATH" \
  --mysql-host "$SYNC_HOST" \
  --mysql-port "$SYNC_PORT" \
  --mysql-user "$SYNC_USER" \
  --mysql-pass "$SYNC_PASS" \
  --mysql-db "$SYNC_DB" \
  "$@"

# Cleanup
rm -f "$TMP_DIR"/*.db
rmdir "$TMP_DIR" 2>/dev/null || rm -rf "$TMP_DIR"
echo "Done."
