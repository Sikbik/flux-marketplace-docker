#!/usr/bin/env bash
set -euo pipefail

ENS_QUERY_PORT="${ENS_QUERY_PORT:-15637}"

if ! pgrep -f "enshrouded_server\\.exe" >/dev/null 2>&1; then
  echo "enshrouded_server.exe process not running" >&2
  exit 1
fi

if command -v ss >/dev/null 2>&1; then
  if ! ss -lun 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\\[::\\]:)${ENS_QUERY_PORT}\$"; then
    echo "UDP port ${ENS_QUERY_PORT} not listening yet" >&2
    exit 1
  fi
fi

exit 0

