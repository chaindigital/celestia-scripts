#!/usr/bin/env bash
# Install the Fibre server next to a running Celestia validator and run it under systemd.
# Fibre is a separate service from celestia-appd. It reads chain state over the node's app gRPC
# and asks the node to sign over privval gRPC, so it runs on the validator host and talks to it over loopback.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-fibre.sh) mainnet
#
# Optional environment: FIBRE_HOME (default ~/.celestia-fibre, ideally on its own disk),
# CELESTIA_HOME (default ~/.celestia-app), EXTERNAL_IP.
set -euo pipefail

CD_RAW="${CD_RAW:-https://raw.githubusercontent.com/chaindigital/celestia-scripts/main}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -f "$here/common.sh" ]; then . "$here/common.sh"; else . <(curl -fsSL "$CD_RAW/common.sh"); fi

set_network "${1:-}"
APP="$CELESTIA_HOME/config/app.toml"
CFG="$CELESTIA_HOME/config/config.toml"

command -v celestia-appd >/dev/null || die "celestia-appd not found. Install the validator first (install-node.sh)."
command -v jq >/dev/null || sudo apt-get install -y -qq jq >/dev/null
[ -f "$APP" ] || die "$APP not found. Set CELESTIA_HOME."
require_glibc 2.34

app_version="$(curl -fsS localhost:26657/abci_info | jq -r '.result.response.app_version // empty' || true)"
[ -n "$app_version" ] || die "celestia-appd RPC on localhost:26657 is not answering"
[ "$app_version" -ge 10 ] || die "the chain is on app version $app_version. Fibre needs app version 10 or later."

# Fibre needs the node's app gRPC and privval gRPC, both on loopback.
grpc_on="$(sed -n '/^\[grpc\]/,/^\[/p' "$APP" | grep -cE '^enable *= *true' || true)"
if [ "$grpc_on" = "0" ]; then
  warn "app gRPC was disabled. Enabling it on 127.0.0.1:9090. Restart celestia-appd before Fibre starts."
  toml_set_in "$APP" grpc enable  "true"
  toml_set_in "$APP" grpc address "\"127.0.0.1:9090\""
  sudo systemctl restart celestia-appd
fi
signer="$(grep -E '^priv_validator_grpc_laddr *=' "$CFG" | cut -d'"' -f2 || true)"
[ -n "$signer" ] || die "priv_validator_grpc_laddr is missing in $CFG. Run: celestia-appd config sync --home $CELESTIA_HOME"
case "$signer" in
  127.0.0.1:*) ;;
  *) die "privval gRPC listens on $signer. This script supports the loopback setup only; a remote signer needs mutual TLS, see the Fibre guide." ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading Fibre $APP_VERSION"
fetch_release celestia-app "$APP_VERSION" "fibre_Linux_$(arch_suffix).tar.gz" "$tmp/fibre"
install_bin "$tmp/fibre" fibre
fibre version

mkdir -p "$FIBRE_HOME"
write_service celestia-fibre "Celestia Fibre server ($CHAIN_ID)" \
  "/usr/local/bin/fibre start --home $FIBRE_HOME --app-grpc-address 127.0.0.1:9090 --signer-grpc-address $signer --server-listen-address 0.0.0.0:7980"
sudo systemctl restart celestia-fibre

say "Waiting for Fibre to listen on :7980"
listening() { [ -n "$(ss -ltnH 'sport = :7980')" ]; }
for _ in $(seq 1 30); do
  listening && break
  sleep 2
done
listening || die "Fibre is not listening yet. Check: sudo journalctl -u celestia-fibre -n 100"

EXTERNAL_IP="${EXTERNAL_IP:-$(public_ip)}"
cat <<EOF

Fibre is running. Home: $FIBRE_HOME  ·  logs: sudo journalctl -u celestia-fibre -f -o cat

1. Open the client port:   sudo ufw allow 7980/tcp
2. Check it from outside this host, then register the host with your validator's account key:

   celestia-appd tx valaddr set-host $EXTERNAL_IP:7980 \\
     --from <validator-account-key> --chain-id $CHAIN_ID --fees 2000utia --home $CELESTIA_HOME

3. Confirm:                celestia-appd query valaddr providers --home $CELESTIA_HOME

An unregistered server gets no Fibre traffic. Register again only if the address changes.
Using TMKMS or another remote signer: it must support SignRawBytes, with median signing latency of 10 ms or less.
Memory: the defaults (max_connections 16 × max_concurrent_streams 13) suit a 32 GiB host. Tune them in
$FIBRE_HOME/config/server_config.toml.
EOF
