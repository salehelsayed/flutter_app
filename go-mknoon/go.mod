module github.com/mknoon/go-mknoon

go 1.27.1

// BUILD TOOLCHAIN: pin to go1.27.1 via GOTOOLCHAIN=go1.27.1 (set in the Makefile
// and scripts/ensure_go_*_bindings.sh), NOT a go.mod `toolchain` directive — that
// directive can only switch UP from the local default, so it can't force an exact
// version. History (plan 406): go1.26+ crypto/tls panicked quic-go < v0.57.1
// ("crypto/tls bug: where's my session ticket?") on the SERVER side of a QUIC
// handshake, which pinned us to go1.25.0 until go-libp2p v0.50.0 / quic-go
// v0.62.0. node/quic_toolchain_compat_test.go guards that crash.

// 406 — pubsub v0.18.0 fork: limited_conn.go lets pubsub open and keep streams
// over limited (relay-circuit) connections; call sites in comm.go, pubsub.go,
// gossipsub.go and peer_notify.go.
replace github.com/libp2p/go-libp2p-pubsub => ./third_party/go-libp2p-pubsub

// 190 — Android netlink SELinux denial (b/155595000). Same-version (v0.16.1)
// in-repo fork routing manet.InterfaceMultiaddrs through a provider seam whose
// Android default is wlynxg/anet (no netlink bind). Re-applied on v0.16.1 by plan
// 406; a future go-libp2p bump needing a newer go-multiaddr fails LOUDLY at
// compile until the fork is moved. See
// Test-Flight-Improv/190-android-netlink-selinux-addr-visibility-tdd-plan.md.
replace github.com/multiformats/go-multiaddr => ./third_party/go-multiaddr

// 190 — companion fork of go-netroute v0.4.0 (re-applied by plan 406). Two
// changes: a test-only New() failure hook (nil in production) so a darwin host
// test can reproduce Android's netlink-denied routing lane, and a PRODUCTION
// change: on Android New() returns an error before any netlink bind, which stops
// the SELinux audit spam (callers already degrade gracefully on that error).
replace github.com/libp2p/go-netroute => ./third_party/go-netroute

require (
	filippo.io/edwards25519 v1.2.0
	github.com/cloudflare/circl v1.6.3
	github.com/google/uuid v1.6.0
	github.com/libp2p/go-libp2p v0.50.0 // plan 406: bumps are proven by the mixed-version interop test (scripts/test/go_mixed_version_interop.sh) plus a short device LAN run, not the full FDC-S6 soak
	github.com/libp2p/go-libp2p-pubsub v0.18.0
	github.com/libp2p/go-msgio v0.3.0
	github.com/libp2p/go-netroute v0.4.0
	github.com/multiformats/go-multiaddr v0.16.1
	github.com/multiformats/go-multistream v0.6.1
	github.com/tyler-smith/go-bip39 v1.1.0
	golang.org/x/crypto v0.57.0
	golang.org/x/mobile v0.0.0-20260908204917-8b95e45f8d3e
	google.golang.org/protobuf v1.36.11
)

