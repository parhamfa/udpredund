# udpredund

`udpredund` is a small, transport-agnostic UDP redundancy and deduplication
wrapper. Its first integration carries an existing WireGuard peer flow through
[PingTunnel](https://github.com/esrrhs/pingtunnel), so the outer carrier is ICMP
while WireGuard remains the security boundary.

This is a public beta. Test rollback on your own network before relying on it.
The amd64 image and RouterOS lifecycle are CHR-tested. The arm64 artifacts are
build- and container-smoke-tested, but remain experimental until they are
validated on physical MikroTik arm64 hardware.

```text
existing WireGuard UDP flow
        │
        ▼
UDR1 encode + selective copies ─► PingTunnel client ─► ICMP carrier
                                                         │
existing WireGuard UDP port ◄─ UDR1 dedupe ◄─ PingTunnel server
```

The tested starting profile sends two copies of payloads at or below 300 bytes,
separated by 10 ms. Larger payloads remain single-copy:

```text
COPIES=2  MAX_DUPLICATE_SIZE=300  COPY_GAP=10ms
```

That profile is evidence from one environment, not a universal optimum.

## What it does

- Preserves the deployed `UDR1` format: `UDR1` magic, big-endian 64-bit
  sequence number, then the original UDP payload.
- Sends the primary packet immediately and schedules delayed copies in a
  bounded queue. Queue pressure drops redundant copies, never the primary.
- Bounds and expires deduplication state, rejects malformed or oversized
  frames, exposes counters, propagates worker failures, and exits cleanly.
- Ships a pinned PingTunnel build and first-class RouterOS and Ubuntu exit
  integrations.
- Leaves existing WireGuard keys, addresses, MTU, routes, ECMP, default routes,
  and peer endpoints alone. RouterOS prints the peer endpoint command for human
  review.

## What it does not do

`udpredund` adds no encryption, authentication, ACK, retransmission, forward
error correction, congestion control, or reorder buffer. WireGuard is still
responsible for confidentiality, integrity, and peer authentication. Expose
UDR1 only on loopback or a tightly controlled internal network.

The beta has one effective UDP peer per relay. The last valid sender wins; it
is not a multi-tenant UDP proxy. Session-aware multi-peer support would require
an incompatible `UDR2` protocol and is intentionally deferred.

## Release artifacts

The [`v0.1.0-beta.1` prerelease](https://github.com/parhamfa/udpredund/releases/tag/v0.1.0-beta.1)
contains:

| Artifact | Purpose |
|---|---|
| `udpredund-linux-{amd64,arm64}` | Standalone static relay binaries |
| `udpredund-pingtunnel-v0.1.0-beta.1-routeros-{amd64,arm64}.tar` | RouterOS image archives |
| `udpredund-v0.1.0-beta.1-routeros-templates.tar.gz` | Entry, exit, verification, and uninstall scripts |
| `udpredund-v0.1.0-beta.1-ubuntu-{amd64,arm64}.tar.gz` | Binaries, hardened systemd units, installer, and uninstaller |
| `SHA256SUMS`, `*.spdx.json`, attestations | Integrity and provenance material |

There is deliberately no `latest` image tag during beta. The versioned
multi-architecture image is:

```sh
docker pull ghcr.io/parhamfa/udpredund-pingtunnel:v0.1.0-beta.1
```

## Quick Starts

Two supported layouts are documented:

1. [RouterOS entry to RouterOS exit](docs/quickstart-routeros.md)
2. [RouterOS entry to Ubuntu exit](docs/quickstart-ubuntu.md)

Both guides use release archives as the primary installation path, require an
explicit source restriction for inbound ICMP, keep the current WireGuard
configuration intact, and make the final peer endpoint change manual.

Read the [protocol and CLI reference](docs/protocol.md), [anonymized benchmark
report](docs/benchmarks.md), and [beta release notes](docs/release-notes-v0.1.0-beta.1.md)
before deployment.

## Verification and rollback

On RouterOS, import `verify.rsc` for a read-only view of repository-owned
containers, interfaces, and NAT counters. Verify the existing WireGuard peer's
handshake and your own loss/latency probes separately.

To roll back, first restore the WireGuard peer endpoint manually. Then run the
matching entry uninstaller followed by the exit uninstaller. Each uninstaller
checks ownership and removes only `udpredund:v0.1-*` objects; the entry
uninstaller refuses to proceed while a peer still targets the carrier.

On Ubuntu, use `systemctl is-active` for both units and then verify WireGuard
end to end. Run the bundled `uninstall.sh` after moving the entry peer away.
The uninstaller retains upgrade backups under `/var/lib/udpredund`.

## Build and test

Go 1.24 or newer is required for the relay. Docker Buildx is required for the
production image.

```sh
make test
make test-race
make vet
make fuzz
make lint
make privacy
VERSION=v0.1.0-beta.1 make package
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report
security issues privately as described in [SECURITY.md](SECURITY.md).

## Responsible use

Use this software only on systems and networks you own or are explicitly
authorized to administer. You are responsible for local law, provider terms,
network policy, and the consequences of carrying traffic over ICMP. See
[LEGAL.md](LEGAL.md).

MIT licensed. Copyright 2026 Parham Fatemi. PingTunnel attribution and bundled
dependency notices are in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
