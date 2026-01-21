#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"

HYTALE_RUN_MODE="${HYTALE_RUN_MODE:-server}"

HYTALE_BIND="${HYTALE_BIND:-0.0.0.0:5520}"
HYTALE_PORT="${HYTALE_PORT:-}"
HYTALE_AUTH_MODE="${HYTALE_AUTH_MODE:-authenticated}"
HYTALE_AUTH_AUTO="${HYTALE_AUTH_AUTO:-0}"
HYTALE_AUTH_STATE_DIR="${HYTALE_AUTH_STATE_DIR:-${DATA_DIR}/auth}"
HYTALE_AUTH_PROFILE_UUID="${HYTALE_AUTH_PROFILE_UUID:-}"
HYTALE_AUTH_PROFILE_USERNAME="${HYTALE_AUTH_PROFILE_USERNAME:-}"
HYTALE_AUTH_CLIENT_ID="${HYTALE_AUTH_CLIENT_ID:-hytale-server}"
HYTALE_ACCEPT_EARLY_PLUGINS="${HYTALE_ACCEPT_EARLY_PLUGINS:-0}"
HYTALE_ALLOW_OP="${HYTALE_ALLOW_OP:-0}"
HYTALE_BACKUP="${HYTALE_BACKUP:-0}"
HYTALE_BACKUP_DIR="${HYTALE_BACKUP_DIR:-${DATA_DIR}/backups}"
HYTALE_BACKUP_FREQUENCY="${HYTALE_BACKUP_FREQUENCY:-}"
HYTALE_PATCHLINE="${HYTALE_PATCHLINE:-release}"
HYTALE_AUTO_DOWNLOAD="${HYTALE_AUTO_DOWNLOAD:-0}"
HYTALE_AUTO_UPDATE="${HYTALE_AUTO_UPDATE:-0}"
HYTALE_KEEP_DOWNLOAD_ARCHIVE="${HYTALE_KEEP_DOWNLOAD_ARCHIVE:-0}"
HYTALE_UPDATE_SKIP_PATTERNS="${HYTALE_UPDATE_SKIP_PATTERNS:-universe/**,logs/**,mods/**,.cache/**,*.json}"
HYTALE_CONSOLE_MODE="${HYTALE_CONSOLE_MODE:-file}"
HYTALE_CONSOLE_CLEAR_ON_START="${HYTALE_CONSOLE_CLEAR_ON_START:-1}"
HYTALE_STARTUP_COMMANDS="${HYTALE_STARTUP_COMMANDS:-}"
HYTALE_STARTUP_COMMANDS_APPLY_MODE="${HYTALE_STARTUP_COMMANDS_APPLY_MODE:-once}"
HYTALE_EPHEMERAL_CACHE="${HYTALE_EPHEMERAL_CACHE:-0}"
HYTALE_CACHE_DIR="${HYTALE_CACHE_DIR:-/tmp/hytale-cache}"
HYTALE_EXTRA_ARGS="${HYTALE_EXTRA_ARGS:-}"
HYTALE_CONFIG_PATH="${HYTALE_CONFIG_PATH:-}"
HYTALE_CONFIG_ENV_PREFIX="${HYTALE_CONFIG_ENV_PREFIX:-HYTALE_CFG__}"
HYTALE_CONFIG_MODE="${HYTALE_CONFIG_MODE:-merge}"
HYTALE_CONFIG_ALLOW_CREATE="${HYTALE_CONFIG_ALLOW_CREATE:-0}"
HYTALE_CONFIG_APPLY_MODE="${HYTALE_CONFIG_APPLY_MODE:-always}"
HYTALE_CONFIG_JSON="${HYTALE_CONFIG_JSON:-}"
HYTALE_CONFIG_JSON_B64="${HYTALE_CONFIG_JSON_B64:-}"
HYTALE_CONFIG_JSON_FILE="${HYTALE_CONFIG_JSON_FILE:-}"
HYTALE_SERVER_NAME="${HYTALE_SERVER_NAME:-}"
HYTALE_SERVER_NAME_CONFIG_KEY="${HYTALE_SERVER_NAME_CONFIG_KEY:-ServerName}"

HYTALE_WHITELIST_PATH="${HYTALE_WHITELIST_PATH:-}"
HYTALE_WHITELIST_MODE="${HYTALE_WHITELIST_MODE:-replace}"
HYTALE_WHITELIST_ALLOW_CREATE="${HYTALE_WHITELIST_ALLOW_CREATE:-1}"
HYTALE_WHITELIST_APPLY_MODE="${HYTALE_WHITELIST_APPLY_MODE:-once}"
HYTALE_WHITELIST_JSON="${HYTALE_WHITELIST_JSON:-}"
HYTALE_WHITELIST_JSON_B64="${HYTALE_WHITELIST_JSON_B64:-}"
HYTALE_WHITELIST_JSON_FILE="${HYTALE_WHITELIST_JSON_FILE:-}"

HYTALE_BANS_PATH="${HYTALE_BANS_PATH:-}"
HYTALE_BANS_MODE="${HYTALE_BANS_MODE:-replace}"
HYTALE_BANS_ALLOW_CREATE="${HYTALE_BANS_ALLOW_CREATE:-1}"
HYTALE_BANS_APPLY_MODE="${HYTALE_BANS_APPLY_MODE:-once}"
HYTALE_BANS_JSON="${HYTALE_BANS_JSON:-}"
HYTALE_BANS_JSON_B64="${HYTALE_BANS_JSON_B64:-}"
HYTALE_BANS_JSON_FILE="${HYTALE_BANS_JSON_FILE:-}"

