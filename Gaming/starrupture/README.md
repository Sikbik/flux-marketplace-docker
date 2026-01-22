# StarRupture Dedicated Server (Flux-ready)

This image uses `cm2network/steamcmd` as the base and runs the Windows-only
StarRupture dedicated server under Wine. The entrypoint handles SteamCMD
downloads/updates, persistence, and optionally auto-starting the session via
StarRupture's Remote Control API.

## Quick start

```bash
docker build -t starrupture:flux .

docker run --rm -it \
  -p 7777:7777/udp -p 7777:7777/tcp \
  -p 27015:27015/udp \
  -e SERVER_NAME="RunOnFlux" \
  -v /path/to/saves:/saves \
  starrupture:flux
```

## Environment variables

### SteamCMD / install

- `STEAM_APP_ID` (default: `3809400`)
- `STEAM_INSTALL_DIR` (default: auto-selects `/opt/server` if it has `MIN_FREE_GB` free; otherwise uses `/data/server` when `/data` is a separate mount)
- `STEAM_LOGIN` (default: `anonymous`)
- `STEAM_PASSWORD` (default: empty)
- `STEAM_GUARD` (default: empty)
- `STEAMCMD_VALIDATE` (default: `true`)
- `STEAM_BRANCH` (default: empty)
- `STEAM_BRANCH_PASSWORD` (default: empty)
- `STEAMCMD_FORCE_PLATFORM_TYPE` (default: `windows`)
- `STEAMCMD_EXTRA_ARGS` (default: empty)
- `AUTO_UPDATE` (default: `true`)
- `STEAMCMD_RUN_AS` (default: `steam`) — run SteamCMD as `steam` to avoid permissions errors
- `SYNC_SAVES_ONLY` (default: `false`) — when `true`, treat `SAVEGAMES_DIR` as the synced SaveGames folder and keep the full `SAVED_DIR` local
- `SAVED_DIR` (default: `/saves`) — Unreal "Saved" directory root (legacy alias: `SAVES_DIR`)
- `SAVEGAMES_DIR` (default: `SAVED_DIR/SaveGames`, or `/saves` when `SYNC_SAVES_ONLY=true`) — SaveGames folder root (session folders live here)
- `WINE_G_DRIVE` (default: `SAVEGAMES_DIR`)
- `DISK_PREFLIGHT` (default: `true`) — fail early if disk space is too low for install/update
- `MIN_FREE_GB` (default: `30`) — minimum free space required at `STEAM_INSTALL_DIR`
- `STEAMCMD_LOG_FILE` (default: `/tmp/steamcmd.log`)
- `STEAMCMD_RETRY_NO_VALIDATE_ON_FAIL` (default: `true`) — if SteamCMD fails with `validate`, retry once without it
- `STEAMCMD_RESET_ON_MISSING_CONFIG` (default: `true`) — if SteamCMD fails with `Missing configuration`, wipe Steam config/appcache and retry once
- `STEAMCMD_RETRY_AS_STEAM_ON_FAIL` (default: `true`) — if SteamCMD fails as `root`, retry once as `steam`
- `STEAMCMD_RETRY_AS_ROOT_ON_FAIL` (default: `true`) — if SteamCMD fails as `steam`, retry once as `root`
- `HARDEN_FLUX_VOLUME_BROWSER` (default: `false`) — when true (and running as root), chmods `/data/server` and `/data/wine` to `700` to reduce Flux volume browser risk on large installs

### Server runtime

- `SERVER_EXE` (default: `${STEAM_INSTALL_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe`)
- `DEFAULT_PORT` (default: `7777`)
- `SERVER_PORT` (default: `DEFAULT_PORT`)
- `QUERY_PORT` (default: `27015`)
- `SERVER_NAME` (default: `starrupture-server`)
- `MULTIHOME` (default: empty)
- `SERVER_ARGS` (default: empty)
- `SR_LOG` (default: `true`)
- `USE_XVFB` (default: `true`)
- `XVFB_DISPLAY` (default: `99`)
- `XVFB_ARGS` (default: `-screen 0 1280x1024x24 -nolisten tcp -ac`)
- `WINEPREFIX` (default: `/opt/wine/prefix` when unset; falls back to `/data/wine/prefix` if it already exists)
- `WINEDLLOVERRIDES` (default: `mscoree,mshtml=` to avoid Mono/Gecko prompts)
- `WINEDEBUG` (default: `-all`)
- `WINE_BIN` (default: auto-detects `wine`, falls back to `/usr/lib/wine/wine64`)

