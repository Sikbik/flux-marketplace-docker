# V Rising Dedicated Server (Flux-friendly, SteamCMD + Wine)

Professional V Rising dedicated server container designed for Flux Marketplace deployment.

Key goals:

- **Flux-friendly persistence**: persistent data lives under `/config/save-data` (recommended Flux `g:/config`)
- **Low syncthing churn**: Steam install + cache live under `/data` (recommended local/non-synced volume)
- **Consumer-friendly env vars**: server name, password, ports, autosave, listing, etc.

## Ports

Default ports:

- `9876/udp` — game port
- `9877/udp` — query port

Optional:

- `25575/tcp` — RCON (only if enabled and the port is opened on your platform)

## Volumes

- `/config` — persistent settings + saves (on Flux use `g:/config`)
  - `/config/save-data` contains `Settings/` and save files
- `/data` — Steam install + SteamCMD cache (on Flux keep this local to the node)

## Quick start (Docker)

```bash
docker run -d --name v-rising \
  -p 9876:9876/udp \
  -p 9877:9877/udp \
  -e VR_SERVER_NAME="RunOnFlux - V Rising" \
  -e VR_PASSWORD="test1234" \
  -v "$PWD/vrising-config:/config" \
  -v "$PWD/vrising-data:/data" \
  littlestache/v-rising-flux:latest
```

To join in-game:

- Search for server name: `VR_SERVER_NAME` (if public listing is enabled)
- Or connect via IP: `SERVER_IP:9876`
- Password: `VR_PASSWORD`

## Configuration (env vars)

### SteamCMD / install

- `AUTO_UPDATE` (default: `true`)
- `STEAM_APP_ID` (default: `1829350`) — V Rising Dedicated Server tool
- `STEAM_INSTALL_DIR` (default: `/data/server`)
- `STEAMCMD_HOME` (default: `/data/steam`)
- `STEAMCMD_LOG_FILE` (default: `/data/steam/steamcmd.log`)
- `STEAMCMD_VALIDATE` (default: `true`) — set `false` for faster (but less strict) updates
- `DISK_PREFLIGHT` (default: `true`)
- `MIN_FREE_GB` (default: `15`)

### Server basics (player-facing)

- `VR_SERVER_NAME` (default: `RunOnFlux - V Rising`)
- `VR_SERVER_DESCRIPTION` (default: empty)
- `VR_SAVE_NAME` (default: `RunOnFlux`)
- `VR_PASSWORD` (default: empty)
- `VR_GAME_PORT` (default: `9876`)
- `VR_QUERY_PORT` (default: `9877`)
- `VR_MAX_PLAYERS` (default: `40`)
- `VR_MAX_ADMINS` (default: `4`)
- `VR_SERVER_FPS` (default: `30`)
- `VR_SECURE` (default: `true`)
- `VR_LIST_ON_STEAM` (default: `true`)
- `VR_LIST_ON_EOS` (default: `true`)
- `VR_AUTOSAVE_INTERVAL` (default: `600`) — seconds
- `VR_AUTOSAVE_COUNT` (default: `50`)
- `VR_GAME_SETTINGS_PRESET` (optional) — if set, writes `GameSettingsPreset` in host settings

### Popular game settings (env → `ServerGameSettings.json`)

These are some of the most commonly tweaked server settings. When `MANAGE_CONFIG=true`, this container will set these keys in `ServerGameSettings.json`:

- `VR_GAME_MODE_TYPE` → `GameModeType` (`PvP` or `PvE`)
- `VR_TELEPORT_BOUND_ITEMS` → `TeleportBoundItems` (`true`/`false`)
- `VR_BAT_BOUND_ITEMS` → `BatBoundItems` (`true`/`false`)
- `VR_MATERIAL_YIELD_MODIFIER_GLOBAL` → `MaterialYieldModifier_Global` (number)
- `VR_INVENTORY_STACKS_MODIFIER` → `InventoryStacksModifier` (number)
- `VR_CRAFT_RATE_MODIFIER` → `CraftRateModifier` (number)
- `VR_REFINEMENT_RATE_MODIFIER` → `RefinementRateModifier` (number)
- `VR_CASTLE_BLOOD_ESSENCE_DRAIN_MODIFIER` → `CastleBloodEssenceDrainModifier` (number)
- `VR_CASTLE_DECAY_RATE_MODIFIER` → `CastleDecayRateModifier` (number)

### RCON (optional)

- `VR_RCON_ENABLED` (default: `false`)
- `VR_RCON_PORT` (default: `25575`)
- `VR_RCON_PASSWORD` (optional)

### Admin / whitelist / banlist (optional)

Values accept commas and/or newlines (SteamID64 per line):

- `VR_ADMIN_LIST`
- `VR_WHITELIST`
- `VR_BANLIST`

### Advanced

- `VR_PERSISTENT_DATA_DIR` (default: `/config/save-data`)
- `VR_GAME_SETTINGS_JSON` / `VR_GAME_SETTINGS_JSON_B64` — overwrite `ServerGameSettings.json`
- `VR_LOG_FILE` (optional) — if set to an absolute Unix path, it is converted to a Windows path with `winepath`
- `VR_SERVER_ARGS` (optional) — extra args appended to the server command
- `HARDEN_FLUX_VOLUME_BROWSER` (default: `false`) — `chmod 700` the top-level cache dirs under `/data` to reduce Flux volume explorer load

## Flux notes (recommended production layout)

This repo’s Flux pattern for survival/long-lived worlds is:

- **3 instances** (so `g:/config` is replicated)
- **2 components**
  - `data` → local `/data` volume (not synced)
  - `server` → `g:/config|0:/data` (saves synced, install local)

See `Gaming/v-rising/flux-spec.json` as a template.

## VPS test (required by repo rules)

On the VPS (`root@46.224.159.242`):

```bash
cd /root/flux-marketplace-dockers/Gaming/v-rising
rm -rf vrising-config vrising-data || true
docker compose down --remove-orphans || true
cp -f .env.example .env
docker compose up -d --build
docker logs -f v-rising-server
```

Health check:

```bash
docker inspect --format '{{.State.Health.Status}}' v-rising-server
```

Cleanup:

```bash
docker compose down -v
rm -rf vrising-config vrising-data
```
