# Hytale (Flux-Friendly)

This folder contains a small wrapper image to run the **Hytale Dedicated Server** in a way that fits Flux conventions:

- Persists everything under `/data` (use `g:/data` on Flux for primary/standby + Syncthing replication).
- Exposes UDP port `5520` by default (Hytale uses QUIC over UDP).
- Supports a Flux-friendly authentication flow (OAuth device code) that can persist tokens under `/data/auth` for failover/restarts.
- Provides a **file-based console input** so you can still trigger `/auth login device` without an interactive TTY.

This image does **not** bundle any Hytale server files. You must download them using the official tooling (or provide them yourself).

## Docker image

Published image:

```bash
docker pull littlestache/hytale-flux:latest
```

Use `littlestache/hytale-flux:latest` as the `repotag` in Flux specs (or pin to a specific tag if you publish one).

## Build (local)

```bash
docker build -t hytale-flux:local ./Gaming/hytale
```

If your Docker setup has permission issues writing to `~/.docker` (e.g. buildx activity), you can use a local config dir:

```bash
DOCKER_CONFIG=$PWD/.tmp_dockerconfig docker build -t hytale-flux:local ./Gaming/hytale
```

## Run (local)

Create a persistent data directory:

```bash
mkdir -p ./hytale-data
```

### Option A: Auto-download (linux/amd64 only)

The image includes the official `hytale-downloader` for **linux/amd64** builds. On first start it will print a device-login URL + code and wait for you to authorize in your browser.

```bash
docker run --rm -it \
  -p 5520:5520/udp \
  -v "$PWD/hytale-data:/data" \
  -e HYTALE_AUTO_DOWNLOAD=1 \
  hytale-flux:local
```

If the download succeeds but extraction fails for any reason, the downloaded `/data/game.zip` is reused on the next start (so you don’t have to re-download 1.4GB).

### Option B: Manual files

Place these into your `./hytale-data` directory:

- `Server/` (folder)
- `Assets.zip` (file)

Then run:

```bash
docker run --rm -it \
  -p 5520:5520/udp \
  -v "$PWD/hytale-data:/data" \
  hytale-flux:local
```

## Configuration (env vars)

Core:

- `HYTALE_BIND` (default: `0.0.0.0:5520`) → `--bind`
- `HYTALE_PORT` (optional) → convenience override for `HYTALE_BIND` (binds `0.0.0.0:<port>`)
- `HYTALE_AUTH_MODE` (`authenticated` or `offline`) → `--auth-mode`
- `JAVA_OPTS` (default: `-Xms1G -Xmx4G`) → JVM flags
- `HYTALE_SERVER_NAME` (optional) → convenience wrapper that patches `config.json` (key defaults to `ServerName`)
- `HYTALE_SERVER_NAME_CONFIG_KEY` (default: `ServerName`) → override which `config.json` key is set by `HYTALE_SERVER_NAME`

Backups:

- `HYTALE_BACKUP` (`1`/`0`) → `--backup`
- `HYTALE_BACKUP_DIR` (default: `/data/backups`) → `--backup-dir` (created if backups enabled)
- `HYTALE_BACKUP_FREQUENCY` (minutes) → `--backup-frequency`

Plugins / ops:

- `HYTALE_ACCEPT_EARLY_PLUGINS` (`1`/`0`) → `--accept-early-plugins`
- `HYTALE_ALLOW_OP` (`1`/`0`) → `--allow-op`

Console input:

- `HYTALE_CONSOLE_MODE` (`file` or `none`, default `file`)
- `HYTALE_CONSOLE_FILE` (default: `/data/console.commands`)
- `HYTALE_CONSOLE_CLEAR_ON_START` (`1`/`0`, default `1`) clears `HYTALE_CONSOLE_FILE` at startup to avoid replaying old commands
- `HYTALE_STARTUP_COMMANDS` (optional) sends startup console commands on container start (supports `\n` separators)
- `HYTALE_STARTUP_COMMANDS_APPLY_MODE` (`once` or `always`, default `once`)

Downloader (optional):

- `HYTALE_AUTO_DOWNLOAD` (`1`/`0`, default `0`) runs the official downloader if server files are missing (linux/amd64 only)
- `HYTALE_AUTO_UPDATE` (`1`/`0`, default `0`) downloads and applies the latest release on container start (linux/amd64 only)
- `HYTALE_KEEP_DOWNLOAD_ARCHIVE` (`1`/`0`, default `0`) keeps `/data/game.zip` and extraction temp dir (otherwise removed to save disk)
- `HYTALE_PATCHLINE` (default: `release`) passed to downloader as `-patchline`
- `HYTALE_UPDATE_SKIP_PATTERNS` (default: `universe/**,logs/**,mods/**,.cache/**,*.json`) glob list of paths to skip when applying an update

Advanced:

- `HYTALE_EXTRA_ARGS` (string) appended to the server args (whitespace-split; no shell quoting)
- `HYTALE_SERVER_DIR`, `HYTALE_ASSETS_PATH`, `HYTALE_JAR_PATH` to override file locations under `/data`
- `HYTALE_RUN_MODE` (`server`, `auth`, `auth-status`, default `server`)

Performance / storage:

