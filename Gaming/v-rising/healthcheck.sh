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

tcp_listening() {
  local port="$1"
  local port_hex
  port_hex="$(port_to_hex "${port}")" || return 1

  # State 0A == LISTEN
  if awk 'NR>1 {print $2, $4}' /proc/net/tcp | grep -qi ":${port_hex} .*0A$"; then
    return 0
  fi
  if awk 'NR>1 {print $2, $4}' /proc/net/tcp6 | grep -qi ":${port_hex} .*0A$"; then
    return 0
  fi
  return 1
}

if ! pgrep -f 'VRisingServer\.exe' >/dev/null 2>&1; then
  exit 1
fi

game_port="${VR_GAME_PORT:-9876}"
query_port="${VR_QUERY_PORT:-9877}"

udp_listening "${game_port}" || exit 1
udp_listening "${query_port}" || exit 1

if [[ "${VR_RCON_ENABLED:-false}" =~ ^(1|true|yes|y|on)$ ]]; then
  tcp_listening "${VR_RCON_PORT:-25575}" || exit 1
fi

exit 0
