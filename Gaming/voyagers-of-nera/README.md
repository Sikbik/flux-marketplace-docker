# Voyagers of Nera Dedicated Server - Docker

Docker image for hosting a Voyagers of Nera dedicated server, compatible with Flux and other container platforms.

## Quick Start

### Using Docker Compose (Recommended)

```bash
# From this folder:
cd Gaming/voyagers-of-nera

# Build and start the server (Wine-based minimal image, defaults to "flux")
docker compose up -d

# View logs
docker compose logs -f

# Stop the server
docker compose down
```

### Using Docker CLI

```bash
# Build the Wine-based image
docker build -t voyagers-of-nera-server:local ./Gaming/voyagers-of-nera

# Create a persistent data directory
mkdir -p ./Gaming/voyagers-of-nera/serverdata

# Run the container
docker run -d \
  --name voyagers-of-nera-server \
  -p 7777:7777/udp -p 7778:7778/udp \
  -e SERVER_PORT=7777 \
  -e EOS_OVERRIDE_HOST_IP=YOUR_PUBLIC_IP \
  -e HOST_SERVER_DISPLAY_NAME="flux" \
  -e USE_STUB_EXE=false \
  -e MANAGE_CONFIG=true \
  -e MAX_PLAYERS=10 \
  -v "$PWD/Gaming/voyagers-of-nera/serverdata:/home/steam/nera/server/BoatGame/Saved" \
  voyagers-of-nera-server:local
```

### Official-Style Workflow (Optional)

If you prefer the Windows guide flow:
1. Set `MANAGE_CONFIG=false` and run once to generate configs.
2. Stop the server.
3. Edit the config files.
4. Start the server again.

Config locations (inside the container volume):
- `/home/steam/nera/server/BoatGame/Saved/PersistedData/CustomConfig`
- `/home/steam/nera/server/BoatGame/Saved/Config/WindowsServer`

## Environment Variables

### Network Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_PORT` | `7777` | UDP port for game connections |
| `EOS_OVERRIDE_HOST_IP` | (empty) | Public IP for clients to connect to. **Required for external connections** |
| `ENABLE_LOGGING` | `true` | Enable logging to files in `Saved/Logs` |
| `QUERY_PORT` | (empty) | Steam query port for server browser (e.g., `27015`) |

### Online Subsystem (Optional)

When set, the container writes `Config/WindowsServer/Engine.ini` with the selected subsystem.

| Variable | Default | Description |
|----------|---------|-------------|
| `ONLINE_SUBSYSTEM` | (empty) | Override `DefaultPlatformService` (`Steam` or `RedpointEOS`) |

### Config Management

| Variable | Default | Description |
|----------|---------|-------------|
| `MANAGE_CONFIG` | `true` | When true, generates `CustomHostServerUserSettings.ini` and `CustomGameUserSettings.ini` from envs |
| `CLEAR_ENGINE_INI` | `false` | When true, moves `Engine.ini` to a backup and lets the server use defaults |
| `CLEAR_CUSTOM_CONFIGS` | `false` | When true, moves custom host/game INIs to backups so the server can regenerate |
| `DISABLE_PRESENCE` | `false` | Best-effort attempt to disable session presence/lobbies (may help listing without EOS presence permissions) |
| `EOS_DEPLOYMENT_ID` | (empty) | Override EOS DeploymentId (use if server is on a different EOS deployment than clients) |
| `USE_STUB_EXE` | `false` | Use the shipping EXE by default; set true to force `BoatGameServer.exe` |
| `WINE_TRICKS` | (empty) | Winetricks packages to install (e.g., `vcrun2019`) |

### Host Server Settings

These settings control the server listing and access.

| Variable | Default | Range | Description |
|----------|---------|-------|-------------|
| `HOST_SERVER_DISPLAY_NAME` | `flux` | Max 30 chars | Server name shown in browser |
| `HOST_SERVER_PASSWORD` | (empty) | Alphanumeric | Password to join (blank = no password) |
| `MAX_PLAYERS` | `10` | 1-10 | Maximum players allowed |
| `AUTOSAVE_TIMER_SECONDS` | `300` | 10-900 | Autosave interval in seconds |

### Game Server Settings

These settings control gameplay mechanics.

| Variable | Default | Range | Description |
|----------|---------|-------|-------------|
| `GATHERING_RATE_MULTIPLIER` | `1.0` | 0.01-10.0 | Resource gathering rate multiplier |
| `ENEMY_DAMAGE_MULTIPLIER` | `1.0` | 0.01-10.0 | Enemy damage multiplier |
| `PLAYER_DAMAGE_MULTIPLIER` | `1.0` | 0.01-10.0 | Player damage multiplier |
| `DISABLE_EQUIPMENT_DURABILITY` | `False` | True/False | When True, equipment never breaks |
| `DISABLE_DROP_ITEMS_ON_DEATH` | `False` | True/False | When True, players keep inventory on death |

