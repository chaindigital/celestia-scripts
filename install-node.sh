#!/usr/bin/env bash
# Install a Celestia consensus node, validator or full (RPC), from the official celestia-app release,
# restore it from the Chain Digital snapshot and run it under systemd.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-node.sh) mainnet validator
#   bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-node.sh) mocha full
#
# Optional environment: MONIKER, CELESTIA_HOME (default ~/.celestia-app), EXTERNAL_IP.
set -euo pipefail

CD_RAW="${CD_RAW:-https://raw.githubusercontent.com/chaindigital/celestia-scripts/main}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$here/common.sh" ]; then . "$here/common.sh"; else . <(curl -fsSL "$CD_RAW/common.sh"); fi

usage="usage: install-node.sh <mainnet|mocha> <validator|full>"
set_network "${1:-}"
ROLE="${2:-}"
case "$ROLE" in validator|full) ;; *) die "$usage" ;; esac

[ -e "$CELESTIA_HOME/config/genesis.json" ] && die "$CELESTIA_HOME already exists. Move it away or set CELESTIA_HOME."
MONIKER="${MONIKER:-}"
[ -n "$MONIKER" ] || read -rp "Node moniker: " MONIKER
[ -n "$MONIKER" ] || die "a moniker is required"

require_glibc 2.38

say "Installing system packages"
sudo apt-get update -qq
sudo apt-get install -y -qq curl jq tar zstd ca-certificates >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading celestia-app $APP_VERSION"
fetch_release celestia-app "$APP_VERSION" "celestia-app_Linux_$(arch_suffix).tar.gz" "$tmp/app"
install_bin "$tmp/app" celestia-appd
celestia-appd version

say "Initialising $CELESTIA_HOME for $CHAIN_ID"
celestia-appd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$CELESTIA_HOME" >/dev/null
curl -fsSL "$NETWORKS_RAW/$NETWORKS_DIR/genesis.json" -o "$CELESTIA_HOME/config/genesis.json"

CFG="$CELESTIA_HOME/config/config.toml"
APP="$CELESTIA_HOME/config/app.toml"
EXTERNAL_IP="${EXTERNAL_IP:-$(public_ip)}"

toml_set "$CFG" seeds             "\"$(list_from_networks seeds.txt)\""
toml_set "$CFG" persistent_peers  "\"$(list_from_networks peers.txt)\""
toml_set "$CFG" external_address  "\"$EXTERNAL_IP:26656\""
toml_set "$CFG" prometheus        "true"

toml_set "$APP" minimum-gas-prices "\"0.002utia\""
toml_set "$APP" app-db-backend     "\"pebbledb\""   # the Chain Digital snapshots are pebbledb

if [ "$ROLE" = "validator" ]; then
  # Keep RPC local. App gRPC stays on loopback: Fibre on this host reads from it.
  toml_set "$APP" pruning             "\"custom\""
  toml_set "$APP" pruning-keep-recent "\"100\""
  toml_set "$APP" pruning-interval    "\"10\""
  toml_set_in "$APP" grpc enable  "true"
  toml_set_in "$APP" grpc address "\"127.0.0.1:9090\""
else
  # A full node serves RPC, REST and gRPC (a bridge node connects to gRPC). Firewall them to trusted hosts.
  toml_set_in "$CFG" rpc  laddr   "\"tcp://0.0.0.0:26657\""
  toml_set_in "$APP" api  enable  "true"
  toml_set_in "$APP" api  address "\"tcp://0.0.0.0:1317\""
  toml_set_in "$APP" grpc enable  "true"
  toml_set_in "$APP" grpc address "\"0.0.0.0:9090\""
fi

say "Restoring the latest $SNAP_NET snapshot from snapshots.chaindigital.tech"
curl -fsSL "$SNAPSHOT_BASE/$SNAP_NET/latest.json" | jq -r '"  height \(.height) · \(.size) · \(.timestamp)"' || true
cp "$CELESTIA_HOME/data/priv_validator_state.json" "$tmp/priv_validator_state.json"
rm -rf "$CELESTIA_HOME/data"
curl -fL "$SNAPSHOT_BASE/$SNAP_NET/latest.tar.zst" | tar --zstd -xf - -C "$CELESTIA_HOME"
cp "$tmp/priv_validator_state.json" "$CELESTIA_HOME/data/priv_validator_state.json"

say "Enabling BBR congestion control"
printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' \
  | sudo tee /etc/sysctl.d/99-celestia-bbr.conf >/dev/null
sudo modprobe tcp_bbr 2>/dev/null || true
sudo sysctl --system >/dev/null

say "Starting celestia-appd"
write_service celestia-appd "Celestia consensus node ($CHAIN_ID)" \
  "/usr/local/bin/celestia-appd start --home $CELESTIA_HOME"
sudo systemctl restart celestia-appd

cat <<EOF

Done. celestia-appd $APP_VERSION is running on $CHAIN_ID ($ROLE).

  logs:    sudo journalctl -u celestia-appd -f -o cat
  synced?  curl -s localhost:26657/status | jq .result.sync_info.catching_up

Open the P2P port:  sudo ufw allow 26656/tcp
EOF

if [ "$ROLE" = "validator" ]; then
  cat <<EOF

Next, for a validator:
  1. Create or import the operator key:  celestia-appd keys add <name> --home $CELESTIA_HOME
  2. Once synced, create the validator:  https://docs.celestia.org/how-to-guides/validator-node
  3. Install the Fibre server:           bash <(curl -fsSL $CD_RAW/install-fibre.sh) ${1}
EOF
else
  cat <<EOF

RPC 26657, REST 1317 and gRPC 9090 listen on all interfaces. Allow only the hosts that need them, e.g.:
  sudo ufw allow from <bridge-ip> to any port 9090 proto tcp
EOF
fi