HYTALE_PERMISSIONS_PATH="${HYTALE_PERMISSIONS_PATH:-}"
HYTALE_PERMISSIONS_MODE="${HYTALE_PERMISSIONS_MODE:-replace}"
HYTALE_PERMISSIONS_ALLOW_CREATE="${HYTALE_PERMISSIONS_ALLOW_CREATE:-1}"
HYTALE_PERMISSIONS_APPLY_MODE="${HYTALE_PERMISSIONS_APPLY_MODE:-once}"
HYTALE_PERMISSIONS_JSON="${HYTALE_PERMISSIONS_JSON:-}"
HYTALE_PERMISSIONS_JSON_B64="${HYTALE_PERMISSIONS_JSON_B64:-}"
HYTALE_PERMISSIONS_JSON_FILE="${HYTALE_PERMISSIONS_JSON_FILE:-}"

JAVA_OPTS="${JAVA_OPTS:--Xms1G -Xmx4G}"

SERVER_DIR="${HYTALE_SERVER_DIR:-${DATA_DIR}/Server}"
ASSETS_PATH="${HYTALE_ASSETS_PATH:-${DATA_DIR}/Assets.zip}"
JAR_PATH="${HYTALE_JAR_PATH:-${SERVER_DIR}/HytaleServer.jar}"

CONSOLE_FILE="${HYTALE_CONSOLE_FILE:-${DATA_DIR}/console.commands}"
AUTH_STATE_PATH="${HYTALE_AUTH_STATE_PATH:-${HYTALE_AUTH_STATE_DIR}/state.json}"
VERSION_MARKER_PATH="${HYTALE_VERSION_MARKER_PATH:-${DATA_DIR}/.hytale-flux.version.json}"

msg() { printf '%s\n' "$*"; }

bool_true() {
  local value="${1:-}"
  value="${value,,}"
  case "$value" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_int() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    return 0
  fi
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    msg "Invalid ${name}=${value} (expected integer)"
    return 1
  fi
}

read_config_patch_json() {
  if [[ -n "$HYTALE_CONFIG_JSON_FILE" ]]; then
    cat "$HYTALE_CONFIG_JSON_FILE"
    return 0
  fi
  if [[ -n "$HYTALE_CONFIG_JSON_B64" ]]; then
    printf '%s' "$HYTALE_CONFIG_JSON_B64" | base64 -d
    return 0
  fi
  if [[ -n "$HYTALE_CONFIG_JSON" ]]; then
    printf '%s' "$HYTALE_CONFIG_JSON"
    return 0
  fi
  return 1
}

read_env_prefixed_config_patch_json() {
  CONFIG_ENV_PREFIX="$HYTALE_CONFIG_ENV_PREFIX" python3 - <<'PY'
import json
import os
import re
import sys

prefix = os.environ.get("CONFIG_ENV_PREFIX", "HYTALE_CFG__")

def infer_value(raw: str):
    val = raw.strip()
    low = val.lower()
    if low in ("true", "false"):
        return low == "true"
    if low in ("null", "none"):
        return None
    if val.startswith("{") or val.startswith("["):
        try:
            return json.loads(val)
        except Exception:
            return raw
    if re.fullmatch(r"[+-]?\d+", val):
        try:
            return int(val, 10)
        except Exception:
            return raw
    if re.fullmatch(r"[+-]?\d+\.\d+", val):
        try:
            return float(val)
        except Exception:
            return raw
    return raw

patch = {}
found = False

for key, raw_value in os.environ.items():
    if not key.startswith(prefix):
        continue
    path = key[len(prefix):]
    parts = [p for p in path.split("__") if p]
    if not parts:
        continue
    found = True
    cursor = patch
    for part in parts[:-1]:
        if part not in cursor or not isinstance(cursor[part], dict):
            cursor[part] = {}
        cursor = cursor[part]
    cursor[parts[-1]] = infer_value(raw_value)

if not found:
    sys.exit(1)

print(json.dumps(patch, sort_keys=True))
PY
}

merge_json_patches() {
  local base_json="$1"
  local override_json="$2"
  BASE_JSON="$base_json" OVERRIDE_JSON="$override_json" python3 - <<'PY'
import json
import os
import sys

base_raw = os.environ.get("BASE_JSON", "")
override_raw = os.environ.get("OVERRIDE_JSON", "")

def deep_merge(existing, patch):
    if isinstance(existing, dict) and isinstance(patch, dict):
        out = dict(existing)
        for key, value in patch.items():
            if key in out:
                out[key] = deep_merge(out[key], value)
            else:
                out[key] = value
        return out
    return patch

base = json.loads(base_raw) if base_raw.strip() else {}
override = json.loads(override_raw) if override_raw.strip() else {}
merged = deep_merge(base, override)
print(json.dumps(merged, sort_keys=True))
PY
}

read_explicit_json_patch() {
  local json_file="$1"
  local json_b64="$2"
  local json_raw="$3"

  if [[ -n "$json_file" ]]; then
    cat "$json_file"
    return 0
  fi
  if [[ -n "$json_b64" ]]; then
    printf '%s' "$json_b64" | base64 -d
    return 0
  fi
  if [[ -n "$json_raw" ]]; then
    printf '%s' "$json_raw"
    return 0
  fi
  return 1
}

