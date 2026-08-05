# Security policy

## Supported versions

During beta, only the newest published prerelease receives security fixes.

| Version | Supported |
|---|---|
| `0.1.0-beta.1` | Yes |
| Private prototypes and untagged builds | No |

## Report a vulnerability privately

Do not open a public issue for a suspected vulnerability. Use GitHub's
[private vulnerability reporting form](https://github.com/parhamfa/udpredund/security/advisories/new).
Include the affected version or digest, deployment topology, impact, minimal
reproduction, and any suggested mitigation. Remove public IP addresses, keys,
WireGuard configuration, packet captures, and unrelated production data.

You should receive an acknowledgement within seven days. Triage and remediation
timing depend on severity and reproducibility. Please allow coordinated repair
and release before public disclosure.

## Security boundaries

- UDR1 is an unauthenticated framing and deduplication protocol. It must stay on
  loopback or an isolated internal network.
- A valid-looking sender can inject plain payloads and become the beta relay's
  single effective return peer.
- `udpredund` does not encrypt, authenticate, retransmit, or provide FEC.
  WireGuard remains responsible for payload security and peer identity.
- The PingTunnel key is transport configuration, not cryptographic protection.
  In the Ubuntu integration it is passed to the upstream binary as a process
  argument and may be visible to local observers with process-inspection
  access.
- RouterOS containers expand the router's trusted computing base. The templates
  use source-restricted ICMP NAT, isolated veths, owned-object comments, and
  disabled container logging, but cannot remove the platform's container risk.
- The installers intentionally do not manage host firewall policy, WireGuard,
  routes, ECMP, or default routes. Operators must secure and verify those
  boundaries separately.

Reports that demonstrate a bypass of these documented boundaries, unsafe
installer mutation, malformed-frame memory or process safety issues,
cross-peer data delivery beyond the stated last-sender model, secret exposure
beyond the documented PingTunnel argv limitation, or release supply-chain
problems are in scope.

Traffic-blocking behavior intrinsic to ICMP filtering, loss on an uncontrolled
network, or use outside the documented single-peer topology is not by itself a
security vulnerability.
