# Enshrouded Dedicated Server (Flux-friendly, SteamCMD + Wine)

Professional Enshrouded dedicated server container designed for Flux Marketplace deployment.

Key goals:

- **Flux-friendly persistence**: persistent save data + logs live under `/config` (recommended Flux `g:/config`)
- **Low syncthing churn**: Steam install + cache live under `/data` (recommended local/non-synced volume)
- **Consumer-friendly env vars**: server name, password, slots, preset, chat, etc.

> Note: Enshrouded dedicated server is currently **Windows-only**, so this image runs it under **Wine**.

## Ports

Default:

- `15637/udp` — `queryPort` (official default)

Steam:

- Steam may require additional ports (see Valve “Required Ports for Steam” guidance). For simple home/VPS deployments, `27015/udp` is commonly used, but requirements vary by environment.

## Volumes

- `/config` — persistent config + saves + logs (on Flux use `g:/config`)
  - `/config/enshrouded_server.json` (managed/updated by this container)
  - `/config/savegame`
- `/data` — Steam install + SteamCMD cache (on Flux keep this local to the node)
  - `/data/logs` (default) — server log files (kept local for performance)

## Quick start (Docker)

```bash
docker run -d --name enshrouded \
  -p 15637:15637/udp \
  -e ENS_SERVER_NAME="RunOnFlux - Enshrouded" \
  -e ENS_PASSWORD="test1234" \
  -v "$PWD/enshrouded-config:/config" \
  -v "$PWD/enshrouded-data:/data" \
  littlestache/enshrouded-flux:latest
```

Join in-game:

- Add as a Steam favorite using `SERVER_IP:15637` (query port)
- Password: `ENS_PASSWORD`

## Configuration (env vars)

### SteamCMD / install

- `AUTO_UPDATE` (default: `true`)
- `STEAM_APP_ID` (default: `2278520`)
- `STEAM_INSTALL_DIR` (default: `/data/server`)
- `STEAMCMD_HOME` (default: `/data/steam`)
- `STEAMCMD_LOG_FILE` (default: `/data/steam/steamcmd.log`)
- `STEAMCMD_VALIDATE` (default: `true`)
- `STEAM_BRANCH` (optional)
- `STEAM_LOGIN` (default: `anonymous`)
- `STEAM_PASSWORD`, `STEAM_GUARD` (optional)

If SteamCMD starts failing with “No subscription”, set `STEAM_LOGIN/STEAM_PASSWORD` to a Steam account that owns Enshrouded.

### Server basics (player-facing)

These are written into `/config/enshrouded_server.json`:

- `ENS_SERVER_NAME` (default: `RunOnFlux - Enshrouded`)
- `ENS_PASSWORD` (default: empty)
- `ENS_SLOT_COUNT` (default: `16`)
- `ENS_QUERY_PORT` (default: `15637`)
- `ENS_IP` (default: `0.0.0.0`)
- `ENS_GAME_SETTINGS_PRESET` (default: `Default`)
- `ENS_ENABLE_TEXT_CHAT` (default: `false`)
- `ENS_ENABLE_VOICE_CHAT` (default: `false`)
- `ENS_VOICE_CHAT_MODE` (default: `Proximity`)

Password behavior:

- This image uses a single `Default` user group in `enshrouded_server.json` (with full permissions) when `ENS_PASSWORD` is set, so most users only need **one password**.

### Disk preflight

- `DISK_PREFLIGHT` (default: `true`)
- `MIN_FREE_GB` (default: `30`)

### Flux hardening

- `HARDEN_FLUX_VOLUME_BROWSER` (default: `true`) — sets restrictive permissions on the large `/data` directory trees to reduce Flux volume explorer load.

### Logs location (Flux performance)

By default this container keeps server logs **local** under `/data/logs` to avoid constant syncthing churn on `g:/config`.  
If you really want logs replicated with your world data, set:

- `ENS_LOG_DIR=/config/logs`

## Recommended server specs (official guidance)

Per Enshrouded official recommendations:

- For **4–6 players**: ~6 cores / 16 GB RAM / 30 GB SSD free
- For **16 players**: ~8 cores / 16 GB RAM / 30 GB SSD free

## Flux notes (recommended production layout)

This repo’s Flux pattern for survival/long-lived worlds is:

- **3 instances** (so `g:/config` is replicated)
- **2 components**
  - `data` → local `/data` volume (not synced)
  - `server` → `g:/config|0:/data` (saves synced, install local)

See `Gaming/enshrouded/flux-spec.json` as a template.

## VPS test (required by repo rules)

On the VPS (`root@46.224.159.242`):

```bash
cd /root/flux-marketplace-dockers/Gaming/enshrouded
rm -rf enshrouded-config enshrouded-data || true
docker compose down --remove-orphans || true
cp -f .env.example .env
docker compose up -d --build
docker logs -f enshrouded-server
```

Health check:

```bash
docker inspect --format '{{.State.Health.Status}}' enshrouded-server
```

Cleanup:

```bash
docker compose down -v
rm -rf enshrouded-config enshrouded-data
```