apply_json_config_patch() {
  local config_path="$1"
  local patch_json="$2"

  local apply_mode="${HYTALE_CONFIG_APPLY_MODE,,}"
  if [[ "$apply_mode" != "always" && "$apply_mode" != "once" ]]; then
    msg "Invalid HYTALE_CONFIG_APPLY_MODE=${HYTALE_CONFIG_APPLY_MODE} (expected 'always' or 'once')"
    return 1
  fi

  local mode="${HYTALE_CONFIG_MODE,,}"
  if [[ "$mode" != "merge" && "$mode" != "replace" ]]; then
    msg "Invalid HYTALE_CONFIG_MODE=${HYTALE_CONFIG_MODE} (expected 'merge' or 'replace')"
    return 1
  fi

  if [[ "$mode" == "merge" && ! -s "$config_path" ]] && ! bool_true "$HYTALE_CONFIG_ALLOW_CREATE"; then
    msg "Config file is missing or empty at ${config_path}; skipping patch (set HYTALE_CONFIG_ALLOW_CREATE=1 to create)."
    return 0
  fi

  local stamp_file="${DATA_DIR}/.hytale-flux-config.patch.sha256"
  local patch_hash
  patch_hash="$(printf '%s' "$patch_json" | sha256sum | awk '{print $1}')"

  if [[ "$apply_mode" == "once" && -f "$stamp_file" ]]; then
    local previous_hash
    previous_hash="$(cat "$stamp_file" 2>/dev/null || true)"
    if [[ "$previous_hash" == "$patch_hash" ]]; then
      msg "Config patch already applied (HYTALE_CONFIG_APPLY_MODE=once)."
      return 0
    fi
  fi

  msg "Patching ${config_path} (mode: ${HYTALE_CONFIG_MODE}, apply: ${HYTALE_CONFIG_APPLY_MODE})"
  CONFIG_PATH="$config_path" CONFIG_PATCH_JSON="$patch_json" CONFIG_MODE="$mode" python3 - <<'PY'
import json
import os
import sys

config_path = os.environ["CONFIG_PATH"]
patch_raw = os.environ["CONFIG_PATCH_JSON"]
mode = os.environ.get("CONFIG_MODE", "merge").lower()

def deep_merge(existing, patch):
    if isinstance(existing, dict) and isinstance(patch, dict):
        out = dict(existing)
        for key, value in patch.items():
            if key in out:
                out[key] = deep_merge(out[key], value)
            else:
                out[key] = value
        return out
    return patch

try:
    patch = json.loads(patch_raw)
except Exception as e:
    print(f"Invalid JSON patch provided (HYTALE_CONFIG_*): {e}", file=sys.stderr)
    sys.exit(2)

existing = {}
try:
    with open(config_path, "r", encoding="utf-8") as f:
        raw = f.read()
    if raw.strip():
        existing = json.loads(raw)
except FileNotFoundError:
    existing = {}
except Exception as e:
    print(f"Unable to read/parse existing config at {config_path}: {e}", file=sys.stderr)
    sys.exit(3)

if mode == "replace":
    merged = patch
else:
    merged = deep_merge(existing, patch)

tmp_path = f"{config_path}.tmp"
try:
    os.makedirs(os.path.dirname(config_path) or ".", exist_ok=True)
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, config_path)
except Exception as e:
    print(f"Failed writing patched config to {config_path}: {e}", file=sys.stderr)
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    sys.exit(4)
PY

  echo "$patch_hash" > "$stamp_file"
}

server_name_patch_json() {
  local name_value="$1"
  local key="$2"

  SERVER_NAME="$name_value" SERVER_NAME_KEY="$key" python3 - <<'PY'
import json
import os

name = os.environ.get("SERVER_NAME", "")
key = os.environ.get("SERVER_NAME_KEY", "ServerName")

print(json.dumps({key: name}, sort_keys=True))
PY
}

