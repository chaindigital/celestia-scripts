#!/usr/bin/env bash
# Install a Celestia bridge node from the official celestia-node release and run it under systemd.
# The bridge reads blocks from a consensus node over gRPC (port 9090), e.g. one set up with install-node.sh <net> full.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-bridge.sh) mainnet
#
# Optional environment: CORE_IP (consensus node address), CORE_PORT (default 9090), ARCHIVAL (default true).
set -euo pipefail

CD_RAW="${CD_RAW:-https://raw.githubusercontent.com/chaindigital/celestia-scripts/main}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$here/common.sh" ]; then . "$here/common.sh"; else . <(curl -fsSL "$CD_RAW/common.sh"); fi

set_network "${1:-}"
CORE_IP="${CORE_IP:-}"
[ -n "$CORE_IP" ] || read -rp "Consensus node IP or host (gRPC): " CORE_IP
[ -n "$CORE_IP" ] || die "a consensus node address is required"
CORE_PORT="${CORE_PORT:-9090}"
ARCHIVAL="${ARCHIVAL:-true}"

say "Installing system packages"
sudo apt-get update -qq
sudo apt-get install -y -qq curl jq tar ca-certificates >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading celestia-node $NODE_VERSION"
fetch_release celestia-node "$NODE_VERSION" "celestia-node_Linux_$(arch_suffix).tar.gz" "$tmp/node"
install_bin "$tmp/node" celestia
celestia version

say "Initialising the bridge store"
# P2P_NETWORK_FLAG is empty on mainnet and "--p2p.network mocha" on mocha, so it is left unquoted.
# shellcheck disable=SC2086
celestia bridge init --core.ip "$CORE_IP" --core.port "$CORE_PORT" $P2P_NETWORK_FLAG

start="/usr/local/bin/celestia bridge start $P2P_NETWORK_FLAG"
[ "$ARCHIVAL" = "true" ] && start="$start --archival"
start="$start --metrics.tls=true --metrics --metrics.endpoint $OTEL_ENDPOINT"

write_service celestia-bridge "Celestia bridge node ($CHAIN_ID)" "$start"
sudo systemctl restart celestia-bridge

cat <<EOF

Done. celestia-node $NODE_VERSION bridge is running on $CHAIN_ID, reading from $CORE_IP:$CORE_PORT.

  logs:     sudo journalctl -u celestia-bridge -f -o cat
  firewall: sudo ufw allow 2121/tcp && sudo ufw allow 2121/udp
EOF
