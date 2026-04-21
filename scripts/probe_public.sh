#!/usr/bin/env bash
# Probe a public CVAT URL from a remote computer and pinpoint where it breaks.
# Run from your laptop / phone / any box with curl — no repo checkout needed on
# the target. Usage:
#
#   ./scripts/probe_public.sh https://samm.example.com
#   ./scripts/probe_public.sh samm.example.com         # https:// assumed
set -euo pipefail

RAW="${1:-}"
[[ -n "$RAW" ]] || { echo "usage: $0 <url-or-hostname>" >&2; exit 2; }

URL="$RAW"
[[ "$URL" =~ ^https?:// ]] || URL="https://$URL"

log()  { printf '\033[1;34m[probe]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[probe]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[probe]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[probe]\033[0m %s\n' "$*" >&2; }

extract_host() {
  printf '%s' "$URL" | sed -E 's|^https?://||; s|/.*$||; s|:.*$||'
}

resolve_host() {
  local host="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short "$host"
  elif command -v host >/dev/null 2>&1; then
    host "$host" 2>/dev/null | awk '/has address|has IPv6 address/ {print $NF}'
  elif command -v getent >/dev/null 2>&1; then
    getent hosts "$host" 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

probe_dns() {
  local host; host="$(extract_host)"
  log "DNS lookup: $host"
  local ips; ips="$(resolve_host "$host" | paste -sd, - || true)"
  if [[ -z "$ips" ]]; then
    fail "No A/AAAA records for $host. Cloudflare DNS entry missing or unproxied?"
    return 1
  fi
  ok "Resolved: $ips"
}

fetch_headers() {
  curl -sSI -m 10 --connect-timeout 5 "$URL" 2>&1 || true
}

header_value() {
  awk -v key="$1" -F': ' 'tolower($1)==tolower(key){print $2}' | tr -d '\r' | head -n1
}

diagnose_status() {
  local status="$1" cfray="$2"
  case "$status" in
    2??) ok "Root: HTTP $status — page reachable." ;;
    3??) warn "Root: HTTP $status redirect. Check Location header." ;;
    404) warn "Root: HTTP 404 — tunnel reached Traefik but no router matched (stale pull? run: ./stop.sh && ./start.sh)." ;;
    502) fail "HTTP 502 — Cloudflare reached your tunnel but origin didn't answer. cf-ray=$cfray" ;;
    503) fail "HTTP 503 — origin overloaded or not ready. cf-ray=$cfray" ;;
    520|521|522|523|524) fail "Cloudflare $status — origin unreachable from cloudflared. Check tunnel logs. cf-ray=$cfray" ;;
    530) fail "HTTP 530 — tunnel not connected to Cloudflare edge. Is cloudflared running? cf-ray=$cfray" ;;
    *)   warn "Root: HTTP $status (cf-ray=$cfray)" ;;
  esac
}

probe_root() {
  log "GET $URL"
  local headers; headers="$(fetch_headers)"
  if [[ -z "$headers" ]] || ! grep -qE '^HTTP/' <<<"$headers"; then
    fail "No HTTP response (TLS or connect error):"
    printf '%s\n' "$headers" | sed 's/^/    /'
    return 1
  fi
  printf '%s\n' "$headers" | sed 's/^/    /'
  local status; status="$(awk 'NR==1{print $2}' <<<"$headers")"
  local cfray;  cfray="$(header_value 'cf-ray' <<<"$headers")"
  local server; server="$(header_value 'server' <<<"$headers")"
  [[ "$server" == "cloudflare" ]] && log "Server header: cloudflare (tunnel/proxy in path)"
  diagnose_status "$status" "$cfray"
}

probe_api() {
  log "GET $URL/api/server/about"
  local body; body="$(curl -sS -m 10 --connect-timeout 5 "$URL/api/server/about" 2>&1 || true)"
  if grep -q '"version"' <<<"$body"; then
    local ver; ver="$(grep -oE '"version":"[^"]+"' <<<"$body" | head -n1)"
    ok "CVAT API responding: $ver"
    return
  fi
  warn "API endpoint didn't return JSON. First few lines of response:"
  printf '%s\n' "$body" | head -5 | sed 's/^/    /'
}

main() {
  probe_dns || exit 1
  probe_root
  probe_api
}

main "$@"
