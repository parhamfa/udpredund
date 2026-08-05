# Contributing

Contributions are welcome when they preserve a small, auditable transport
wrapper and safe deployment defaults.

## Before opening a pull request

1. Use the software and test traffic only on systems you own or are authorized
   to administer.
2. Open a focused issue for substantial protocol or deployment changes, unless
   the matter is security-sensitive.
3. Keep UDR1 byte-for-byte compatible. Any session-aware or multi-peer wire
   design belongs in an explicitly incompatible UDR2 proposal.
4. Do not add credentials, public addresses, hostnames, packet captures,
   RouterOS backups, logs, generated binaries, or production configuration.
5. Add tests for behavior changes and update the operator documentation.

Run the local checks:

```sh
make test
make test-race
make vet
make fuzz
make lint
```

Container or deployment changes should also run the relevant image E2E,
RouterOS disposable lifecycle, or Ubuntu disposable-VM validation. Describe
what was actually tested and what remains untested; do not imply arm64 hardware
validation from emulation.

## Design constraints

- Primary packets must not wait for delayed-copy capacity.
- Queues, deduplication, and per-peer state must remain bounded.
- Worker failures must reach the process supervisor.
- Public integrations must fail closed, avoid unrelated network mutation, and
  provide a documented rollback.
- New runtime dependencies require a clear reason, pinned provenance, license
  notice, and SBOM coverage.

Use conventional, scoped commits where practical. By contributing, you agree
that your contribution is licensed under the repository's MIT license.

For vulnerabilities, do not use issues or ordinary pull requests. Follow
[SECURITY.md](SECURITY.md).