### Auto-start session (recommended)

StarRupture dedicated servers boot into a "DedicatedServerStart" world and
normally require the game client’s **Manage Server** flow to set passwords and
start/load a session. This image can automate that by calling the server’s
Remote Control API endpoints on `SERVER_PORT`.

- `SR_AUTO_START` (default: `true`) — auto-starts by loading the save referenced by `SaveData.dat` (or the newest `*.sav`). If no save exists, the behavior depends on `SR_START_NEW_SESSION_IF_NO_SAVE` (and is disabled by default in `SYNC_SAVES_ONLY=true` mode).
- `SR_START_NEW_SESSION_IF_NO_SAVE` (default: `false`) — when `SYNC_SAVES_ONLY=true`, controls whether the container should start a new session if no save exists yet. For marketplace/Flux failover safety, the default is to **not** auto-create a world on an empty `/saves` and stay in the initial **Manage Server** state instead.
- `SR_ADMIN_PASSWORD_TOKEN` (default: empty) — **recommended**. Token string stored in `Password.json` under `"Password"` (684 base64 chars). This is what the StarRupture client expects when connecting via **Manage Server**.
- `SR_PLAYER_PASSWORD_TOKEN` (default: empty) — **recommended**. Token string stored in `PlayerPassword.json` under `"Password"` (684 base64 chars). This is what the StarRupture client expects for the gameplay “join password”.
- `SR_ADMIN_PASSWORD` (default: empty) — plain-string fallback. This can be used for headless automation, but StarRupture clients appear to use token-based passwords; **Manage Server may not accept it**.
- `SR_PLAYER_PASSWORD` (default: empty) — plain-string fallback. **Join password may not be enforced** unless a token is used.
- If no admin password/token is available yet, the image will **skip auto-start** and keep the server in the initial **Manage Server** state so you can initialize it once.
- `SR_FORCE_PASSWORD_FILES` (default: `false`) — when `true`, forces copies of `Password.json` / `PlayerPassword.json` between `SAVED_DIR`, `SAVEGAMES_DIR` (when `SYNC_SAVES_ONLY=true`), and the install dir (helpful on Flux migrations)
- `SR_SESSION_NAME` (default: empty) — session name used when starting a new session (defaults to `SERVER_NAME`)
- `SR_CREDENTIALS_WAIT_SECS` (default: `60`) — when `SYNC_SAVES_ONLY=true` and saves exist, how long to wait for Syncthing to deliver `Password.json` before skipping auto-start (helps Flux failovers)
- These waits only affect **auto-start automation**. If they time out, the server keeps running in its initial state and you can still open **Manage Server** later to initialize or recover.
- `SR_PASSWORD_SYNC_INTERVAL_SECS` (default: `10`) — when `SYNC_SAVES_ONLY=true`, how often to sync token password files into the synced folder (helps Flux failovers)
- `SR_AUTOSTART_WATCH_INTERVAL_SECS` (default: `10`) — background watcher interval for “late” Syncthing arrivals (token + existing saves)
- `SR_AUTOSTART_WATCH_SECS` (default: `0`) — watcher timeout in seconds (`0` = keep watching)
- `SR_REMOTE_WAIT_SECS` (default: `600`) — how long to wait for `/remote/info` before skipping auto-start
- `SR_REMOTE_HOST` (default: empty) — host used for Remote Control API calls (auto-detected; override only for debugging)
- `SR_REMOTE_PORT` (default: `SERVER_PORT`) — port used for Remote Control API calls (auto-detected)
- `SR_REMOTE_PORTS` (default: `${SERVER_PORT},30010,30020`) — ports to probe for `/remote/info` (comma/space-separated)

