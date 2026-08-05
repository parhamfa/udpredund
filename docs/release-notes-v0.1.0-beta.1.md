# v0.1.0-beta.1 release notes

`v0.1.0-beta.1` is the first public `udpredund` beta. It packages the deployed
UDR1-compatible UDP wrapper as an independent MIT-licensed project; it is not a
PingTunnel fork.

## Highlights

- Exact deployed UDR1 wire compatibility and cross-version fixtures.
- Bounded delayed-copy scheduling that never queues the primary packet.
- Bounded, expiring deduplication and strict frame-size/magic validation.
- Process-lifetime metrics for malformed/oversized frames, copy queue pressure,
  duplicate suppression, peer changes, and evictions.
- Clean signal shutdown and propagation of worker and delayed-send failures.
- Minimal amd64/arm64 image with PingTunnel pinned to commit
  `a0d08ec7d44f4829c543416542ef3734453a4a55`.
- Safe-by-default RouterOS entry/exit templates and an Ubuntu systemd bundle.
- Standalone static Linux binaries, architecture-specific RouterOS archives,
  checksums, SPDX SBOMs, licenses, and build provenance attestations.

## Tested status

- **amd64 RouterOS/CHR:** production-path tested and disposable lifecycle
  tested on RouterOS 7.21.5.
- **Ubuntu arm64:** disposable Ubuntu 24.04 VM install, restart, reboot,
  end-to-end relay, network non-mutation, and uninstall tested.
- **Container amd64:** full PingTunnel/ICMP plus selective-C2 UDP echo tested.
- **Container arm64:** build and emulated runtime verification tested.
- **Physical MikroTik arm64:** not tested; experimental.

## Known limitations

- One effective UDP peer per relay; last valid sender wins.
- No UDR-layer encryption, authentication, retransmission, ACK, FEC, congestion
  control, or reorder buffer.
- The PingTunnel numeric key is not a replacement for WireGuard security and is
  visible in the PingTunnel process arguments to sufficiently privileged local
  observers.
- The `2 / 300 B / 10ms` profile is a tested starting point, not an automatic
  optimum.
- RouterOS templates are archive-first and validated on one current CHR
  release. Registry installation is an advanced manual path.

## Upgrade and rollback

There is no older public release to upgrade from. Existing private UDR1
binaries can interoperate during a staged migration, but the public deployment
object names are new. Do not reuse an existing production bridge, veth, root,
layer store, environment list, or NAT comment.

Keep the previous WireGuard peer endpoint recorded outside the scripts. The
installers never change it. Roll back that endpoint first, verify traffic, then
run the provided uninstaller. Ubuntu upgrades back up managed files under
`/var/lib/udpredund`; restoration is manual.

## Image tags

Published:

```text
ghcr.io/parhamfa/udpredund-pingtunnel:v0.1.0-beta.1
```

Not published:

```text
latest
```
