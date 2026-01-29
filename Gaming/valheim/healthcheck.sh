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

if ! pgrep -f 'valheim_server\.x86_64' >/dev/null 2>&1; then
  exit 1
fi

base_port="${VALHEIM_PORT:-2456}"
if [[ ! "${base_port}" =~ ^[0-9]+$ ]]; then
  base_port=2456
fi

udp_listening "${base_port}" || exit 1
udp_listening $((base_port + 1)) || exit 1

# Valheim is commonly documented as using 3 UDP ports (base, base+1, base+2),
# but in practice some builds/configurations may not bind base+2. Keep it
# optional so health doesn't flap on a working server.
if [[ "${VALHEIM_HEALTHCHECK_PORT_3:-false}" =~ ^(1|true|yes|y|on)$ ]]; then
  udp_listening $((base_port + 2)) || exit 1
fi

exit 0
