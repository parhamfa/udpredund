# RouterOS entry to Ubuntu exit

This layout keeps the existing WireGuard egress on Ubuntu. PingTunnel receives
the ICMP carrier, forwards UDR1 datagrams to a loopback deduplicator, and the
deduplicator sends the original UDP payload to the existing WireGuard listen
port.

The installer adds two hardened systemd services and two binaries. It does not
change the Ubuntu firewall, interfaces, routes, sysctls, or WireGuard
configuration.

The lifecycle was tested on a disposable Ubuntu 24.04 arm64 VM with systemd
255. The amd64 artifacts use the same units and are build-tested.

## Prerequisites

- A supported Ubuntu host with systemd and root access.
- A directly reachable public IPv4 address.
- An existing WireGuard listener on the exit.
- Host and upstream firewall policy that permits required ICMP only from the
  entry's actual public source CIDR.
- A RouterOS entry meeting the prerequisites in the
  [RouterOS guide](quickstart-routeros.md).

## 1. Download and verify the Ubuntu bundle

Map `uname -m` to the release architecture:

| `uname -m` | Bundle |
|---|---|
| `x86_64` | `amd64` |
| `aarch64` or `arm64` | `arm64` |

Download `SHA256SUMS` and the matching bundle from the `v0.1.0-beta.1`
prerelease, then verify it. On GNU/Linux:

```sh
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf udpredund-v0.1.0-beta.1-ubuntu-amd64.tar.gz
cd udpredund-v0.1.0-beta.1-ubuntu-amd64
```

Use the arm64 filename when appropriate.

## 2. Install the exit services

Run the interactive installer:

```sh
sudo ./install.sh
```

It prompts, without echoing the PingTunnel key, for:

- A shared decimal PingTunnel key from 1 through 2147483647.
- The existing WireGuard UDP listen port.
- The loopback UDR1 port, default `46111`.
- The duplication profile, default `2 / 300 bytes / 10ms`.

The installer stores values in `/etc/udpredund/udpredund.env`, owned by root
with mode `0600`; installs static binaries under
`/usr/local/libexec/udpredund`; verifies both units with `systemd-analyze`; and
enables them only when verification succeeds.

The upstream PingTunnel CLI accepts its key only as a process argument. The
installer keeps it out of shell history and terminal status output, but a
local user who can inspect another service's process arguments may still see
it. Do not treat the PingTunnel key as cryptographic protection or run this
beta on an untrusted multi-user host without an appropriate `/proc` policy.
WireGuard remains the security boundary.

Configure the host firewall yourself. Restrict ICMP to the entry source when
possible. The installer intentionally makes no firewall assumptions.

## 3. Install the RouterOS entry

Download the RouterOS image tar and template bundle described in the
[RouterOS guide](quickstart-routeros.md). In `install-entry.rsc`, set:

```routeros
:local exitPublicAddress "YOUR_EXIT_PUBLIC_ADDRESS"
:local pingTunnelTarget "127.0.0.1"
:local pingTunnelKey "YOUR_SHARED_DECIMAL_KEY"
```

Also set `imageFile`, `wireGuardPeerComment`, a collision-free `entryPrefix`,
and storage. Import the entry installer with plain `/import`. It prints the
exact local WireGuard peer endpoint command but does not apply it. Review and
run that command manually only after the Ubuntu units are healthy.

Why loopback works: PingTunnel's Ubuntu server receives the outer ICMP and
opens its configured UDP target locally. The target is the UDR1 service on
`127.0.0.1:46111`, not an address on the RouterOS entry.

## 4. Verify

Avoid `systemctl status` because the live PingTunnel command line contains its
key. Use quiet state checks:

```sh
sudo systemctl is-enabled udpredund-pingtunnel.service udpredund-relay.service
sudo systemctl is-active udpredund-pingtunnel.service udpredund-relay.service
sudo systemd-analyze verify \
  /etc/systemd/system/udpredund-pingtunnel.service \
  /etc/systemd/system/udpredund-relay.service
sudo systemd-analyze security \
  udpredund-pingtunnel.service udpredund-relay.service
```

Then verify the original WireGuard peer handshake, bidirectional application
traffic, latency, and loss. Unit state alone does not prove the ICMP path.

Periodic UDR1 metrics are written to the relay journal. Useful counters
include `invalid_frame`, `oversize_frame`, `queued_copy`, `dropped_copy`,
`duplicate`, `peer_change`, and `dedupe_eviction`:

```sh
sudo journalctl -u udpredund-relay.service --since today
```

Do not publish journal output without reviewing it for operational data.

## Rollback and uninstall

First move the RouterOS WireGuard peer back to its previous endpoint and
confirm traffic. Then remove the Ubuntu components:

```sh
sudo ./uninstall.sh
```

For unattended removal, use `sudo ./uninstall.sh --yes`. The uninstaller
disables the two units and removes their units, binaries, and environment file.
It does not change firewall or WireGuard state. Upgrade backups remain under
`/var/lib/udpredund`; inspect and restore those manually if rolling back an
upgrade rather than removing the integration.

Finally import `uninstall-entry.rsc` on RouterOS after confirming that no peer
still targets the carrier.

## Troubleshooting

- **PingTunnel unit fails:** confirm the host permits `CAP_NET_RAW`, the binary
  matches the CPU architecture, and the key is a valid decimal integer.
- **Units are active but no WireGuard reply arrives:** confirm inbound ICMP,
  the entry public source restriction, `pingTunnelTarget=127.0.0.1`, matching
  keys, and the existing WireGuard listen port entered during installation.
- **Relay counters show `invalid_frame`:** traffic other than UDR1 is reaching
  the loopback relay, or the two sides are not using a compatible UDR1 wrapper.
- **`dropped_copy` rises:** the bounded delayed-copy queue is saturated.
  Primary packets still bypass that queue; measure CPU and carrier capacity
  before increasing it.
