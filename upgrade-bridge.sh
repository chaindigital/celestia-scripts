#!/usr/bin/env bash
# Upgrade a celestia-node bridge to the version pinned in common.sh.
# Check the release notes for breaking changes first: https://github.com/celestiaorg/celestia-node/releases
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/upgrade-bridge.sh) mainnet
set -euo pipefail

CD_RAW="${CD_RAW:-https://raw.githubusercontent.com/chaindigital/celestia-scripts/main}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$here/common.sh" ]; then . "$here/common.sh"; else . <(curl -fsSL "$CD_RAW/common.sh"); fi

set_network "${1:-}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading celestia-node $NODE_VERSION"
fetch_release celestia-node "$NODE_VERSION" "celestia-node_Linux_$(arch_suffix).tar.gz" "$tmp/node"

sudo systemctl stop celestia-bridge
install_bin "$tmp/node" celestia

say "Updating the bridge config"
# shellcheck disable=SC2086
celestia bridge config-update $P2P_NETWORK_FLAG

sudo systemctl start celestia-bridge

cat <<EOF

Upgraded to $(celestia version | head -n1).
  logs: sudo journalctl -u celestia-bridge -f -o cat
EOF