### System Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | User ID for file permissions |
| `PGID` | `1000` | Group ID for file permissions |

## Ports

The game uses both the configured port and port+1. If using custom port, open both `port` and `port+1`.

| Port | Protocol | Description |
|------|----------|-------------|
| 7777 | UDP | Primary game server port |
| 7778 | UDP | Secondary game server port (port+1) |
| 27015 | UDP | Steam server query port (optional) |

## Volumes

| Path | Description |
|------|-------------|
| `/home/steam/nera/server/BoatGame/Saved` | Persistent data (saves, config, logs) |

## Deploying on Flux

### 1. Build and Push to Docker Registry

```bash
# Build the image
docker build -t your-dockerhub-username/voyagers-of-nera-server:latest .

# Push to Docker Hub
docker push your-dockerhub-username/voyagers-of-nera-server:latest
```

### 2. Deploy Using flux-spec.json

A pre-configured `flux-spec.json` is included. Before deploying:

1. Edit `flux-spec.json`:
   - Replace `YOUR_ZELID_HERE` with your ZelID
   - Replace `YOUR_DOCKERHUB_USERNAME` with your Docker Hub username
   - Adjust `EOS_OVERRIDE_HOST_IP` if needed (Flux may handle this automatically)
   - Tweak the included `environmentParameters` (server name, password, rates) as needed

2. Deploy via Flux:
   - Use the Flux marketplace or API to deploy using the spec
   - Or upload through the Flux dashboard

### 3. Flux Resource Requirements

The default `flux-spec.json` requests:
- **CPU**: 2 cores
- **RAM**: 8000 MB (8 GB)
- **Storage**: 20 GB

### 4. Important Flux Notes

- Set `EOS_OVERRIDE_HOST_IP` to the public IP of your Flux node for external connections
- Ensure UDP port 7777 is accessible through Flux networking
- The `containerData` volume persists the full server install and saves
- First startup takes longer as it downloads the server files (later restarts reuse the persisted install)

## Example Configurations

### Casual/Easy Server
```bash
GATHERING_RATE_MULTIPLIER=2.0
ENEMY_DAMAGE_MULTIPLIER=0.5
PLAYER_DAMAGE_MULTIPLIER=1.5
DISABLE_DROP_ITEMS_ON_DEATH=True
```

### Hardcore Server
```bash
GATHERING_RATE_MULTIPLIER=0.5
ENEMY_DAMAGE_MULTIPLIER=2.0
PLAYER_DAMAGE_MULTIPLIER=0.75
DISABLE_EQUIPMENT_DURABILITY=False
DISABLE_DROP_ITEMS_ON_DEATH=False
```

### Private Friends Server
```bash
HOST_SERVER_DISPLAY_NAME=Friends Only
HOST_SERVER_PASSWORD=secretpassword123
MAX_PLAYERS=4
```

## Troubleshooting

### Server not showing in browser
- Ensure `EOS_OVERRIDE_HOST_IP` is set to your public IP
- Verify UDP ports 7777 AND 7778 are forwarded/open in your firewall
- If using Steam listing, set `ONLINE_SUBSYSTEM=Steam`, keep Steam enabled (`DISABLE_STEAM=false`), and open UDP `QUERY_PORT` (e.g., 27015)
- If you want stock behavior, unset `ONLINE_SUBSYSTEM`, unset `QUERY_PORT`, set `MANAGE_CONFIG=false`, and set `CLEAR_ENGINE_INI=true` once to remove overrides
- For a pristine first-run, also set `CLEAR_CUSTOM_CONFIGS=true` once to remove the custom INIs

### Players can't connect
- Check that UDP 7777 AND 7778 are accessible from the internet
- The game uses both port and port+1, so both must be open
- Verify the `EOS_OVERRIDE_HOST_IP` matches your public IP

### Saves not persisting
- Ensure the volume is properly mounted
- Check that the container has write permissions to the save directory

### View logs
```bash
# Docker Compose
docker-compose logs -f

# Docker CLI
docker logs -f voyagers-of-nera-server
```

### Configuration not applying
- If `MANAGE_CONFIG=true`, config files are regenerated from envs on each startup
- If you edit configs manually, keep `MANAGE_CONFIG=false` and stop the container first

## System Requirements

- **CPU**: 2+ cores
- **RAM**: 8 GB recommended (4 GB can OOM during startup)
- **Storage**: 50 GB+ (for server files, Wine, and saves)
- **Network**: Stable connection with UDP 7777 accessible

## Technical Notes

- Wine-only container (minimal), matching the official Windows dedicated server workflow
- First startup will take longer as it downloads the server files (~10-15 GB)
- The server automatically updates on each container start via SteamCMD
- Configuration files are only regenerated when `MANAGE_CONFIG=true`
- Setting `ONLINE_SUBSYSTEM` overwrites `Config/WindowsServer/Engine.ini` when set
- Steam App ID: 3937860
