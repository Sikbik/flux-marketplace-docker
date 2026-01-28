#!/usr/bin/env bash
set -euo pipefail

port_to_hex() {
  local port="$1"
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  printf '%04X' "${port}"
}

udp_listening() {
  local port="$1"
  local port_hex
  port_hex="$(port_to_hex "${port}")" || return 1

  if awk 'NR>1 {print $2}' /proc/net/udp | grep -qi ":${port_hex}$"; then
    return 0
  fi
  if awk 'NR>1 {print $2}' /proc/net/udp6 | grep -qi ":${port_hex}$"; then
    return 0
  fi

  return 1
}

if ! pgrep -f 'SonsOfTheForestDS\.exe' >/dev/null 2>&1; then
  exit 1
fi

game_port="${SOTF_GAME_PORT:-8766}"
query_port="${SOTF_QUERY_PORT:-27016}"
blob_port="${SOTF_BLOB_SYNC_PORT:-9700}"

udp_listening "${game_port}" || exit 1
udp_listening "${query_port}" || exit 1
udp_listening "${blob_port}" || exit 1

exit 0