apply_json_patch_file() {
  local name="$1"
  local file_path="$2"
  local patch_json="$3"
  local mode="$4"
  local allow_create="$5"
  local apply_mode="$6"
  local allow_create_hint="${7:-}"

  local apply_mode_normalized="${apply_mode,,}"
  if [[ "$apply_mode_normalized" != "always" && "$apply_mode_normalized" != "once" ]]; then
    msg "Invalid apply mode for ${name}: ${apply_mode} (expected 'always' or 'once')"
    return 1
  fi

  local mode_normalized="${mode,,}"
  if [[ "$mode_normalized" != "merge" && "$mode_normalized" != "replace" ]]; then
    msg "Invalid mode for ${name}: ${mode} (expected 'merge' or 'replace')"
    return 1
  fi

  if [[ "$mode_normalized" == "merge" && ! -s "$file_path" ]] && ! bool_true "$allow_create"; then
    if [[ -n "$allow_create_hint" ]]; then
      msg "File is missing or empty at ${file_path}; skipping ${name} patch (set ${allow_create_hint}=1 to create)."
    else
      msg "File is missing or empty at ${file_path}; skipping ${name} patch."
    fi
    return 0
  fi

  local stamp_file="${DATA_DIR}/.hytale-flux-${name}.patch.sha256"
  local patch_hash
  patch_hash="$(printf '%s' "$patch_json" | sha256sum | awk '{print $1}')"

  if [[ "$apply_mode_normalized" == "once" && -f "$stamp_file" ]]; then
    local previous_hash
    previous_hash="$(cat "$stamp_file" 2>/dev/null || true)"
    if [[ "$previous_hash" == "$patch_hash" ]]; then
      return 0
    fi
  fi

  msg "Patching ${file_path} (${name}, mode: ${mode_normalized}, apply: ${apply_mode_normalized})"
  CONFIG_PATH="$file_path" CONFIG_PATCH_JSON="$patch_json" CONFIG_MODE="$mode_normalized" python3 - <<'PY'
import json
import os
import sys

config_path = os.environ["CONFIG_PATH"]
patch_raw = os.environ["CONFIG_PATCH_JSON"]
mode = os.environ.get("CONFIG_MODE", "replace").lower()

def deep_merge(existing, patch):
    if isinstance(existing, dict) and isinstance(patch, dict):
        out = dict(existing)
        for key, value in patch.items():
            if key in out:
                out[key] = deep_merge(out[key], value)
            else:
                out[key] = value
        return out
    return patch

try:
    patch = json.loads(patch_raw)
except Exception as e:
    print(f"Invalid JSON patch: {e}", file=sys.stderr)
    sys.exit(2)

existing = {}
try:
    with open(config_path, "r", encoding="utf-8") as f:
        raw = f.read()
    if raw.strip():
        existing = json.loads(raw)
except FileNotFoundError:
    existing = {}
except Exception as e:
    print(f"Unable to read/parse existing file at {config_path}: {e}", file=sys.stderr)
    sys.exit(3)

if mode == "replace":
    merged = patch
else:
    merged = deep_merge(existing, patch)

tmp_path = f"{config_path}.tmp"
try:
    os.makedirs(os.path.dirname(config_path) or ".", exist_ok=True)
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, config_path)
except Exception as e:
    print(f"Failed writing patched file to {config_path}: {e}", file=sys.stderr)
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    sys.exit(4)
PY

  echo "$patch_hash" > "$stamp_file"
}

render_startup_commands() {
  local apply_mode="${HYTALE_STARTUP_COMMANDS_APPLY_MODE,,}"
  if [[ "$apply_mode" != "always" && "$apply_mode" != "once" ]]; then
    msg "Invalid HYTALE_STARTUP_COMMANDS_APPLY_MODE=${HYTALE_STARTUP_COMMANDS_APPLY_MODE} (expected 'always' or 'once')"
    return 1
  fi

  local rendered
  rendered="$(printf '%b' "$HYTALE_STARTUP_COMMANDS")"

  if [[ -z "${rendered//[[:space:]]/}" ]]; then
    return 1
  fi

  local stamp_file="${DATA_DIR}/.hytale-flux-startup.commands.sha256"
  local hash
  hash="$(printf '%s' "$rendered" | sha256sum | awk '{print $1}')"

  if [[ "$apply_mode" == "once" && -f "$stamp_file" ]]; then
    local previous_hash
    previous_hash="$(cat "$stamp_file" 2>/dev/null || true)"
    if [[ "$previous_hash" == "$hash" ]]; then
      return 1
    fi
  fi

  echo "$hash" > "$stamp_file"
  printf '%s' "$rendered"
  return 0
}

prepare_cache_dirs() {
  if ! bool_true "$HYTALE_EPHEMERAL_CACHE"; then
    return 0
  fi

  if [[ -z "$HYTALE_CACHE_DIR" ]]; then
    msg "HYTALE_EPHEMERAL_CACHE=1 but HYTALE_CACHE_DIR is empty"
    return 1
  fi

  mkdir -p "$HYTALE_CACHE_DIR"
  rm -rf "${SERVER_DIR}/.cache"
  ln -s "$HYTALE_CACHE_DIR" "${SERVER_DIR}/.cache"
}

ensure_hytale_files() {
  if [[ -f "$JAR_PATH" && -f "$ASSETS_PATH" ]]; then
    return 0
  fi

  if [[ "$HYTALE_AUTO_DOWNLOAD" != "1" ]]; then
    return 1
  fi

  if [[ ! -x /opt/hytale/hytale-downloader ]]; then
    msg "HYTALE_AUTO_DOWNLOAD=1 is set, but hytale-downloader is not available in this image."
    msg "Place the Hytale Server files manually under ${DATA_DIR}/Server and ${DATA_DIR}/Assets.zip."
    return 1
  fi

  if [[ "$(uname -m)" != "x86_64" && "$(uname -m)" != "amd64" ]]; then
    msg "HYTALE_AUTO_DOWNLOAD=1 is set, but hytale-downloader is only bundled for linux/amd64."
    msg "Place the Hytale Server files manually under ${DATA_DIR}/Server and ${DATA_DIR}/Assets.zip."
    return 1
  fi

  local game_zip="${DATA_DIR}/game.zip"
  local extract_dir="${DATA_DIR}/.extract"

  local zip_layout=""
  local asset_entry=""
  local server_prefix=""

  mkdir -p "$DATA_DIR"
  cd "$DATA_DIR"

  if [[ -s "$game_zip" ]]; then
    msg "Found existing ${game_zip}; attempting extraction..."
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    if extract_hytale_archive "$game_zip" "$extract_dir"; then
      if latest_version="$(hytale_downloader_print_version 2>/dev/null)"; then
        write_version_marker "$latest_version" || true
      fi
      return 0
    fi
    msg "Existing archive extraction failed; re-downloading..."
  fi

  msg "Hytale files not found. Running hytale-downloader (patchline: ${HYTALE_PATCHLINE})..."
  msg "This will print a device-login URL + code. Complete it in your browser to start the download."
  /opt/hytale/hytale-downloader -patchline "$HYTALE_PATCHLINE" -download-path "$game_zip"

  if [[ ! -f "$game_zip" ]]; then
    msg "Download completed but ${game_zip} was not created."
    return 1
  fi

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  if ! extract_hytale_archive "$game_zip" "$extract_dir"; then
    msg "Unzip the archive manually and place the Server folder and Assets.zip into ${DATA_DIR}."
    return 1
  fi

  if ! bool_true "$HYTALE_KEEP_DOWNLOAD_ARCHIVE"; then
    rm -rf "$extract_dir"
    rm -f "$game_zip"
  fi

  msg "Hytale files ready:"
  msg "- ${JAR_PATH}"
  msg "- ${ASSETS_PATH}"

  local latest_version=""
  if latest_version="$(hytale_downloader_print_version 2>/dev/null)"; then
    write_version_marker "$latest_version" || true
  fi
}