- `HYTALE_EPHEMERAL_CACHE` (`1`/`0`, default `0`) moves the server `.cache/` directory to a non-persistent location to reduce synced data
- `HYTALE_CACHE_DIR` (default: `/tmp/hytale-cache`) cache location when `HYTALE_EPHEMERAL_CACHE=1`

### Auth helper (recommended on Flux)

If you set `HYTALE_AUTH_AUTO=1`, the container will:

1. Start an OAuth device-login flow (prints URL + code in logs).
2. Persist OAuth tokens and selected profile under `/data/auth/state.json`.
3. Create/refresh a game session token on boot and export it to the server process.

Env vars:

- `HYTALE_AUTH_AUTO` (`1`/`0`, default `0`)
- `HYTALE_AUTH_STATE_DIR` (default: `/data/auth`)
- `HYTALE_AUTH_CLIENT_ID` (default: `hytale-server`)
- Profile selection (only needed if your account has multiple profiles):
  - `HYTALE_AUTH_PROFILE_UUID`
  - `HYTALE_AUTH_PROFILE_USERNAME`

One-shot commands:

- Run auth flow and exit: set `HYTALE_RUN_MODE=auth`
- Inspect state: set `HYTALE_RUN_MODE=auth-status`

If you also use `HYTALE_AUTO_DOWNLOAD=1`, the official downloader stores credentials at `/data/.hytale-downloader-credentials.json`, and the auth helper will reuse the saved `refresh_token` when possible (so you don’t have to complete device auth twice).

Security note: tokens stored under `/data` may be accessible to infrastructure operators; treat `/data/auth/state.json` as sensitive.

### Config file overrides (`config.json`)

Hytale stores most “server settings” in `config.json` alongside `HytaleServer.jar`. This image can apply a JSON patch to that file **before** starting the server:

- `HYTALE_CONFIG_PATH` (default: `/data/Server/config.json`) override location
- `HYTALE_CONFIG_ENV_PREFIX` (default: `HYTALE_CFG__`) enables “one env var per setting” patches
- `HYTALE_CONFIG_MODE` (`merge` or `replace`, default `merge`)
- `HYTALE_CONFIG_APPLY_MODE` (`always` or `once`, default `always`)
- Provide the patch via one of:
  - `HYTALE_CONFIG_JSON` (raw JSON string)
  - `HYTALE_CONFIG_JSON_B64` (base64-encoded JSON)
  - `HYTALE_CONFIG_JSON_FILE` (path to a JSON file, e.g. `/data/config.patch.json`)
- `HYTALE_CONFIG_ALLOW_CREATE` (`1`/`0`, default `0`): if `config.json` doesn’t exist yet, allow creating it when using `merge` mode

You can also set individual settings as env vars, without writing JSON, using the prefix:

```bash
# Sets: { "ServerName": "My Server", "Limits": { "MaxPlayers": 20 } }
-e HYTALE_CFG__ServerName="My Server" \
-e HYTALE_CFG__Limits__MaxPlayers=20
```

Notes:

- You’ll need the actual key names from Hytale’s generated `config.json` (run once, then inspect `/data/Server/config.json`).
- The patch happens on container start; manual edits while the server is running can be overwritten by the server (per the Hytale server manual).

### Other JSON files (`whitelist.json`, `permissions.json`, `bans.json`)

This wrapper can also write/patch other server JSON files before boot.

These default to **replace** + **apply once** (to avoid overwriting runtime changes), and are schema-agnostic: you supply the exact JSON you want.

- `HYTALE_WHITELIST_PATH` (default: `/data/Server/whitelist.json`)
- `HYTALE_WHITELIST_MODE` (`merge` or `replace`, default `replace`)
- `HYTALE_WHITELIST_APPLY_MODE` (`always` or `once`, default `once`)
- `HYTALE_WHITELIST_ALLOW_CREATE` (`1`/`0`, default `1`)
- `HYTALE_WHITELIST_JSON`, `HYTALE_WHITELIST_JSON_B64`, `HYTALE_WHITELIST_JSON_FILE`

Same pattern for:

- `HYTALE_PERMISSIONS_*` (targets `/data/Server/permissions.json`)
- `HYTALE_BANS_*` (targets `/data/Server/bans.json`)

## Authentication on Flux (fallback via console file)

The container reads console commands from a file:

- `/data/console.commands`

To start device auth, append:

```bash
echo "/auth login device" >> /data/console.commands
```

On Flux you can do the same via `POST /apps/appexec` by running an `echo >> /data/console.commands` inside the container, then watch `GET /apps/applog/<appname>` for the device URL + code.

## Flux v8 compose component (example)

Use `g:/data` so the world/config/auth state persists and is replicated to standby nodes:

```json
{
  "name": "server",
  "description": "Hytale dedicated server",
  "repotag": "littlestache/hytale-flux:latest",
  "ports": [5520],
  "containerPorts": [5520],
  "domains": [""],
  "environmentParameters": [
    "HYTALE_BIND=0.0.0.0:5520",
    "HYTALE_AUTH_MODE=authenticated",
    "HYTALE_AUTH_AUTO=1",
    "JAVA_OPTS=-Xms2G -Xmx6G"
  ],
  "commands": [],
  "containerData": "g:/data",
  "cpu": 4,
  "ram": 8000,
  "hdd": 20,
  "repoauth": ""
}
```
