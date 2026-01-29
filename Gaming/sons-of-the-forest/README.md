# Sons of the Forest Dedicated Server (Flux-ready)

Marketplace-ready, Flux-friendly Docker image for the **Sons of the Forest** dedicated server:

- Installs/updates via **SteamCMD** (Steam appid `2465200`)
- Runs the **Windows-only** server on **linux/amd64** using **Wine + Xvfb**
- Flux-friendly persistence split:
  - `/data` → large **local** cache (Steam install + SteamCMD cache) (recommended: Flux non-synced volume)
  - `/config` → **config + saves** (recommended: Flux synced `g:/config`)

This image does **not** ship any proprietary server files; everything is pulled via SteamCMD at runtime.

## Ports

Default ports (UDP):

- `8766/udp` — Game port (`SOTF_GAME_PORT`)
- `27016/udp` — Query port (`SOTF_QUERY_PORT`)
- `9700/udp` — Blob sync port (`SOTF_BLOB_SYNC_PORT`)

## Volumes

- `/data` → Steam install + SteamCMD cache (large; safe to keep non-synced on Flux)
- `/config` → `dedicatedserver.cfg`, `ownerswhitelist.txt`, and save data (recommended to sync on Flux)

## Recommended host specs (quick guidance)

Real-world resource use varies heavily by world age, AI activity, and player count. As a starting point for a public server:

- CPU: **6 vCPU** recommended
- RAM: **16 GB** recommended
- Disk: **40 GB** recommended for the server + growth (mods/logs/backups)

The included `flux-spec.json` matches this baseline (6 CPU / 16 GB RAM, plus a 40 GB local `/data` cache volume).

## Quick start (Docker Compose)

```bash
cd Gaming/sons-of-the-forest
mkdir -p ./sotf-data ./sotf-config
cp .env.example .env

# Edit .env (server name, password, etc), then:
docker compose up -d --build
docker compose logs -f
```

## Quick start (Flux)

1. Build + publish your image (or use an existing `repotag` you control).
2. Edit `flux-spec.json`:
   - set `owner`
   - set `repotag`
   - edit `environmentParameters` (server name/password/admins/etc)
3. Deploy via Flux UI/API using the edited spec.

## High availability / world persistence on Flux (important)

The included `flux-spec.json` uses **3 instances** and mounts:

- `g:/config` for **world saves + config** (synced to standby nodes)
- `0:/data` for **Steam/Wine cache** (non-synced, large)

This gives you the Flux benefit you want for survival games: **your world data is replicated** so you can fail over if a node goes down.

Important: `g:/` is a **sync mechanism**, not a clustered filesystem. Running multiple game servers actively writing the same world at the same time can cause sync conflicts/corruption. Treat this as **primary + standby**:

- Share **one** instance’s IP:port with players as the “primary”.
- Keep the other instances as **standby** (do not give those endpoints out).
- If the primary node dies, move players to a standby node’s IP:port; the synced `g:/config` world should already be there.

## Configuration (env vars)

### SteamCMD / install

- `STEAM_APP_ID` (default: `2465200`)
- `STEAM_INSTALL_DIR` (default: `/data/server`)
- `AUTO_UPDATE` (default: `true`) — set `false` to skip updates on startup
- `STEAMCMD_VALIDATE` (default: `true`) — slower but safer; set `false` for faster boot
- `STEAMCMD_FORCE_PLATFORM_TYPE` (default: `windows`) — required for Windows-only servers
- `STEAM_BRANCH`, `STEAM_BRANCH_PASSWORD` (optional) — beta branches
- `STEAMCMD_HOME` (default: `/data/steam`) — where SteamCMD stores state/caches
- `STEAMCMD_LOG_FILE` (default: `/data/steam/steamcmd.log`) — captures the last SteamCMD output (useful for troubleshooting)
- `STEAMCMD_RESET_ON_MISSING_CONFIG` (default: `true`) — wipes Steam config/appcache and retries once if SteamCMD reports “Missing configuration”
- `STEAMCMD_RETRY_NO_VALIDATE_ON_FAIL` (default: `true`) — when `STEAMCMD_VALIDATE=true`, retries once with validate disabled if SteamCMD fails
- `DISK_PREFLIGHT` (default: `true`) — fail early if free disk is too low
- `MIN_FREE_GB` (default: `30`) — required free space at `STEAM_INSTALL_DIR`

### Server identity & access (dedicatedserver.cfg)

- `SOTF_SERVER_NAME` (default: `flux`)
- `SOTF_PASSWORD` (default: empty) — join password (alias: `SOTF_SERVER_PASSWORD`)
- `SOTF_MAX_PLAYERS` (default: `8`)
- `SOTF_LAN_ONLY` (default: `false`)
- `SOTF_IP_ADDRESS` (default: `0.0.0.0`)
- `SOTF_GAME_PORT` / `SOTF_QUERY_PORT` / `SOTF_BLOB_SYNC_PORT`
- `SOTF_SKIP_NETWORK_ACCESSIBILITY_TEST` (default: `true`) — recommended for NAT/proxy scenarios (often helpful on Flux)

### Saves / game mode

- `SOTF_SAVE_SLOT` (default: `1`)
- `SOTF_SAVE_MODE` (default: `Continue`) — typically `Continue` or `New`
- `SOTF_GAME_MODE` (default: `Normal`) — e.g. `Normal`, `Hard`, `Peaceful`, `Custom`
- `SOTF_SAVE_INTERVAL` (default: `600`) — seconds

### Performance / logging (dedicatedserver.cfg)

