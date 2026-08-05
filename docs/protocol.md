# UDR1 protocol, CLI, and container contract

## Wire compatibility

`UDR1` deliberately remains compatible with the already deployed wrapper.
Every encoded UDP datagram is:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 bytes | ASCII magic `UDR1` |
| 4 | 8 bytes | Unsigned sequence number, big-endian |
| 12 | remainder | Original UDP payload, unchanged |

There is no session identifier, peer identifier, length field, checksum, or
authentication tag. UDP provides the frame boundary. The maximum accepted
encoded datagram is 65,507 bytes; therefore the maximum plain payload is
65,495 bytes.

Each process chooses a random initial 64-bit sequence and increments it for
outbound plain datagrams. Receivers retain a bounded set of recently seen
sequence numbers and deliver only the first copy.

Existing UDR1 binaries and this beta interoperate in both directions. A future
multi-peer/session-aware protocol would be named `UDR2` and treated as an
explicit incompatible change; it will not silently alter UDR1.

## CLI

The original six flags and semantics are preserved:

```text
-mode client|server
-listen UDP_ADDRESS
-next UDP_ADDRESS
-copies 1..8
-max-duplicate-size BYTES
-gap DURATION
```

Example client and server around an arbitrary UDP service:

```sh
udpredund -mode client -listen 127.0.0.1:45111 \
  -next 127.0.0.1:45211 -copies 2 -max-duplicate-size 300 -gap 10ms

udpredund -mode server -listen 127.0.0.1:46111 \
  -next 127.0.0.1:51820 -copies 2 -max-duplicate-size 300 -gap 10ms
```

Client mode accepts plain UDP on `listen`, emits UDR1 to `next`, decodes the
reverse path, and returns it to the last plain sender. Server mode accepts UDR1
on `listen`, emits plain UDP to `next`, encodes the reverse path, and returns it
to the last valid UDR1 sender.

`max-duplicate-size=0` preserves full-duplication behavior. A positive value
makes datagrams larger than the threshold single-copy. `copies=1` disables
redundancy without disabling framing. Durations use Go syntax such as `10ms`.

Additional bounded-resource controls are available:

```text
-copy-queue 4096
-dedupe-window 30s
-dedupe-capacity 65536
-metrics-interval 5s
-version
```

The primary write is synchronous and never enters the delayed-copy queue.
Delayed copies use one bounded scheduler. When capacity is exhausted, the copy
is dropped and counted. A delayed-copy send failure is propagated and stops the
process instead of leaving a partially failed worker running.

Deduplication state is pruned by age and capacity. A duplicate arriving after
expiration can be delivered again. UDR1 does not reorder payloads.

## Single-effective-peer beta model

Both modes remember one return peer. The last valid sender becomes effective.
On a server-side peer change, deduplication state is reset for the new source.
This behavior supports a single WireGuard flow through one carrier; it is not
safe multi-client multiplexing.

Do not bind UDR1 to an untrusted network. A party that can submit valid-looking
UDR1 frames can inject payloads and can become the effective return peer. UDR1
has no authentication; an internal bridge or loopback binding is part of the
security design.

## Metrics

Metrics are process-lifetime log counters:

| Counter | Meaning |
|---|---|
| `plain_in`, `plain_out` | Original UDP datagrams read and delivered |
| `encoded_in`, `encoded_out` | UDR1 datagrams read and sent |
| `duplicate` | Valid repeated sequence numbers suppressed |
| `invalid_frame` | Short frames or invalid UDR1 magic |
| `oversize_frame` | Plain or encoded datagrams over protocol limits |
| `queued_copy` | Delayed redundant copies accepted by the scheduler |
| `dropped_copy` | Redundant copies rejected by capacity or shutdown |
| `send_error` | Failed primary or delayed writes |
| `no_peer` | Reverse payload dropped before a return peer was learned |
| `peer_change` | Effective sender changed after initial discovery |
| `dedupe_eviction` | Sequence entries removed by expiry, capacity, or reset |

## Production image contract

The image has a fixed `ENTRYPOINT` and deliberately empty `CMD`. RouterOS does
not need a `cmd` value: the entrypoint reads `ROLE` and the environment list,
then constructs the pinned PingTunnel and `udpredund` arguments.

| Role | Required configuration | Process layout |
|---|---|---|
| `pt-client` | `PT_SERVER`, `PT_TARGET`, `PT_KEY`, `PT_LISTEN_PORT`, `UDR_LISTEN_PORT` | PingTunnel client plus UDR1 client |
| `pt-server` | `PT_KEY` | PingTunnel server |
| `udr-server` | `UDR_LISTEN_PORT`, `UDR_NEXT` | UDR1 deduplicating server |
| `verify` | none | Checks binaries and reports the image version |

The optional profile variables are `COPIES`, `MAX_DUPLICATE_SIZE`, and
`COPY_GAP`. The image defaults to `2`, `300`, and `10ms`. `PT_KEY` must be a
decimal integer from 1 through 2147483647 because that is the pinned
PingTunnel CLI's accepted type.

The entrypoint supervises both client processes: if either exits, it stops the
other and returns the failure. `tini` is PID 1 and forwards termination signals.
