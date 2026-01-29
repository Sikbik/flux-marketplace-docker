# Valheim Dedicated Server (Flux-friendly, headless)

Official **Valheim** dedicated server container designed for Flux Marketplace deployment.

Key goals:

- **Headless**: runs with `-nographics -batchmode`
- **Flux-friendly persistence**: worlds/saves live under `/config` (recommended `g:/config`)
- **Low syncthing churn**: Steam install lives under `/data` (recommended local/non-synced volume)

## Ports

Valheim uses 3 UDP ports:

- `2456/udp` (default)
- `2457/udp`
- `2458/udp`

Note: some server builds/configurations may not actively bind `PORT+2` (`2458`) even though it’s commonly recommended to forward it. This image’s healthcheck requires `PORT` and `PORT+1` by default; set `VALHEIM_HEALTHCHECK_PORT_3=true` to require `PORT+2` as well.

## Volumes

- `/config` — saves/worlds (persist this; on Flux use `g:/config`)
- `/data` — Steam install + caches (on Flux keep this local to the node)

## Quick start (Docker)

```bash
docker run -d --name valheim \
  -p 2456-2458:2456-2458/udp \
  -e VALHEIM_SERVER_NAME="RunOnFlux - Valheim" \
  -e VALHEIM_WORLD_NAME="RunOnFlux" \
  -e VALHEIM_PASSWORD="test1234" \
  -v "$PWD/valheim-config:/config" \
  -v "$PWD/valheim-data:/data" \
  littlestache/valheim-flux:latest
```

To join in-game:

- Join IP: your server IP
- Port: `2456`
- Password: `VALHEIM_PASSWORD`

## Configuration (env vars)

### SteamCMD / install

- `AUTO_UPDATE` (default: `true`)
- `STEAM_APP_ID` (default: `896660`)
- `STEAM_INSTALL_DIR` (default: `/data/server`)
- `STEAMCMD_HOME` (default: `/data/steam`)
- `STEAMCMD_LOG_FILE` (default: `/data/steam/steamcmd.log`)
- `STEAMCMD_VALIDATE` (default: `false`) — set `true` if you need a slower but safer validation pass
- `STEAM_BRANCH` / `STEAM_BRANCH_PASSWORD` (optional)
- `DISK_PREFLIGHT` (default: `true`)
- `MIN_FREE_GB` (default: `5`)

### Server basics (player-facing)

- `VALHEIM_SERVER_NAME` (default: `RunOnFlux - Valheim`)
- `VALHEIM_WORLD_NAME` (default: `RunOnFlux`)
- `VALHEIM_PASSWORD` (**required**, 5+ chars)
- `VALHEIM_PUBLIC` (default: `true`) — show in community list (`true`/`false`)
- `VALHEIM_PORT` (default: `2456`) — base port (uses base+1, base+2 too)

### Persistence

- `VALHEIM_SAVEDIR` (default: `/config`) — where Valheim writes worlds/saves (recommended Flux `g:/config`)

### Optional

- `VALHEIM_CROSSPLAY` (default: `false`)
- `VALHEIM_STEAM_APP_ID` (default: `892970`) — used for Steam initialization (exported as `SteamAppId`/`SteamGameId`)
- `VALHEIM_WRITE_STEAM_APPID_TXT` (default: `true`) — writes `steam_appid.txt` next to the server binary (recommended)
- `VALHEIM_LOG_FILE` (default: empty) — leave empty to use stdout; set e.g. `/config/valheim-server.log` to write to a file
- `VALHEIM_EXTRA_ARGS` (optional)

## Flux notes (recommended production layout)

This repo’s Flux pattern for survival/long-lived worlds is:

- **3 instances** (so `g:/config` is replicated)
- **2 components**
  - `data` → local `/data` volume (not synced)
  - `server` → `g:/config|0:/data` (worlds synced, install local)

See `Gaming/valheim/flux-spec.json` as a template.

## VPS test (required by repo rules)

On the VPS (`root@46.224.159.242`):

```bash
cd /root/flux-marketplace-dockers/Gaming/valheim
rm -rf valheim-config valheim-data || true
docker compose down --remove-orphans || true
cp -f .env.example .env
docker compose up -d --build
docker logs -f valheim-server
```

Health check:

```bash
docker inspect --format '{{.State.Health.Status}}' valheim-server
```

Cleanup:

```bash
docker compose down -v
rm -rf valheim-config valheim-data
```
