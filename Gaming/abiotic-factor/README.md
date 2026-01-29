# Abiotic Factor Dedicated Server (Flux-ready)

Marketplace-ready, Flux-friendly Docker image for the **Abiotic Factor** dedicated server:

- Installs/updates via **SteamCMD** (Steam tool appid `2857200`)
- Runs the **Windows-only** server on **linux/amd64** using **Wine + Xvfb**
- Flux-friendly persistence split:
  - `/data` → large **local** cache (Steam install + SteamCMD cache) (recommended: Flux non-synced volume)
  - `/config` → **saves + config** (recommended: Flux synced `g:/config`)

This image does **not** ship any proprietary server files; everything is pulled via SteamCMD at runtime.

## Ports

Default ports (UDP):

- `7777/udp` — Game port (`AF_PORT`)
- `7778/udp` — Secondary port (typically `AF_PORT+1`)
- `27015/udp` — Query port (`AF_QUERY_PORT`)

## Volumes

- `/data` → Steam install + SteamCMD cache (large; safe to keep non-synced on Flux)
- `/config` → `Saved/` folder (world data + server config) (recommended to sync on Flux)

## Recommended host specs (quick guidance)

Real-world resource use varies by world size, progression, and player count.

As a starting point for a public server:

- CPU: **4 vCPU** recommended
- RAM: **8 GB** recommended
- Disk: **30–40 GB** recommended for install + growth

For bigger worlds / higher uptime / “always-on” public servers, plan for **6 vCPU / 16 GB**.

The included `flux-spec.json` matches the baseline (4 CPU / 8 GB RAM) and uses a 30 GB local `/data` cache volume.

## Quick start (Docker Compose)

```bash
cd Gaming/abiotic-factor
mkdir -p ./abiotic-data ./abiotic-config
cp .env.example .env

# Defaults in .env.example include a test password (change it!).

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

- `g:/config` for **saves + config** (synced to standby nodes)
- `0:/data` for **Steam cache/install** (non-synced, large)

This gives you the Flux benefit you want for survival games: **your world data is replicated** so you can fail over if a node goes down.

Important: `g:/` is a **sync mechanism**, not a clustered filesystem. Running multiple game servers actively writing the same world at the same time can cause sync conflicts/corruption. Treat this as **primary + standby**:

- Share **one** instance’s IP:port with players as the “primary”.
- Keep the other instances as **standby** (do not give those endpoints out).
- If the primary node dies, move players to a standby node’s IP:port; the synced `g:/config` world should already be there.

## Configuration (env vars)

### SteamCMD / install

- `STEAM_APP_ID` (default: `2857200`)
- `STEAM_INSTALL_DIR` (default: `/data/server`)
- `AUTO_UPDATE` (default: `true`) — set `false` to skip updates on startup
- `STEAMCMD_VALIDATE` (default: `true`) — slower but safer; set `false` for faster boot
- `STEAMCMD_FORCE_PLATFORM_TYPE` (default: `windows`) — required for Windows-only servers
- `STEAM_BRANCH`, `STEAM_BRANCH_PASSWORD` (optional) — beta branches
- `STEAMCMD_HOME` (default: `/data/steam`)
- `STEAMCMD_LOG_FILE` (default: `/data/steam/steamcmd.log`)
- `DISK_PREFLIGHT` (default: `true`)
- `MIN_FREE_GB` (default: `20`)

### Server identity & access (command-line)

- `MANAGE_CONFIG` (default: `true`) — when `true`, the container can write `Admin.ini` and a sandbox preset file from env vars
- `AF_SERVER_NAME` (default: `RunOnFlux - Abiotic Factor`) → `-SteamServerName=...`
- `AF_SERVER_PASSWORD` (default: empty) → `-ServerPassword=...`
- `AF_ADMIN_PASSWORD` (default: empty) → `-AdminPassword=...`
- `AF_MAX_PLAYERS` (default: `6`) → `-MaxServerPlayers=...`
- `AF_WORLD_SAVE_NAME` (default: `Cascade`) → `-WorldSaveName=...`
- `AF_PORT` / `AF_QUERY_PORT` (also open `AF_PORT+1`)
- `AF_SERVER_ARGS` (default: empty) — extra raw args appended to the server command

### Moderators (Admin.ini)

Moderators are SteamID64 entries stored in:

`/config/Saved/SaveGames/Server/Admin.ini`

Options:

- edit the file manually, or
- set `AF_MODERATORS` as comma/space-separated SteamID64s

Apply behavior:

- `AF_MODERATORS_APPLY_MODE=always` (default) overwrites the file from env on each start (when set)
- `AF_MODERATORS_APPLY_MODE=once` only writes if the file is missing/empty

### Sandbox settings (advanced)

The server supports a sandbox preset file (ini) via `-SandboxIniPath=...` (path relative to the `Saved/` folder).

This image can write your preset file and automatically pass the flag:

- `AF_SANDBOX_SETTINGS_INI` (raw file contents)
- `AF_SANDBOX_SETTINGS_INI_B64` (base64)
- `AF_SANDBOX_SETTINGS_INI_FILE` (container path to read from)
- `AF_SANDBOX_INI_RELATIVE_PATH` (default: `Config/WindowsServer/ServerSandbox.ini`)
- `AF_SANDBOX_APPLY_MODE=once` (default) or `always`

Tip: sandbox settings are typically safest to apply when creating a **new** world save.

### Wine / Xvfb

- `USE_XVFB` (default: `true`)
- `XVFB_DISPLAY` (default: `99`)
- `XVFB_ARGS` (default: `-screen 0 1024x768x24 -nolisten tcp -ac`)
- `WINEPREFIX` (default: `/opt/wine/prefix`) — keeps the huge Wine prefix off Flux volumes (helps avoid volume explorer slowdowns/crashes). Set `WINEPREFIX=/data/wine/prefix` if you want it persisted.
- `WINEARCH` (default: `win64`)
- `WINEDEBUG` (default: `-all`)

### Flux hardening (optional)

- `HARDEN_FLUX_VOLUME_BROWSER` (default: `false`) — reduces impact of Flux volume browsing on large cache dirs. Combine with the default `WINEPREFIX=/opt/...` for best results.

### Permissions

- `PUID` / `PGID` (optional) — adjusts the `steam` user inside the container for volume permissions

## Troubleshooting

### First start takes a long time

The first boot must download the server via SteamCMD. Subsequent boots reuse `/data/server`.

If updates are too slow:

- set `STEAMCMD_VALIDATE=false`
- ensure you have enough disk (`MIN_FREE_GB`)

### Server not visible / players can’t connect

- Confirm the UDP ports are reachable from the internet.
- If you change ports, update both the env vars and your port mappings in Flux / Docker.
