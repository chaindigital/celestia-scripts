#!/usr/bin/env bash
# Upgrade celestia-appd, and Fibre if it is installed, to the version pinned in common.sh.
# Run the upgrade only when the network has announced it. Check the release notes first:
# https://github.com/celestiaorg/celestia-app/releases
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/upgrade-app.sh) mainnet
#
# Optional environment: CELESTIA_HOME, FIBRE_HOME.
set -euo pipefail

CD_RAW="${CD_RAW:-https://raw.githubusercontent.com/chaindigital/celestia-scripts/main}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$here/common.sh" ]; then . "$here/common.sh"; else . <(curl -fsSL "$CD_RAW/common.sh"); fi

set_network "${1:-}"
require_glibc 2.38
have_fibre=false
[ -x /usr/local/bin/fibre ] && have_fibre=true

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading celestia-app $APP_VERSION"
fetch_release celestia-app "$APP_VERSION" "celestia-app_Linux_$(arch_suffix).tar.gz" "$tmp/app"
if $have_fibre; then
  fetch_release celestia-app "$APP_VERSION" "fibre_Linux_$(arch_suffix).tar.gz" "$tmp/fibre"
fi

say "Installed: $(celestia-appd version 2>/dev/null || echo none)  ->  $APP_VERSION"

$have_fibre && sudo systemctl stop celestia-fibre
sudo systemctl stop celestia-appd
install_bin "$tmp/app" celestia-appd
$have_fibre && install_bin "$tmp/fibre" fibre

say "Adding new config settings (existing values are kept, backups are written)"
if $have_fibre; then
  celestia-appd config sync --home "$CELESTIA_HOME" --fibre-home "$FIBRE_HOME"
else
  celestia-appd config sync --home "$CELESTIA_HOME"
fi

sudo systemctl start celestia-appd
$have_fibre && sudo systemctl start celestia-fibre

cat <<EOF

Upgraded to $(celestia-appd version).
  logs: sudo journalctl -u celestia-appd -f -o cat
EOF
$have_fibre && echo "        sudo journalctl -u celestia-fibre -f -o cat"
exit 0
