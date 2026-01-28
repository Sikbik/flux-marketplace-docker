# Sons of the Forest Dedicated Server (Flux-friendly)

Flux-friendly Docker image for **Sons of the Forest** dedicated server:

- Downloads/updates via **SteamCMD** (appid `2465200`)
- Runs the **Windows-only** server under **Wine** (linux/amd64)
- Persists config + saves under `/config` (ideal for Flux `g:/`)
- Persists Steam install + Wine prefix under `/data` (ideal for a non-synced Flux volume)

## Quick start (Docker Compose)

```bash
cd Gaming/sons-of-the-forest
mkdir -p ./sotf-config ./sotf-data
docker compose up -d --build
docker compose logs -f
```

## Ports

Defaults (UDP):

- `8766/udp` game port
- `27016/udp` query port
- `9700/udp` blob sync port

## Persistence

Mount these:

- `/config` → config + saves (contains `dedicatedserver.cfg`, `ownerswhitelist.txt`, and save data)
- `/data` → Steam install + Wine prefix (large)

## Config management

By default `MANAGE_CONFIG=true` and the container generates `/config/dedicatedserver.cfg` from env vars on boot.

If you want to manage the config file yourself, set:

- `MANAGE_CONFIG=false`

### Admins

You can set admins by writing SteamID64 entries into `/config/ownerswhitelist.txt` (one per line),
or set `SOTF_OWNERS` (comma/space-separated) to generate the file.

## Flux deployment

This folder includes a ready-to-edit `flux-spec.json` that:

- uses a `data` component for local `/data` (not synced),
- uses `g:/config` for synced config+saves,
- runs 3 instances by default.

Before deploying, edit:

- `owner`
- `repotag` (publish your image first, or use `littlestache/sons-of-the-forest-flux:latest` if that’s what you’re pushing)

