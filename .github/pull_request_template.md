## Change

Describe the behavior and why it belongs in this project.

## Verification

List exact tests and environments. Distinguish physical hardware, CHR/VM,
container emulation, and build-only coverage.

## Safety checklist

- [ ] UDR1 compatibility is unchanged, or this is explicitly an incompatible protocol proposal.
- [ ] Primary traffic cannot block on redundant-copy capacity.
- [ ] Queues and peer/deduplication state remain bounded.
- [ ] Deployment changes avoid unrelated WireGuard, route, MTU, ECMP, default-route, and firewall mutation.
- [ ] Rollback behavior is documented and tested in proportion to risk.
- [ ] No credentials, public addresses, hostnames, captures, logs, backups, generated binaries, or production identifiers are included.
- [ ] `make test test-race vet lint privacy` passes.
- [ ] Security-sensitive behavior and operator documentation are updated.