detect_hytale_archive_layout() {
  local zip_path="$1"

  ZIP_PATH="$zip_path" python3 - <<'PY'
import os
import re
import sys
import zipfile

zip_path = os.environ.get("ZIP_PATH")
if not zip_path:
  raise SystemExit(1)

with zipfile.ZipFile(zip_path) as zf:
  names = zf.namelist()

assets = [n for n in names if re.search(r'(^|/)Assets\.zip$', n, re.IGNORECASE)]
if not assets:
  raise SystemExit(2)
asset_entry = assets[0]

roots = set()
for name in names:
  lower = name.lower()
  if lower.startswith("server/"):
    roots.add(name.split("/", 1)[0] + "/")
  idx = lower.find("/server/")
  if idx != -1:
    roots.add(name[: idx + len("/server/")])

if not roots:
  raise SystemExit(3)

asset_parent = asset_entry.rsplit("/", 1)[0] if "/" in asset_entry else ""

candidate_roots = []
if asset_parent:
  prefix = (asset_parent + "/").lower()
  for root in roots:
    if root.lower().startswith(prefix):
      candidate_roots.append(root)

server_root = None
if candidate_roots:
  server_root = sorted(candidate_roots, key=len)[0]
else:
  jar_roots = []
  for root in roots:
    jar = root + "HytaleServer.jar"
    if any(n.lower() == jar.lower() for n in names):
      jar_roots.append(root)
  if jar_roots:
    server_root = sorted(jar_roots, key=len)[0]
  else:
    server_root = sorted(roots, key=len)[0]

if not server_root:
  raise SystemExit(4)

print(asset_entry)
print(server_root)
PY
}

extract_hytale_archive() {
  local zip_path="$1"
  local extract_dir="$2"

  msg "Extracting Server/ + Assets.zip from ${zip_path}..."

  local zip_layout=""
  if ! zip_layout="$(detect_hytale_archive_layout "$zip_path" 2>/dev/null)"; then
    msg "Unable to find Assets.zip and/or Server folder inside ${zip_path}."
    return 1
  fi

  local asset_entry=""
  local server_prefix=""
  asset_entry="$(printf '%s\n' "$zip_layout" | sed -n '1p' | tr -d '\r')"
  server_prefix="$(printf '%s\n' "$zip_layout" | sed -n '2p' | tr -d '\r')"

  if [[ -z "$asset_entry" || -z "$server_prefix" ]]; then
    msg "Archive layout detection failed for ${zip_path}."
    return 1
  fi

  unzip -q "$zip_path" -d "$extract_dir" "$asset_entry" "${server_prefix}*"

  if [[ ! -f "${extract_dir}/${asset_entry}" ]]; then
    msg "Assets.zip did not extract as expected."
    return 1
  fi
  if [[ ! -d "${extract_dir}/${server_prefix}" ]]; then
    msg "Server/ did not extract as expected."
    return 1
  fi

  rm -rf "$SERVER_DIR"
  mkdir -p "$SERVER_DIR"
  cp -a "${extract_dir}/${server_prefix}." "$SERVER_DIR/"
  cp -f "${extract_dir}/${asset_entry}" "$ASSETS_PATH"
  return 0
}

hytale_downloader_print_version() {
  if [[ ! -x /opt/hytale/hytale-downloader ]]; then
    return 1
  fi
  local version_line=""
  if version_line="$(/opt/hytale/hytale-downloader -patchline "$HYTALE_PATCHLINE" -print-version 2>/dev/null | head -n 1)"; then
    version_line="$(printf '%s' "$version_line" | tr -d '\r' | xargs || true)"
    if [[ -n "${version_line//[[:space:]]/}" ]]; then
      printf '%s' "$version_line"
      return 0
    fi
  fi
  return 1
}

read_version_marker() {
  if [[ ! -f "$VERSION_MARKER_PATH" ]]; then
    return 1
  fi

  VERSION_MARKER_PATH="$VERSION_MARKER_PATH" python3 - <<'PY'
import json
import os

path = os.environ.get("VERSION_MARKER_PATH")
with open(path, "r", encoding="utf-8") as f:
  data = json.load(f)
patchline = str(data.get("patchline", "")).strip()
version = str(data.get("version", "")).strip()
print(patchline)
print(version)
PY
}

