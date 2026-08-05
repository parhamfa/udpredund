# Anonymized beta benchmark report

These results explain why the beta default is selective two-copy redundancy.
They are not a capacity promise and should not be generalized to another ISP,
CPU, RouterOS build, loss process, or WireGuard workload.

No hostnames, public addresses, keys, raw captures, RouterOS exports, or
production logs are included in this repository.

## Method

The real-path tests used isolated bridges, veths, containers, WireGuard peers,
addresses, and NAT rules between two amd64 RouterOS CHR instances over a public
network. The existing production data plane was kept out of the test path.

Both compared modes used the same pinned PingTunnel transport. `udpredund`
wrapped the WireGuard UDP flow before PingTunnel and deduplicated it after
PingTunnel:

- **Full duplication:** two copies of every WireGuard UDP datagram.
- **Selective C2:** two copies only when the original UDP payload was at most
  300 bytes, with a configurable temporal gap.

The WireGuard MTU was 1280. Bidirectional UDP load was offered through
WireGuard, one end-to-end probe was sent each second, CPU was sampled on both
CHRs, and outer ICMP traffic was captured for aggregate comparison. Raw
captures were reviewed privately and deliberately excluded from publication.

## Short full-versus-selective comparison

One 15-second case offered 5 Mbit/s in each direction:

| Mode | Delivered TX / RX | Idle probes before / after | Mean entry / exit CPU | Encoded copies per input datagram |
|---|---:|---:|---:|---:|
| Full C2 | 4.8 / 4.8 Mbit/s | 100/100 / 100/100 | 35.5% / 46.3% | 2.000 / 2.000 |
| Selective C2, 300 B | 4.8 / 4.8 Mbit/s | 100/100 / 100/100 | 24.2% / 30.5% | 1.030 / 1.029 |

Selective duplication reduced captured outer ICMP bytes by 49.7% and packets
by 48.3% while delivering the same measured payload in this case. Roughly 3%
of input datagrams qualified for duplication. The threshold does not parse or
identify WireGuard packet types; it simply prioritizes small datagrams.

## Profile search

Selected bidirectional 8 Mbit/s-per-direction cases:

| Copies / threshold / gap | Duration | Probe loss | Delivered TX / RX average | Finding |
|---|---:|---:|---:|---|
| 2 / 300 B / 1 ms | 60 s | 3.3% | 7.7 / 7.6 Mbit/s | Copies were too closely spaced in this path |
| 2 / 300 B / 10 ms | 60 s | 0.0% | 7.7 / 7.6 Mbit/s | Clean short screen |
| 3 / 300 B / 10 ms | 60 s | 0.0% | 7.7 / 7.6 Mbit/s | No demonstrated benefit over two copies |
| 2 / 300 B / 10 ms | 300 s | 0.3% | 7.7 / 7.4 Mbit/s | Longer confirmation |
| 2 / 300 B / 10 ms | 900 s | 0.3% | 7.7 / 7.4 Mbit/s | Final confirmation |

The 900-second run delivered 897 of 900 probes. Mean exit CPU was 80.7% and
reached 100%. Only 0.31% of forward input datagrams and 0.36% of reverse input
datagrams were duplicated.

An additional 60-second case offered 8.5 Mbit/s each way. Delivery remained
near the same 7.4–7.6 Mbit/s ceiling while probe loss rose to 6.7%. That points
to the one-core exit CHR and PingTunnel path as the capacity limit in this
environment, not to a localhost UDP limit. It is also why gigabit throughput
should not be inferred from a loopback test: raw ICMP processing, userspace
copies, single-flow serialization, virtual CPU limits, and the carrier path
dominate.

## Release validation beyond the benchmark

- UDR1 compatibility fixtures passed old-client/new-server and
  new-client/old-server tests.
- Integration tests inject loss, duplication, delay, and reordering and verify
  first-copy delivery, selective duplication, malformed-frame rejection,
  bounded queues, dedupe expiry/capacity, peer changes, and clean shutdown.
- A disposable amd64 Docker topology completed UDP echo through
  UDR1 → PingTunnel/ICMP → UDR1 and observed two encoded copies with one
  delivered payload.
- Both amd64 and arm64 images built and passed their `verify` role; the arm64
  image ran under emulation.
- A disposable amd64 CHR completed preflight, install, reboot persistence,
  verification, safety-refused uninstall while a peer targeted the carrier,
  full uninstall, and reinstall without changing WireGuard or routes.
- A disposable Ubuntu 24.04 arm64 VM completed install, UDR1 echo, forced
  process restart, reboot persistence, semantic network-state comparison, and
  uninstall. `systemd-analyze security` reported exposure 3.0 for PingTunnel
  and 2.8 for the relay on that VM.

## Limitations

- The short comparison used one run per mode and a compressible RouterOS load
  generator. It establishes comparative overhead, not statistical confidence.
- The 900-second profile test was longer but not a randomized A/B trial.
- Probe loss is end-to-end application evidence, not a direct count of every
  lost outer ICMP or inner UDP packet.
- The public report omits raw captures, so third parties cannot independently
  reprocess packet-level evidence.
- The path had a one-core virtualized exit and saturated near 8 Mbit/s each
  direction. Faster hardware or a different network can behave very
  differently.
- Arm64 RouterOS is not hardware-validated. Its beta status is build-tested and
  experimental.

The defensible conclusion is narrow: in the tested path, selective C2 with a
300-byte threshold and 10 ms gap preserved the measured benefit of duplication
with much less outer traffic and CPU than full duplication. Measure before
changing those values.
