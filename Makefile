.PHONY: test test-race vet fuzz lint build-binaries package

VERSION ?= dev
REVISION ?= $(shell git rev-parse HEAD 2>/dev/null || printf unknown)
BUILD_DATE ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

test:
	go test ./... -count=1

test-race:
	go test -race ./... -count=1

vet:
	go vet ./...

fuzz:
	go test ./internal/relay -run '^$$' -fuzz '^FuzzDecode$$' -fuzztime=10s

lint:
	test -z "$$(gofmt -l cmd internal)"
	shellcheck container/entrypoint.sh container/tests/entrypoint_test.sh deploy/ubuntu/*.sh scripts/*.sh
	scripts/lint-routeros.sh

build-binaries:
	VERSION="$(VERSION)" REVISION="$(REVISION)" BUILD_DATE="$(BUILD_DATE)" scripts/build-binaries.sh

package: build-binaries
	VERSION="$(VERSION)" ARCH=amd64 scripts/package-ubuntu.sh
	VERSION="$(VERSION)" ARCH=arm64 scripts/package-ubuntu.sh
	VERSION="$(VERSION)" scripts/package-routeros.sh
