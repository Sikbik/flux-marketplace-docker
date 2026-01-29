# Terraria Dedicated Server (Flux-friendly, headless)

Vanilla **Terraria** dedicated server container designed for Flux Marketplace deployment.

Key goals:

- **Headless**: no interactive menu prompts (we generate/use a config file)
- **Flux-friendly persistence**: worlds/config live under `/config` (recommended `g:/config`)
- **Low syncthing churn**: server install lives under `/data` (recommended local/non-synced volume)

## Ports

- `7777/tcp` (default) — Terraria server port

## Volumes

- `/config` — worlds + config (persist this; on Flux use `g:/config`)
  - worlds: `/config/worlds/*.wld`
  - config: `/config/serverconfig.txt`
- `/data` — server install/cache (on Flux keep this local to the node)

## Quick start (Docker)

```bash
docker run -d --name terraria \
  -p 7777:7777/tcp \
  -e TERRARIA_WORLD_NAME="RunOnFlux World" \
  -e TERRARIA_SERVER_PASSWORD="test1234" \
  -v "$PWD/terraria-config:/config" \
  -v "$PWD/terraria-data:/data" \
  littlestache/terraria-flux:latest
```

To join in-game:

- Multiplayer → Join via IP
- IP: your server IP (Flux node IP)
- Port: `7777`
- Password: whatever you set in `TERRARIA_SERVER_PASSWORD`

## Configuration (env vars)

### Install / update

- `AUTO_UPDATE` (default: `true`) — downloads/extracts the dedicated server package on startup
- `TERRARIA_SERVER_VERSION` (optional) — pin a server package version (e.g. `1450`)
- `TERRARIA_SERVER_URL` (optional) — override download URL completely
- `TERRARIA_INSTALL_DIR` (default: `/data/server`) — where the server package is extracted
- `DISK_PREFLIGHT` (default: `true`)
- `MIN_FREE_GB` (default: `2`) — free space required at `TERRARIA_INSTALL_DIR`

### Server basics (player-facing)

- `TERRARIA_PORT` (default: `7777`)
- `TERRARIA_WORLD_NAME` (default: `RunOnFlux World`)
- `TERRARIA_SERVER_PASSWORD` (default: empty) — set for private servers
- `TERRARIA_MAX_PLAYERS` (default: `16`)
- `TERRARIA_MOTD` (default: `Welcome to Terraria on Flux!`)

### World creation

If the world file does not exist, the server will create it.

- `TERRARIA_AUTOCREATE` (default: `2`) — `1=small`, `2=medium`, `3=large`
- `TERRARIA_SEED` (optional)
- `TERRARIA_DIFFICULTY` (default: `0`) — commonly `0=normal`, `1=expert`, `2=master`, `3=journey` (varies by version)

### Misc

- `TERRARIA_SECURE` (default: `true`)
- `TERRARIA_UPNP` (default: `false`)
- `TERRARIA_EXTRA_ARGS` (optional) — extra command-line args passed to the server process

### Config file control

By default the image generates `/config/serverconfig.txt` on each boot:

- `MANAGE_CONFIG=true` (default)
- `TERRARIA_CONFIG_PATH=/config/serverconfig.txt` (default)

If you want to fully manage the config file yourself:

- set `MANAGE_CONFIG=false`
- edit `/config/serverconfig.txt` directly

## Flux notes (recommended production layout)

This repo’s Flux pattern for survival/long-lived worlds is:

- **3 instances** (so `g:/config` is replicated)
- **2 components**
  - `data` → local `/data` volume (not synced)
  - `server` → `g:/config|0:/data` (worlds synced, install local)

See `Gaming/terraria/flux-spec.json` as a template.

## VPS test (required by repo rules)

On the VPS (`root@46.224.159.242`):

```bash
cd /root/flux-marketplace-dockers/Gaming/terraria
rm -rf terraria-config terraria-data || true
docker compose down --remove-orphans || true
docker compose up -d --build
docker logs -f terraria-server
```

Health check:

```bash
docker ps --filter name=terraria-server
docker inspect --format '{{json .State.Health}}' terraria-server | jq
ss -lntp | grep ':7777'
```

Cleanup:

```bash
docker compose down -v
rm -rf terraria-config terraria-data
```