- `SOTF_IDLE_DAY_CYCLE_SPEED` (default: `0.0`)
- `SOTF_IDLE_TARGET_FRAMERATE` (default: `5`)
- `SOTF_ACTIVE_TARGET_FRAMERATE` (default: `60`)
- `SOTF_LOG_FILES_ENABLED` (default: `true`)
- `SOTF_TIMESTAMP_LOG_FILENAMES` (default: `true`)
- `SOTF_TIMESTAMP_LOG_ENTRIES` (default: `true`)

### Game settings (player-facing)

The dedicated server supports extra “player/gameplay” settings inside:

- `GameSettings` (applies broadly)
- `CustomGameModeSettings` (typically only applied when **creating a new save** in **Custom** mode)

This image supports both simple key/value input and raw JSON:

**Key/value mode** (comma/newline separated):

- `SOTF_GAME_SETTINGS` (example: `Gameplay.TreeRegrowth=false,Structure.Damage=true`)
- `SOTF_CUSTOM_GAME_MODE_SETTINGS` (example below)

**Raw JSON mode** (advanced):

- `SOTF_GAME_SETTINGS_JSON` / `SOTF_GAME_SETTINGS_JSON_B64` / `SOTF_GAME_SETTINGS_JSON_FILE`
- `SOTF_CUSTOM_GAME_MODE_SETTINGS_JSON` / `SOTF_CUSTOM_GAME_MODE_SETTINGS_JSON_B64` / `SOTF_CUSTOM_GAME_MODE_SETTINGS_JSON_FILE`

Example: enable Custom mode settings (requires a **new** save slot to take effect):

```bash
SOTF_SAVE_MODE=New
SOTF_SAVE_SLOT=2
SOTF_GAME_MODE=Custom
SOTF_CUSTOM_GAME_MODE_SETTINGS=GameSetting.Vail.EnemySpawn=true,GameSetting.Vail.EnemyHealth=Normal,GameSetting.Environment.DayLength=Default
```

### Admins (ownerswhitelist)

Admins are SteamID64 entries stored in `/config/ownerswhitelist.txt`.

Options:

- edit the file manually (one SteamID64 per line), or
- set `SOTF_OWNERS` (alias: `SOTF_ADMINS`) as comma/space-separated SteamID64s.

Apply behavior:

- `SOTF_OWNERS_APPLY_MODE=always` (default) overwrites the file from env on each start (when set)
- `SOTF_OWNERS_APPLY_MODE=once` only writes if the file is missing/empty

### Wine / Xvfb

- `USE_XVFB` (default: `true`)
- `XVFB_DISPLAY` (default: `99`)
- `XVFB_ARGS` (default: `-screen 0 1024x768x24 -nolisten tcp -ac`)
- `WINEPREFIX` (default: `/opt/wine/prefix`) — default keeps the huge Wine prefix off Flux volumes (helps avoid volume explorer slowdowns/crashes). Set `WINEPREFIX=/data/wine/prefix` if you want it persisted.
- `WINEARCH` (default: `win64`)
- `WINEDEBUG` (default: `-all`)

### Dedicated server runtime behavior

The official `StartSOTFDedicated.bat` writes `steam_appid.txt` with the base game appid (`1326470`).

This image mirrors that behavior:

- `SOTF_WRITE_STEAM_APPID_TXT` (default: `true`)
- `SOTF_STEAM_APP_ID` (default: `1326470`) — used for `steam_appid.txt` (not the SteamCMD install appid)
- `SOTF_STEAM_GAME_ID` (default: `1326470`) — exported as `SteamGameId`
- `SOTF_VERBOSE_LOGGING` (default: `false`) — adds `-verboseLogging` to the server args

### Permissions

- `PUID` / `PGID` (optional) — adjusts the `steam` user inside the container for volume permissions

### Flux hardening (optional)

- `HARDEN_FLUX_VOLUME_BROWSER` (default: `false`) — when `true` (and running as root), `chmod 700` the top-level `/data` install/prefix directories to reduce exposure via volume browsing (without walking the full tree).

## Troubleshooting

### First start takes a long time

The first boot must download the server via SteamCMD. Subsequent boots reuse `/data/server`.

If updates are too slow:

- set `STEAMCMD_VALIDATE=false`
- ensure you have enough disk (`MIN_FREE_GB`)

### Server not visible / players can’t connect

- Confirm the UDP ports are reachable from the internet.
- Keep `SOTF_SKIP_NETWORK_ACCESSIBILITY_TEST=true` (default) if the server is behind NAT/proxies.
- If you change ports, update both the env vars and your port mappings in Flux / Docker.

### Factory reset

Stop the container/app, then delete:

- everything under `/config` (saves + config)
- optionally `/data` (forces a full re-download)

## VPS build & test (required before Flux deployment)

All builds/tests should run on the dedicated VPS:

```bash
ssh root@46.224.159.242
cd /path/to/flux-marketplace-dockers/Gaming/sons-of-the-forest

docker build -t sotf:local .
mkdir -p ./sotf-data ./sotf-config

docker run --rm -it \
  -p 8766:8766/udp -p 27016:27016/udp -p 9700:9700/udp \
  -v "$PWD/sotf-data:/data" \
  -v "$PWD/sotf-config:/config" \
  -e SOTF_SERVER_NAME="RunOnFlux - Test" \
  -e SOTF_PASSWORD="" \
  -e SOTF_MAX_PLAYERS=8 \
  sotf:local
```

When the server finishes starting, it will appear in-game under **Multiplayer → Dedicated** (and should accept direct connect to `IP:8766`).

Tip: A successful boot prints `ServerStart Success` and binds UDP `8766`, `27016`, and `9700`.