require (
	filippo.io/bigmod v0.1.1-0.20260103110540-f8a47775ebe5 // indirect
	filippo.io/keygen v1.0.0 // indirect
	github.com/benbjohnson/clock v1.3.5 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/davidlazar/go-crypto v0.0.0-20200604182044-b73af7476f6c // indirect
	github.com/decred/dcrd/dcrec/secp256k1/v4 v4.4.1 // indirect
	github.com/dunglas/httpsfv v1.1.1 // indirect
	github.com/filecoin-project/go-clock v0.1.0 // indirect
	github.com/flynn/noise v1.1.0 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/hashicorp/golang-lru/v2 v2.0.7 // indirect
	github.com/huin/goupnp v1.3.0 // indirect
	github.com/ipfs/go-cid v0.6.2 // indirect
	github.com/jackpal/go-nat-pmp v1.0.2 // indirect
	github.com/jbenet/go-temp-err-catcher v0.1.0 // indirect
	github.com/klauspost/cpuid/v2 v2.4.0 // indirect
	github.com/koron/go-ssdp v0.9.1 // indirect
	github.com/libp2p/go-buffer-pool v0.1.0 // indirect
	github.com/libp2p/go-flow-metrics v0.3.0 // indirect
	github.com/libp2p/go-libp2p-asn-util v0.4.1 // indirect
	github.com/libp2p/go-reuseport v0.4.0 // indirect
	github.com/libp2p/go-yamux/v5 v5.1.0 // indirect
	github.com/marten-seemann/tcp v0.0.0-20210406111302-dfbc87cc63fd // indirect
	github.com/mikioh/tcpinfo v0.0.0-20190314235526-30a79bb1804b // indirect
	github.com/mikioh/tcpopt v0.0.0-20190314235656-172688c1accc // indirect
	github.com/minio/sha256-simd v1.0.1 // indirect
	github.com/mr-tron/base58 v1.3.0 // indirect
	github.com/multiformats/go-base32 v0.1.0 // indirect
	github.com/multiformats/go-base36 v0.2.0 // indirect
	github.com/multiformats/go-multiaddr-dns v0.6.0 // indirect
	github.com/multiformats/go-multiaddr-fmt v0.1.0 // indirect
	github.com/multiformats/go-multibase v0.3.0 // indirect
	github.com/multiformats/go-multicodec v0.10.0 // indirect
	github.com/multiformats/go-multihash v0.2.3 // indirect
	github.com/multiformats/go-varint v0.1.0 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/pbnjay/memory v0.0.0-20210728143218-7b4eea64cf58 // indirect
	github.com/pion/datachannel v1.5.10 // indirect
	github.com/pion/dtls/v3 v3.1.2 // indirect
	github.com/pion/ice/v4 v4.0.10 // indirect
	github.com/pion/interceptor v0.1.40 // indirect
	github.com/pion/logging v0.2.4 // indirect
	github.com/pion/mdns/v2 v2.0.7 // indirect
	github.com/pion/randutil v0.1.0 // indirect
	github.com/pion/rtcp v1.2.16 // indirect
	github.com/pion/rtp v1.8.19 // indirect
	github.com/pion/sctp v1.8.39 // indirect
	github.com/pion/sdp/v3 v3.0.18 // indirect
	github.com/pion/srtp/v3 v3.0.6 // indirect
	github.com/pion/stun/v3 v3.1.1 // indirect
	github.com/pion/transport/v3 v3.0.7 // indirect
	github.com/pion/transport/v4 v4.0.1 // indirect
	github.com/pion/turn/v4 v4.0.2 // indirect
	github.com/pion/webrtc/v4 v4.1.2 // indirect
	github.com/prometheus/client_golang v1.24.1 // indirect
	github.com/prometheus/client_model v0.6.2 // indirect
	github.com/prometheus/common v0.70.1 // indirect
	github.com/prometheus/procfs v0.21.1 // indirect
	github.com/quic-go/qpack v0.6.0 // indirect
	github.com/quic-go/quic-go v0.62.0 // indirect
	github.com/quic-go/webtransport-go v0.13.0 // indirect
	github.com/spaolacci/murmur3 v1.1.0 // indirect
	github.com/wlynxg/anet v0.0.5 // indirect
	go.uber.org/dig v1.19.0 // indirect
	go.uber.org/fx v1.24.0 // indirect
	go.uber.org/mock v0.6.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.28.0 // indirect
	golang.org/x/exp v0.0.0-20260718201538-764159d718ef // indirect
	golang.org/x/mod v0.41.0 // indirect
	golang.org/x/net v0.59.0 // indirect
	golang.org/x/sync v0.23.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
	golang.org/x/telemetry v0.0.0-20260908163034-4bcc4b2ee518 // indirect
	golang.org/x/text v0.42.0 // indirect
	golang.org/x/time v0.15.0 // indirect
	golang.org/x/tools v0.50.0 // indirect
	lukechampine.com/blake3 v1.4.1 // indirect
)

tool (
	golang.org/x/mobile/cmd/gobind
	golang.org/x/mobile/cmd/gomobile
)