write_version_marker() {
  local version="$1"

  VERSION_MARKER_PATH="$VERSION_MARKER_PATH" PATCHLINE="$HYTALE_PATCHLINE" VERSION="$version" python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

path = Path(os.environ["VERSION_MARKER_PATH"])
data = {
  "patchline": os.environ.get("PATCHLINE", "").strip(),
  "version": os.environ.get("VERSION", "").strip(),
  "updatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_suffix(path.suffix + ".tmp")
tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
tmp.replace(path)
PY
}

maybe_auto_update_hytale_files() {
  if ! bool_true "$HYTALE_AUTO_UPDATE"; then
    return 0
  fi

  if [[ ! -x /opt/hytale/hytale-downloader ]]; then
    msg "HYTALE_AUTO_UPDATE=1 is set, but hytale-downloader is not available in this image."
    return 0
  fi

  local latest_version=""
  if ! latest_version="$(hytale_downloader_print_version)"; then
    msg "Unable to determine latest Hytale version; skipping auto-update."
    return 0
  fi

  local marker_out="" current_patchline="" current_version=""
  if marker_out="$(read_version_marker 2>/dev/null)"; then
    current_patchline="$(printf '%s\n' "$marker_out" | sed -n '1p' | tr -d '\r')"
    current_version="$(printf '%s\n' "$marker_out" | sed -n '2p' | tr -d '\r')"
  fi

  if [[ "$current_patchline" == "$HYTALE_PATCHLINE" && "$current_version" == "$latest_version" ]]; then
    msg "Hytale files already up to date (${latest_version})."
    return 0
  fi

  msg "Updating Hytale files (patchline: ${HYTALE_PATCHLINE}, version: ${latest_version})..."

  local game_zip="${DATA_DIR}/game.zip"
  local extract_dir="${DATA_DIR}/.extract"

  mkdir -p "$DATA_DIR"
  cd "$DATA_DIR"

  /opt/hytale/hytale-downloader -patchline "$HYTALE_PATCHLINE" -download-path "$game_zip"

  if [[ ! -f "$game_zip" ]]; then
    msg "Auto-update completed but ${game_zip} was not created."
    return 1
  fi

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  local asset_entry
  local zip_layout=""
  if ! zip_layout="$(detect_hytale_archive_layout "$game_zip" 2>/dev/null)"; then
    msg "Unable to find Assets.zip and/or Server folder inside ${game_zip}."
    return 1
  fi
  asset_entry="$(printf '%s\n' "$zip_layout" | sed -n '1p' | tr -d '\r')"
  local server_prefix=""
  server_prefix="$(printf '%s\n' "$zip_layout" | sed -n '2p' | tr -d '\r')"

  unzip -q "$game_zip" -d "$extract_dir" "$asset_entry" "${server_prefix}*"

  if [[ ! -f "${extract_dir}/${asset_entry}" ]]; then
    msg "Assets.zip did not extract as expected."
    return 1
  fi
  if [[ ! -d "${extract_dir}/${server_prefix}" ]]; then
    msg "Server/ did not extract as expected."
    return 1
  fi

  cp -f "${extract_dir}/${asset_entry}" "$ASSETS_PATH"

  SRC_SERVER_DIR="${extract_dir}/${server_prefix}" DST_SERVER_DIR="$SERVER_DIR" SKIP_PATTERNS="$HYTALE_UPDATE_SKIP_PATTERNS" python3 - <<'PY'
import os
import shutil
from pathlib import Path, PurePosixPath

src = Path(os.environ["SRC_SERVER_DIR"]).resolve()
dst = Path(os.environ["DST_SERVER_DIR"]).resolve()
patterns_raw = os.environ.get("SKIP_PATTERNS", "")
patterns = [p.strip() for p in patterns_raw.split(",") if p.strip()]

def should_skip(rel_posix: str) -> bool:
    rel = PurePosixPath(rel_posix)
    for pat in patterns:
        if rel.match(pat):
            return True
    return False

for root, dirs, files in os.walk(src):
    rel_root = Path(root).relative_to(src)
    rel_root_posix = rel_root.as_posix()

    kept_dirs = []
    for d in dirs:
        rel_dir = (rel_root / d).as_posix()
        if should_skip(rel_dir) or should_skip(rel_dir + "/"):
            continue
        kept_dirs.append(d)
    dirs[:] = kept_dirs

    for filename in files:
        rel_file = (rel_root / filename).as_posix()
        if should_skip(rel_file):
            continue
        src_path = Path(root) / filename
        dst_path = dst / rel_root / filename
        dst_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_path, dst_path)
PY

  write_version_marker "$latest_version" || true

  if ! bool_true "$HYTALE_KEEP_DOWNLOAD_ARCHIVE"; then
    rm -rf "$extract_dir"
    rm -f "$game_zip"
  fi

  msg "Auto-update complete."
}