Notes:
- The StarRupture client stores **token passwords** (684 base64 chars) in `Password.json` / `PlayerPassword.json`. These files should be preserved (and synced on Flux) so passworded servers survive restarts/migrations.
- This image copies password files as regular files (not symlinks) to reduce Flux volume browser issues.
  - In `SYNC_SAVES_ONLY=true` mode, the entrypoint continuously syncs token password files into the synced `SAVEGAMES_DIR` so failover nodes can auto-start without re-initializing via **Manage Server**.

### Password files (optional)

Some server hosts use `Password.json` (admin) and `PlayerPassword.json` (player)
in the server root. If you already have the JSON contents, you can inject them
directly.

- `ADMIN_PASSWORD_JSON` (default: empty)
- `PLAYER_PASSWORD_JSON` (default: empty)

## Notes

- The StarRupture dedicated server is Windows-only, so this image runs it with
  Wine.
- Flux note: the `hdd` value you request in a Flux spec applies to the mounted
  app volume(s) (`containerData`), not the container root filesystem (`/`). If
  you install to `/opt/server`, it uses the node’s Docker disk, which can be
  smaller than your requested `hdd`.
- The default startup flags include `-Log`, `-Port=<SERVER_PORT>`,
  `-QueryPort=<QUERY_PORT>`, `-ServerName=<SERVER_NAME>`, and optional
  `-MULTIHOME=<MULTIHOME>`. You can append more with `SERVER_ARGS`.
- Recommended resources for production: 4 vCPU, 16 GB RAM, 50+ GB disk.
- If SteamCMD fails with `state is 0x202 after update job`, it’s usually the
  node running out of disk for the install path. Try a different node, or set
  `STEAMCMD_VALIDATE=false` to reduce overhead.
- **Manage Server** password state is stored in `Password.json` (admin) and
  `PlayerPassword.json` (join) as token strings. Preserve/sync these files (on
  Flux, typically via `SAVEGAMES_DIR` when `SYNC_SAVES_ONLY=true`). Deleting them
  forces a fresh setup via **Manage Server**.
- If `SR_AUTO_START=true` successfully loads/starts a session, the server leaves
  the `DedicatedServerStart` world and the in-game **Manage Server** UI may no
  longer work (the `DedicatedServerSettingsComp` object only exists in that
  initial world). This is expected for fully automated/marketplace deployments.
- Flux note: the included `flux-spec.json` uses **two components**:
  - `data` provides the larger, non-synced `/data` volume used for Steam/Wine.
  - `server` mounts the `data` volume at `/data` via `0:/data` and uses a `g:`
    mount at `/saves` for the synced SaveGames folder (low bandwidth).
- In sync-only mode, the entrypoint links:
  - `StarRupture/Saved` → local `SAVED_DIR` (defaults to `/data/saved` on Flux)
  - `SAVED_DIR/SaveGames` → synced `SAVEGAMES_DIR` (defaults to `/saves`)
- If you’re testing from the same network as the server, use the external IP and
  ensure your router supports hairpin NAT.

## Reset / recovery

### Reset admin / join passwords (keep the world)

StarRupture stores passwords as **token strings** in `Password.json` (admin) and
`PlayerPassword.json` (join). To reset them:

1. Stop the container/app.
2. Delete one or both files from the **synced** folder:
   - Flux (`SYNC_SAVES_ONLY=true`): delete from `SAVEGAMES_DIR` (default: `/saves`)
   - Docker (default): delete from `SAVED_DIR` (default: `/saves`)
3. Start the container/app.
4. Use StarRupture **Manage Server** to set new passwords and then **Load Game**
   to start your existing save again.

Tip: If you want the server to stay in the initial **Manage Server** state while
you reset credentials, set `SR_AUTO_START=false` for that run and then set it
back to `true` afterward.

### Factory reset (wipe saves + passwords)

1. Stop the container/app.
2. Delete everything in the synced save folder (`/saves` on Flux, or `SAVED_DIR`
   on Docker), including `SaveGames/`, `SaveData.dat`, `Password.json`, and
   `PlayerPassword.json`.
3. Start the container/app and initialize via **Manage Server**.
