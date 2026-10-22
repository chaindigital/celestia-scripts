# Shared settings and helpers for the Chain Digital Celestia scripts.
# Every script loads this file, so a version bump here reaches all of them.

APP_VERSION_MAINNET="v10.4.0"
APP_VERSION_MOCHA="v10.4.0-mocha"
NODE_VERSION_MAINNET="v0.34.3"
NODE_VERSION_MOCHA="v0.34.3-mocha"

SNAPSHOT_BASE="https://snapshots.chaindigital.tech/celestia"
NETWORKS_RAW="https://raw.githubusercontent.com/celestiaorg/networks/master"

CELESTIA_HOME="${CELESTIA_HOME:-$HOME/.celestia-app}"
FIBRE_HOME="${FIBRE_HOME:-$HOME/.celestia-fibre}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

# set_network <mainnet|mocha> fills in everything that differs between the networks.
set_network() {
  case "${1:-}" in
    mainnet)
      CHAIN_ID="celestia"
      APP_VERSION="$APP_VERSION_MAINNET"
      NODE_VERSION="$NODE_VERSION_MAINNET"
      SNAP_NET="mainnet"
      NETWORKS_DIR="celestia"
      P2P_NETWORK_FLAG=""
      OTEL_ENDPOINT="otel.celestia.observer"
      ;;
    mocha)
      CHAIN_ID="mocha-5"
      APP_VERSION="$APP_VERSION_MOCHA"
      NODE_VERSION="$NODE_VERSION_MOCHA"
      SNAP_NET="mocha-5"
      NETWORKS_DIR="mocha-5"
      P2P_NETWORK_FLAG="--p2p.network mocha"
      OTEL_ENDPOINT="otel.mocha.celestia.observer"
      ;;
    *) die "network must be 'mainnet' or 'mocha'" ;;
  esac
}

# Release archives are named after `uname -m`, except that Linux arm64 reports aarch64.
arch_suffix() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported CPU architecture: $(uname -m)" ;;
  esac
}

# require_glibc <version>: the v10 multiplexer needs 2.38 (Ubuntu 24.04), Fibre needs 2.34.
require_glibc() {
  local need="$1" have
  have="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"
  [ -n "$have" ] || die "could not detect the glibc version"
  [ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -n1)" = "$need" ] \
    || die "glibc $have found, $need or newer is required"
}

# fetch_release <repo> <tag> <archive> <dir>
# Downloads a celestiaorg release archive with its checksums.txt, verifies it and unpacks it into <dir>.
fetch_release() {
  local repo="$1" tag="$2" archive="$3" dir="$4"
  local base="https://github.com/celestiaorg/$repo/releases/download/$tag"
  mkdir -p "$dir"
  (
    cd "$dir"
    curl -fsSLO "$base/$archive"
    curl -fsSLO "$base/checksums.txt"
    sha256sum --ignore-missing --quiet -c checksums.txt
    tar -xzf "$archive"
  ) || die "download or checksum check failed for $repo $tag ($archive)"
}

# install_bin <dir> <name>: installs the binary <name> found anywhere under <dir> into /usr/local/bin.
install_bin() {
  local src
  src="$(find "$1" -type f -name "$2" -print -quit)"
  [ -n "$src" ] || die "$2 not found in the release archive"
  sudo install -m 0755 "$src" "/usr/local/bin/$2"
}

public_ip() {
  curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
    || curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null \
    || die "could not detect the public IPv4 address; set EXTERNAL_IP"
}

# toml_set <file> <key> <value>: replaces a top-level or unique key. Accepts both foo_bar and foo-bar spellings.
toml_set() {
  local file="$1" key="$2" value="$3" pattern
  pattern="$(printf '%s' "$key" | sed 's/[_-]/[_-]/g')"
  grep -qE "^${pattern} *=" "$file" || die "key $key not found in $file"
  sed -i -E "s|^(${pattern}) *=.*|\1 = ${value}|" "$file"
}

# toml_set_in <file> <section> <key> <value>: replaces a key inside one [section] only.
toml_set_in() {
  local file="$1" section="$2" key="$3" value="$4"
  sed -i -E "/^\[${section}\]/,/^\[/ s|^(${key}) *=.*|\1 = ${value}|" "$file"
}

# list_from_networks <file>: a comma-separated list from celestiaorg/networks (seeds.txt, peers.txt).
list_from_networks() {
  curl -fsSL "$NETWORKS_RAW/$NETWORKS_DIR/$1" | grep -vE '^\s*(#|$)' | paste -sd, -
}

write_service() {
  local name="$1" description="$2" exec_start="$3"
  sudo tee "/etc/systemd/system/$name.service" >/dev/null <<EOF
[Unit]
Description=$description
After=network-online.target
Wants=network-online.target

[Service]
User=${USER:-$(id -un)}
ExecStart=$exec_start
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable "$name" >/dev/null
}
