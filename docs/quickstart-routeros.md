# RouterOS entry to RouterOS exit

This guide installs one carrier container on the entry and separate
PingTunnel and UDR1 containers on the exit. It does not modify either
WireGuard interface, any peer, route, MTU, ECMP group, default route, or
pre-existing firewall rule.

The templates were lifecycle-tested on amd64 CHR running RouterOS 7.21.5.
Arm64 release images are experimental until tested on physical MikroTik
hardware.

## Prerequisites

- Direct administrative access and a tested recovery path for both routers.
- A matching RouterOS `container` package and container device mode enabled.
- Adequate container storage. External storage is preferable on hardware
  routers.
- A directly reachable public IPv4 address on the exit.
- The actual public source CIDR from which the entry's ICMP reaches the exit.
- An existing, working WireGuard peer on the entry and existing WireGuard
  listen port on the exit.

MikroTik disables container mode by default and warns that third-party
containers expand the router's attack surface. Read the official
[RouterOS container guidance](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container)
before enabling it.

Check the architecture and device mode:

```routeros
/system/resource/print
/system/device-mode/print
/system/package/print where name=container
```

Use the amd64 image for CHR/x86_64 and the arm64 image only for arm64 devices.

## 1. Download and verify

Download these files from the `v0.1.0-beta.1` release:

```text
SHA256SUMS
udpredund-pingtunnel-v0.1.0-beta.1-routeros-amd64.tar
udpredund-v0.1.0-beta.1-routeros-templates.tar.gz
```

Substitute `arm64` only when the router reports that architecture. Verify each
download against `SHA256SUMS` before upload. For example, on GNU/Linux:

```sh
sha256sum --ignore-missing -c SHA256SUMS
```

Extract the template bundle. Upload the architecture-specific image tar and
the `.rsc` files to each relevant router using Files in WinBox, SFTP, or SCP.
Do not upload `SHA256SUMS` as a substitute for verifying it locally.

## 2. Configure the exit template

Edit only the variable block at the top of `install-exit.rsc`:

- `imageFile`: exact uploaded tar path.
- `exitPublicAddress`: the exit address seen by inbound traffic.
- `entrySourceCIDR`: the entry's real public source, normally a `/32`.
- `allowUnrestrictedICMP`: keep `false`. Set `true` only after explicitly
  accepting unrestricted PingTunnel ingress.
- `pingTunnelKey`: a shared decimal integer from 1 through 2147483647.
- `existingWireGuardPort`: the exit's current WireGuard UDP listen port.
- `exitPrefix`: an unused private `/24` prefix without the final octet.
- `storageRoot`: a collision-free path, preferably on suitable storage.

The default `exitPrefix` is `10.254.242`; the entry must then use
`pingTunnelTarget="10.254.242.3"`. If you change the exit prefix, change the
entry target to its `.3` address.

Import the exit installer first:

```routeros
/import file-name=install-exit.rsc
```

Do not add `verbose=yes`. On the tested RouterOS release, verbose import broke
the local-variable execution model used by these templates.

The script completes a collision preflight before mutation, creates two
containers with `start-on-boot=no`, waits for extraction and successful start,
then enables boot persistence and its exact source-restricted ICMP DNAT rule.
If it stops with an error after mutation, leave WireGuard unchanged and use the
matching uninstaller to remove the partial owned stack.

## 3. Configure the entry template

Edit the variable block at the top of `install-entry.rsc`:

- `imageFile`: exact uploaded tar path.
- `exitPublicAddress`: the same exit public address.
- `pingTunnelTarget`: `<exitPrefix>.3` for a RouterOS exit.
- `pingTunnelKey`: exactly the same decimal key.
- `wireGuardPeerComment`: a comment that identifies exactly one existing peer.
- `entryPrefix`: a different unused private `/24` prefix.
- `storageRoot`: a collision-free storage path.

Import it:

```routeros
/import file-name=install-entry.rsc
```

After the container starts, the script prints an exact command that changes
only the selected WireGuard peer endpoint to the local carrier. Review that
command and your rollback endpoint, then run it yourself. The installer never
applies it.

## 4. Verify

Run the read-only verifier on both routers:

```routeros
/import file-name=verify.rsc
```

Expect one running `udrbe-carrier` container on the entry and running
`udrbx-pt` and `udrbx-udr` containers on the exit. Their owned NAT counters
should rise when the carrier is used. Then verify the existing WireGuard peer
handshake, application traffic, latency, and loss using your normal tools.

Container logging is deliberately disabled because RouterOS can copy
container environment values, including `PT_KEY`, into its log. Do not enable
it casually. An administrator can still read the environment list; treat
RouterOS administrative access as trusted.

## Rollback and uninstall

1. Manually restore the WireGuard peer's previous endpoint and confirm that it
   no longer points to the entry carrier.
2. If you changed `entryPrefix` or `storageRoot`, make the same edits at the top
   of `uninstall-entry.rsc`.
3. Import the entry uninstaller.
4. If you changed `exitPrefix` or `storageRoot` on the exit, make the same edits
   in `uninstall-exit.rsc`, then import it.

```routeros
/import file-name=uninstall-entry.rsc
/import file-name=uninstall-exit.rsc
```

The entry uninstaller refuses removal while any WireGuard peer targets its
carrier address and port. Both scripts verify ownership, disable automatic
restart, stop containers, and remove only repository-owned objects. Uploaded
image tars are intentionally retained.

## Registry alternative

The release archive path above is recommended because it is architecture
explicit, checksum-verifiable, and does not modify RouterOS's global registry
configuration. RouterOS can also pull public OCI images through its
`remote-image` property, and GHCR permits anonymous pulls of public packages.

Advanced users can set RouterOS's registry URL to `https://ghcr.io` and use:

```text
parhamfa/udpredund-pingtunnel:v0.1.0-beta.1
```

That global registry change can affect other container workflows, so the beta
templates do not apply it and are not directly interchangeable with
`remote-image`. Follow MikroTik's registry instructions and reproduce the same
interfaces, environment lists, source restriction, ownership comments, and
manual WireGuard handoff if choosing this path.

## Troubleshooting

- **Preflight collision:** choose different `entryPrefix`, `exitPrefix`, or
  `storageRoot`; do not delete an existing object just to satisfy the script.
- **Image never becomes ready:** confirm the tar architecture, free storage,
  matching container package, and device mode.
- **PingTunnel runs but NAT stays at zero:** confirm the entry's actual public
  source CIDR, exit destination address, NAT rule order, and upstream ICMP
  policy. Existing earlier NAT rules can shadow an appended rule.
- **WireGuard sends but receives nothing:** confirm the entry
  `pingTunnelTarget`, exit `existingWireGuardPort`, numeric key, and the exact
  selected peer. The verifier does not prove a WireGuard handshake.
- **Uninstall refuses:** move every WireGuard peer away from the carrier first.
