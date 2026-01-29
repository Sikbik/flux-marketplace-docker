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

if ! pgrep -f 'AbioticFactorServer.*\.exe' >/dev/null 2>&1; then
  exit 1
fi

game_port="${AF_PORT:-7777}"
query_port="${AF_QUERY_PORT:-27015}"

udp_listening "${game_port}" || exit 1

# Some UE-based servers use an additional UDP port (often PORT+1). Abiotic Factor
# may not bind that extra port in all configurations. Keep it optional so health
# doesn't flap on perfectly working servers.
if [[ "${AF_HEALTHCHECK_PORT_2:-false}" =~ ^(1|true|yes|y|on)$ ]]; then
  udp_listening $((game_port + 1)) || exit 1
fi
udp_listening "${query_port}" || exit 1

exit 0
