#!/usr/bin/env bash
# Open a URL in the default browser, cross-platform.
set -euo pipefail
URL="${1:?usage: open_browser.sh <url>}"

case "$(uname -s)" in
  Darwin) open "$URL" ;;
  Linux)  xdg-open "$URL" >/dev/null 2>&1 || echo "[kuzey] Open $URL in your browser." ;;
  MINGW*|MSYS*|CYGWIN*) start "$URL" ;;
  *) echo "[kuzey] Open $URL in your browser." ;;
esac
