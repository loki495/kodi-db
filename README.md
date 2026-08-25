# kodi-db

Central MariaDB for Kodi + sync of watched/resume state from an Nvidia Shield (SQLite) into MySQL.

- **Docker:** `docker-compose.yml` runs `mariadb:10.6` on `3308:3306` with data in `./data` (gitignored).
- **Sync:** `update-db.py` copies `files.playCount` and `bookmark` (resume points) from Shield's `MyVideos*.db` (SQLite) to the shared MySQL library, matched by `strFilename`. Optional `--search` filters by filename, `--dry-run` previews.
- **Pull flow:** `pull-and-update.sh` ADB-pulls `MyVideos*.db` from Shield into a temp dir and invokes `update-db.py`.

All credentials/paths are env-driven via `.env` (gitignored). Copy `.env.example` to `.env`.

## Requirements

- Docker + Compose v2
- Python 3 + `pymysql` (`pip install pymysql` or via your env)
- `adb` (Android platform-tools) for `pull-and-update.sh`

## Setup

```bash
cp .env.example .env
# edit .env — set passwords, hosts, ADB_TARGET, etc.
docker compose up -d
docker compose logs -f kodi-db
```

`.env` is loaded automatically by `docker compose` for interpolation and by both scripts (`pull-and-update.sh` via `source`, `update-db.py` via its built-in `.env` loader — no `python-dotenv` needed).

## Configuration (.env)

See `.env.example` for all variables:

| Var | Purpose |
|-----|---------|
| `MYSQL_ROOT_PASSWORD` `MYSQL_DATABASE` `MYSQL_USER` `MYSQL_PASSWORD` `MYSQL_PORT` | Docker MariaDB |
| `MYSQL_HOST` `MYSQL_DB` | Sync target for `update-db.py` (defaults to docker DB) |
| `SYNC_MYSQL_HOST` etc. | Optional overrides if sync target differs from docker DB |
| `ADB_TARGET` | `host:port` for `adb connect` |
| `KODI_REMOTE_DB_PATTERN` | Remote glob on Shield |
| `SQLITE_DB_FILENAME` | Expected file after pull; if empty, newest `MyVideos*.db` is used |
| `TMP_DIR` | Temp dir for pulls (`./kodi_db_tmp`, gitignored) |

`docker-compose.yml` uses `${VAR}` with defaults (`MYSQL_DATABASE:-kodi`, `MYSQL_PORT:-3308`). `update-db.py` accepts CLI args that override env.

## Usage

### Standalone sync (no ADB)

```bash
# env-driven — no args needed if .env is configured
python3 update-db.py --dry-run
python3 update-db.py --search "mandalorian" --dry-run

# explicit CLI overrides env
python3 update-db.py \
  --sqlite /path/to/MyVideos131.db \
  --mysql-host 127.0.0.1 --mysql-port 3308 \
  --mysql-user kodi --mysql-pass secret --mysql-db MyVideos121
```

### Full pull + sync from Shield

```bash
./pull-and-update.sh              # uses .env, cleans up temp dir
./pull-and-update.sh --dry-run    # preview only
./pull-and-update.sh --search "dune" --dry-run
```

The script: loads `.env`, `adb connect $ADB_TARGET`, `adb shell ls $KODI_REMOTE_DB_PATTERN | xargs adb pull`, then calls `update-db.py` with the resolved SQLite path.

### Kodi clients

Point Kodi to MySQL in `advancedsettings.xml` using the same `MYSQL_*` host/user/pass and `MyVideos121` (or your version).

## Project layout

```
.
├── docker-compose.yml   # mariadb:10.6, env-interpolated
├── update-db.py         # SQLite → MySQL sync + search helpers
├── pull-and-update.sh   # ADB pull wrapper (sources .env)
├── .env.example         # template (commit)
├── .env                 # real values (gitignored)
└── data/                # MariaDB data (gitignored)
```

## Notes

- `data/`, `.env`, `kodi_db_tmp/` and `*.db` are gitignored.
- `docker-compose.yml:command` is a service-level `command`, not an env var (fixed from original).
- `pull-and-update.sh` no longer `cd`s to a hardcoded path; it resolves `SCRIPT_DIR`.
