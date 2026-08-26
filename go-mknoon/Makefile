.PHONY: ios nse-ios android macos all clean test testpeer lint verify-bindings

MODULE := github.com/mknoon/go-mknoon
BIND_PKG := $(MODULE)/bridge

# Pin the Go toolchain for EVERY recipe (ios/macos/android/test/lint). go1.26.x's
# crypto/tls panics with quic-go v0.49.0 ("where's my session ticket?") on the
# server side of a QUIC handshake -> SIGABRTs the receiver of a direct QUIC dial.
# `:=` overrides any inherited GOTOOLCHAIN (incl. a stray "local"); a deliberate
# `GOTOOLCHAIN=... make <t>` on the command line still wins when you need it.
export GOTOOLCHAIN := go1.25.0

# Output paths relative to the Flutter project
IOS_OUT := ../ios/Runner/GoMknoon.xcframework
NSE_IOS_OUT := ../ios/Runner/GoMknoonNSE.xcframework
MACOS_OUT := ../macos/Runner/GoMknoon.xcframework
ANDROID_OUT := ../android/app/libs/GoMknoon.aar
NSE_BIND_PKG := $(MODULE)/nsebridge

# Android min API level (matches Flutter minSdk)
ANDROID_API ?= 24

# Go ≥1.23 restricts //go:linkname; wlynxg/anet needs the check disabled.
ANDROID_LDFLAGS := -checklinkname=0

# Auto-detect NDK if ANDROID_NDK_HOME is not set.
# Picks the highest version under $ANDROID_HOME/ndk/.
ifndef ANDROID_NDK_HOME
  ifdef ANDROID_HOME
    ANDROID_NDK_HOME := $(shell ls -d $(ANDROID_HOME)/ndk/*/ 2>/dev/null | sort -V | tail -1)
  endif
endif

all: ios android

ios: nse-ios
	gomobile bind -target=ios -o $(IOS_OUT) $(BIND_PKG)

# Notification service extensions have a much smaller memory ceiling than the
# app. Build only the crypto entrypoints used by rich pushes and fail the
# not-yet-advertised opaque mailbox route closed, so libp2p is not linked into
# the extension process.
nse-ios:
	gomobile bind -target=ios -tags=nse_lite -ldflags "-s -w" \
		-o $(NSE_IOS_OUT) $(NSE_BIND_PKG)

macos:
	gomobile bind -target=macos -o $(MACOS_OUT) $(BIND_PKG)

android:
	ANDROID_NDK_HOME=$(ANDROID_NDK_HOME) \
	gomobile bind -target=android -androidapi $(ANDROID_API) \
		-ldflags "$(ANDROID_LDFLAGS)" -o $(ANDROID_OUT) $(BIND_PKG) \
	|| { rm -f $(ANDROID_OUT); exit 1; }

clean:
	rm -rf $(IOS_OUT) $(NSE_IOS_OUT) $(MACOS_OUT) $(ANDROID_OUT) GoMknoon-sources.jar

testpeer:
	go build -o bin/testpeer ./cmd/testpeer

test:
	go test ./...

# Go hygiene gate for app-owned code (node/ + bridge/; third_party/ is vendored, excluded).
# gofmt -l only LISTS unformatted files, so wrap it to fail; go vet is the closest analogue to `flutter analyze`.
# golangci-lint lints only code changed since LINT_BASE (default HEAD = uncommitted work) so the
# pre-existing large files / branch debt are not flooded — lint your FDC work before committing it.
# NOTE: do NOT base this on `main` — `new-orbit` is well ahead of main, so a main delta floods legacy
# code. To lint a whole FDC slice, pass the SHA you branched that work from: `make lint LINT_BASE=<sha>`.
# Requires golangci-lint installed (brew install golangci-lint).
LINT_BASE ?= HEAD
lint:
	@test -z "$$(gofmt -l node bridge)" || { echo "gofmt -l: unformatted files (run gofmt -w):"; gofmt -l node bridge; exit 1; }
	go vet ./node/... ./bridge/...
	@command -v golangci-lint >/dev/null 2>&1 || { echo "golangci-lint not installed — https://golangci-lint.run/welcome/install/ (brew install golangci-lint)"; exit 1; }
	golangci-lint run --new-from-rev=$(LINT_BASE) ./node/... ./bridge/...

verify-bindings:
	../scripts/verify_gomobile_bindings.sh