ensure_hytale_auth() {
  if [[ "$HYTALE_AUTH_MODE" != "authenticated" ]]; then
    return 0
  fi

  if [[ -n "${HYTALE_SERVER_SESSION_TOKEN:-}" && -n "${HYTALE_SERVER_IDENTITY_TOKEN:-}" ]]; then
    return 0
  fi

  if ! bool_true "$HYTALE_AUTH_AUTO"; then
    return 0
  fi

  if [[ ! -x /opt/hytale/hytale-auth ]]; then
    msg "HYTALE_AUTH_AUTO=1 is set, but /opt/hytale/hytale-auth is missing."
    return 1
  fi

  mkdir -p "$HYTALE_AUTH_STATE_DIR"

  msg "Ensuring Hytale authentication (device login may be required)..."
  if ! /opt/hytale/hytale-auth --state-path "$AUTH_STATE_PATH" ensure --client-id "$HYTALE_AUTH_CLIENT_ID"; then
    msg ""
    msg "Authentication was not completed."
    msg "If you have multiple Hytale profiles, set one of:"
    msg "- HYTALE_AUTH_PROFILE_UUID"
    msg "- HYTALE_AUTH_PROFILE_USERNAME"
    msg ""
    return 1
  fi

  mapfile -t __tokens < <(AUTH_STATE_PATH="$AUTH_STATE_PATH" python3 - <<'PY'
import json
import os

path = os.environ.get("AUTH_STATE_PATH")
if not path:
  raise SystemExit(1)

with open(path, "r", encoding="utf-8") as f:
  state = json.load(f)

session = state.get("session") or {}
session_token = str(session.get("sessionToken", "")).strip()
identity_token = str(session.get("identityToken", "")).strip()

if not session_token or not identity_token:
  raise SystemExit(1)

print(session_token)
print(identity_token)
PY
)

  if [[ ${#__tokens[@]} -lt 2 ]]; then
    msg "Auth state is missing session tokens at ${AUTH_STATE_PATH}"
    return 1
  fi

  export HYTALE_SERVER_SESSION_TOKEN="${__tokens[0]}"
  export HYTALE_SERVER_IDENTITY_TOKEN="${__tokens[1]}"
  return 0
}

mkdir -p "$DATA_DIR"

run_mode="${HYTALE_RUN_MODE,,}"
if [[ "$run_mode" == "auth" ]]; then
  exec /opt/hytale/hytale-auth --state-path "$AUTH_STATE_PATH" ensure --client-id "$HYTALE_AUTH_CLIENT_ID"
fi
if [[ "$run_mode" == "auth-status" ]]; then
  exec /opt/hytale/hytale-auth --state-path "$AUTH_STATE_PATH" status
fi
if [[ "$run_mode" != "server" ]]; then
  msg "Invalid HYTALE_RUN_MODE=${HYTALE_RUN_MODE} (expected 'server', 'auth', or 'auth-status')"
  exit 1
fi

if [[ "$HYTALE_CONSOLE_MODE" != "file" && "$HYTALE_CONSOLE_MODE" != "none" ]]; then
  msg "Invalid HYTALE_CONSOLE_MODE=${HYTALE_CONSOLE_MODE} (expected 'file' or 'none')"
  exit 1
fi

if [[ "$HYTALE_CONSOLE_MODE" == "file" ]]; then
  touch "$CONSOLE_FILE"
  if bool_true "$HYTALE_CONSOLE_CLEAR_ON_START"; then
    : > "$CONSOLE_FILE"
  fi
fi

if ! ensure_hytale_files; then
  msg "Missing Hytale server files."
  msg ""
  msg "Expected:"
  msg "- ${JAR_PATH}"
  msg "- ${ASSETS_PATH}"
  msg ""
  msg "Options:"
  msg "1) Auto-download (linux/amd64 only): set HYTALE_AUTO_DOWNLOAD=1 and restart the container."
  msg "2) Manual: copy the official Hytale Server folder and Assets.zip into ${DATA_DIR}."
  msg ""
  msg "This container will now idle so you can populate ${DATA_DIR}."
  exec sleep infinity
fi

maybe_auto_update_hytale_files

if [[ -n "$HYTALE_PORT" ]]; then
  require_int "HYTALE_PORT" "$HYTALE_PORT"
  HYTALE_BIND="0.0.0.0:${HYTALE_PORT}"
fi

HYTALE_AUTH_MODE="${HYTALE_AUTH_MODE,,}"
if [[ "$HYTALE_AUTH_MODE" != "authenticated" && "$HYTALE_AUTH_MODE" != "offline" ]]; then
  msg "Invalid HYTALE_AUTH_MODE=${HYTALE_AUTH_MODE} (expected 'authenticated' or 'offline')"
  exit 1
fi

args=(--assets "$ASSETS_PATH" --bind "$HYTALE_BIND")
if [[ "$HYTALE_AUTH_MODE" == "offline" ]]; then
  args+=(--auth-mode offline)
fi

if bool_true "$HYTALE_ACCEPT_EARLY_PLUGINS"; then
  args+=(--accept-early-plugins)
fi

if bool_true "$HYTALE_ALLOW_OP"; then
  args+=(--allow-op)
fi

if bool_true "$HYTALE_BACKUP"; then
  args+=(--backup)
  if [[ -n "$HYTALE_BACKUP_DIR" ]]; then
    mkdir -p "$HYTALE_BACKUP_DIR"
    args+=(--backup-dir "$HYTALE_BACKUP_DIR")
  fi
  if [[ -n "$HYTALE_BACKUP_FREQUENCY" ]]; then
    require_int "HYTALE_BACKUP_FREQUENCY" "$HYTALE_BACKUP_FREQUENCY"
    args+=(--backup-frequency "$HYTALE_BACKUP_FREQUENCY")
  fi
fi

config_path="${HYTALE_CONFIG_PATH:-${SERVER_DIR}/config.json}"
patch_json=""
if [[ -n "${HYTALE_SERVER_NAME//[[:space:]]/}" ]]; then
  patch_json="$(server_name_patch_json "$HYTALE_SERVER_NAME" "$HYTALE_SERVER_NAME_CONFIG_KEY")"
fi
if env_patch_json="$(read_env_prefixed_config_patch_json 2>/dev/null)"; then
  if [[ -n "$patch_json" ]]; then
    patch_json="$(merge_json_patches "$patch_json" "$env_patch_json")"
  else
    patch_json="$env_patch_json"
  fi
fi
if explicit_patch_json="$(read_config_patch_json 2>/dev/null)"; then
  if [[ -n "$patch_json" ]]; then
    patch_json="$(merge_json_patches "$patch_json" "$explicit_patch_json")"
  else
    patch_json="$explicit_patch_json"
  fi
fi
if [[ -n "$patch_json" ]]; then
  apply_json_config_patch "$config_path" "$patch_json"
fi

whitelist_path="${HYTALE_WHITELIST_PATH:-${SERVER_DIR}/whitelist.json}"
if whitelist_patch_json="$(read_explicit_json_patch "$HYTALE_WHITELIST_JSON_FILE" "$HYTALE_WHITELIST_JSON_B64" "$HYTALE_WHITELIST_JSON")"; then
  apply_json_patch_file "whitelist" "$whitelist_path" "$whitelist_patch_json" "$HYTALE_WHITELIST_MODE" "$HYTALE_WHITELIST_ALLOW_CREATE" "$HYTALE_WHITELIST_APPLY_MODE" "HYTALE_WHITELIST_ALLOW_CREATE"
fi

bans_path="${HYTALE_BANS_PATH:-${SERVER_DIR}/bans.json}"
if bans_patch_json="$(read_explicit_json_patch "$HYTALE_BANS_JSON_FILE" "$HYTALE_BANS_JSON_B64" "$HYTALE_BANS_JSON")"; then
  apply_json_patch_file "bans" "$bans_path" "$bans_patch_json" "$HYTALE_BANS_MODE" "$HYTALE_BANS_ALLOW_CREATE" "$HYTALE_BANS_APPLY_MODE" "HYTALE_BANS_ALLOW_CREATE"
fi

permissions_path="${HYTALE_PERMISSIONS_PATH:-${SERVER_DIR}/permissions.json}"
if permissions_patch_json="$(read_explicit_json_patch "$HYTALE_PERMISSIONS_JSON_FILE" "$HYTALE_PERMISSIONS_JSON_B64" "$HYTALE_PERMISSIONS_JSON")"; then
  apply_json_patch_file "permissions" "$permissions_path" "$permissions_patch_json" "$HYTALE_PERMISSIONS_MODE" "$HYTALE_PERMISSIONS_ALLOW_CREATE" "$HYTALE_PERMISSIONS_APPLY_MODE" "HYTALE_PERMISSIONS_ALLOW_CREATE"
fi

if [[ -n "$HYTALE_EXTRA_ARGS" ]]; then
  read -r -a extra_args <<< "$HYTALE_EXTRA_ARGS"
  if [[ ${#extra_args[@]} -gt 0 ]]; then
    args+=("${extra_args[@]}")
  fi
fi

prepare_cache_dirs

if ! ensure_hytale_auth; then
  msg ""
  msg "Hytale auth is not ready."
  msg "Options:"
  msg "1) Enable the built-in helper: set HYTALE_AUTH_AUTO=1 and restart."
  msg "2) Use server console auth: echo '/auth login device' >> ${CONSOLE_FILE}"
  msg ""
  msg "This container will now idle so you can complete authentication."
  exec sleep infinity
fi

msg "Starting Hytale server..."
msg "- Bind: ${HYTALE_BIND} (UDP)"
msg "- Auth mode: ${HYTALE_AUTH_MODE}"
msg "- Data dir: ${DATA_DIR}"
if bool_true "$HYTALE_BACKUP"; then
  msg "- Backups: enabled (dir: ${HYTALE_BACKUP_DIR}${HYTALE_BACKUP_FREQUENCY:+, every ${HYTALE_BACKUP_FREQUENCY} min})"
else
  msg "- Backups: disabled"
fi
msg ""
if [[ "$HYTALE_CONSOLE_MODE" == "file" ]]; then
  msg "To send console commands (Flux-friendly), append a line to:"
  msg "  ${CONSOLE_FILE}"
  msg "Example:"
  msg "  echo '/auth login device' >> ${CONSOLE_FILE}"
  msg ""
fi

cd "$SERVER_DIR"
if [[ "$HYTALE_CONSOLE_MODE" == "file" ]]; then
  startup_file="/tmp/hytale-startup.commands"
  : > "$startup_file"
  if [[ -n "${HYTALE_STARTUP_COMMANDS//[[:space:]]/}" ]]; then
    if startup_rendered="$(render_startup_commands)"; then
      printf '%s\n' "$startup_rendered" > "$startup_file"
    fi
  fi
  exec java $JAVA_OPTS -jar "$JAR_PATH" "${args[@]}" < <({ cat "$startup_file"; tail -n 0 -F "$CONSOLE_FILE"; })
else
  exec java $JAVA_OPTS -jar "$JAR_PATH" "${args[@]}"
fi
