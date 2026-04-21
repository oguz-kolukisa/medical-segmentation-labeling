#!/usr/bin/env bash
# Print the best host address to bake into CVAT_HOST.
#
# Priority:
#   1. Primary outbound IPv4 (what the kernel would use to reach the internet).
#   2. First address from `hostname -I` (any non-loopback interface).
#   3. "localhost" as a last-resort fallback.
set -euo pipefail

detect_primary_outbound_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
}

detect_first_lan_ip() {
  hostname -I 2>/dev/null | awk '{ print $1 }'
}

first_non_empty() {
  for candidate in "$@"; do
    [[ -n "$candidate" ]] && { printf '%s\n' "$candidate"; return; }
  done
}

main() {
  first_non_empty \
    "$(detect_primary_outbound_ip)" \
    "$(detect_first_lan_ip)" \
    "localhost"
}

main "$@"
