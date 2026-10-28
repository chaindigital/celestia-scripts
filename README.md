<p align="center">
  <a href="https://chaindigital.tech"><img src="https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/media/banner.svg?v=1" alt="Chain Digital — Celestia node scripts"/></a>
</p>

<p align="center">
  <img width="100%" src="https://capsule-render.vercel.app/api?type=rect&color=0:0E4C75,50:56CCF2,100:2D9CDB&height=4&section=header"/>
</p>

<p align="center">
  <a href="https://chaindigital.tech/tools"><b>chaindigital.tech/tools</b></a> &nbsp;·&nbsp;
  <a href="https://github.com/chaindigital/endpoints">endpoints</a> &nbsp;·&nbsp;
  <a href="https://chaindigital.tech/chaintia/">CelestiaSignals</a> &nbsp;·&nbsp;
  <a href="https://docs.celestia.org/how-to-guides/nodes-overview">official docs</a>
</p>

<br/>

These are the scripts Chain Digital uses to set up and upgrade Celestia nodes. Each script:

- installs the **official release binaries** from `celestiaorg` and checks them against the release `checksums.txt`
- takes genesis, seeds and peers from the official [celestiaorg/networks](https://github.com/celestiaorg/networks) repository
- restores a consensus node from the [Chain Digital snapshot](https://snapshots.chaindigital.tech), rebuilt every 6 hours
- runs every service under systemd

All versions are pinned in one place, [`common.sh`](common.sh).

<br/>

## Versions

| | Mainnet `celestia` | Testnet `mocha-5` |
|---|---|---|
| celestia-app + Fibre | `v10.5.0` | `v10.5.0-mocha` |
| celestia-node (bridge) | `v0.34.4` | `v0.34.4-mocha` |

## Requirements

- **Ubuntu 24.04** or newer. The v10 `celestia-appd` build needs glibc 2.38; Ubuntu 22.04 does not have it.
- A user with `sudo`. The scripts install binaries into `/usr/local/bin` and write the systemd units.
- Hardware sized to the [official requirements](https://docs.celestia.org/how-to-guides/nodes-overview) for your node type.

<br/>

## Install

> [!TIP]
> These commands run a script straight from GitHub. To read it first, download it and run the local copy:
> `curl -fsSLO https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-node.sh && less install-node.sh`

Use `mocha` in place of `mainnet` for the testnet.

### Consensus node: validator or full

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-node.sh) mainnet validator
```

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-node.sh) mainnet full
```

| | validator | full |
|---|---|---|
| Pruning | custom, keep 100 | default |
| RPC `26657` | localhost | all interfaces |
| gRPC `9090` | localhost, used by Fibre | all interfaces, used by bridges |
| REST `1317` | off | all interfaces |

Both roles use `pebbledb`, the backend of the snapshots, and enable BBR. The script asks for a moniker, or set `MONIKER=...` before running it.
It does not create keys or send transactions. For the validator itself, follow [create a validator](https://docs.celestia.org/how-to-guides/validator-node).

### Fibre server

Fibre is the data availability server introduced in app v10. Validators run it as a separate service next to `celestia-appd`.
Install it on the validator host once the validator is synced and bonded:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-fibre.sh) mainnet
```

The script checks that the chain is on app version 10 and that the node's app gRPC and privval gRPC are on loopback.
It starts `celestia-fibre` on port `7980` and prints the `valaddr set-host` command that registers your host on-chain.
Set `FIBRE_HOME=/mnt/fibre/.celestia-fibre` to keep Fibre data on its own disk, as the [Fibre guide](https://github.com/celestiaorg/celestia-app/blob/v10.5.0/fibre/cmd/README.md) recommends.
Since v10.5.0, Fibre exposes a gRPC health check on `7980` for monitoring:
`grpc_health_probe -addr=127.0.0.1:7980 -tls -tls-no-verify`.

> [!NOTE]
> With TMKMS or another remote signer, Fibre still signs through the node. The signer must support `SignRawBytes`, with median signing latency of 10 ms or less.

### Bridge node

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/install-bridge.sh) mainnet
```

The script asks for the consensus node address (gRPC `9090`), or set `CORE_IP=...`. It runs an archival bridge by default; set `ARCHIVAL=false` to turn that off.

<br/>

## Upgrade

Upgrade when the network announces a release, after reading its notes.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/upgrade-app.sh) mainnet
```

This replaces `celestia-appd`, and `fibre` when it is installed, with the pinned release. It then runs `celestia-appd config sync`, which adds new settings, keeps existing values and writes backups, and restarts both services.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaindigital/celestia-scripts/main/upgrade-bridge.sh) mainnet
```

This replaces `celestia`, runs `celestia bridge config-update` and restarts the bridge.

<br/>

## Ports

| Port | Service | Open to |
|---|---|---|
| `26656/tcp` | consensus P2P | everyone |
| `7980/tcp` | Fibre | everyone |
| `2121/tcp+udp` | bridge P2P | everyone |
| `26657` · `9090` · `1317` | RPC · gRPC · REST | trusted hosts only |
| `26669` | privval gRPC, Fibre signing | loopback only |

```bash
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow ssh && sudo ufw allow 26656/tcp
sudo ufw enable
```

<br/>

## Settings

| Variable | Default | Used by |
|---|---|---|
| `MONIKER` | asked | install-node |
| `CELESTIA_HOME` | `~/.celestia-app` | all app and Fibre scripts |
| `FIBRE_HOME` | `~/.celestia-fibre` | install-fibre, upgrade-app |
| `CORE_IP` · `CORE_PORT` | asked · `9090` | install-bridge |
| `ARCHIVAL` | `true` | install-bridge |
| `EXTERNAL_IP` | detected | install-node, install-fibre |

<br/>

## Public endpoints

No node of your own yet? Our RPC, API and snapshots are listed on [chaindigital.tech/tools](https://chaindigital.tech/tools) and in [endpoints](https://github.com/chaindigital/endpoints).

---

<p align="center">
  <sub>Maintained by <a href="https://chaindigital.tech">Chain Digital</a> · Celestia Foundation Delegation Program, Cohort 7 · issues and PRs welcome</sub>
</p>
