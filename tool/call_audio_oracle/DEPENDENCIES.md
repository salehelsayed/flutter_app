# Call audio oracle dependency record

This Go module is a host-test tool. It is not imported by, linked into, or
packaged with the Flutter application. Every Go command for this module must
set `GOTOOLCHAIN=go1.25.0`; `go.mod` declares `go 1.25.0`.

## Direct Go dependencies

The complete transitive graph is pinned by `go.mod` and `go.sum`. The hashes
below are Go's module-zip checksums, followed by the SHA-256 of the license file
in that exact module zip.

| Module | Version | Source revision | License | Module zip (`h1`) | License SHA-256 |
|---|---:|---|---|---|---|
| `github.com/pion/webrtc/v4` | `v4.2.19` | `37a88bd2ed547954c5d35aad9371a3d90563ba24` | MIT | `h1:2usG6s7eXMF08tqqoP3A4CX5XHArZsi1qeXDIIvXMeE=` | `6483daf6c8aa2c8192528e60be098aa82dd18f6d7b96dc8246f4f7c3333fbf3f` |
| `github.com/pion/rtp` | `v1.10.5` | `e61bd16da5287b0ae211a8624aee62b03ff2306c` | MIT | `h1:ip0HhO/wYZqQ4bKS+R99KnZh/GRCmIT0jDXikub7vlE=` | `b85dcd3e453d05982552c52b5fc9e0bdd6d23c6f8e844b984a88af32570b0cc0` |
| `github.com/pion/logging` | `v0.2.4` | `39ff9235799bde6d2c7b3f5e21579159e5bbe332` | MIT | `h1:tTew+7cmQ+Mc1pTBLKH2puKsOvhm32dROumOZ655zB8=` | `87272dba8c4fcf57101a3195f4f53f7b010b6e153b9b0977bb1a3f91acddf691` |
| `go.uber.org/goleak` | `v1.3.0` | `31095c657c34bba405a8d480db27989aa5f60b9c` | MIT | `h1:2K3zAYmnTNqV73imy9J1T3WC+gmCePx2hEGkimedGto=` | `cea390bdf643a06fbdd99fbab18c50e82c34e7bead0d55bf1168bd0d65b9fa32` |

Pion is pinned exactly to `github.com/pion/webrtc/v4 v4.2.19`. It provides the
two headless WebRTC peers only; it is not used as a TURN server.

## coturn runtime

- Source: `https://github.com/coturn/coturn`
- Image: `coturn/coturn:4.17.2-r0`
- OCI image digest:
  `sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e`
- OCI source revision: `34230574e952f51858f2f2166dab162d448e7809`
- License: BSD-3-Clause

The machine-readable copy is `coturn.lock.json`. The fixture launcher must
verify its container against that exact image and digest. The oracle accepts
only two already-issued short-lived REST credentials through a private
mode-0600 file; the coturn REST shared secret is neither accepted nor needed.
That input must also carry `fixture_instance_sha256`, set to the fixture's
`CoturnContainerIdentitySHA256`, so identical host/port reuse cannot replay a
prior oracle pass.

## Known signal fixture

`../../test/shared/fixtures/call/known_signal_48khz_mono.ogg` is a 48 kHz mono,
non-speech, self-generated signal dedicated under CC0-1.0. Its formula,
encoder versions, Opus/RTP properties, file SHA-256, and ordered-payload
SHA-256 are pinned in the adjacent provenance JSON. The oracle validates both
digests before opening a peer connection.

## Integration invocation

From this directory:

```sh
CALL_AUDIO_ORACLE_CREDENTIALS_FILE=/private/mode-0600/credentials.json \
CALL_AUDIO_ORACLE_RESULT_FILE=/private/mode-0700/result.json \
GOTOOLCHAIN=go1.25.0 \
go test -tags=integration ./... \
  -run '^TestKnownOpusBothDirectionsOverRestAuthenticatedCoturn$' \
  -count=1 -v -timeout=10m
```

The result path must not already exist. The test creates a mode-0600 result
whose fixed schema contains only public dependency/fixture digests and boolean
proof outcomes. `turn_authority_sha256` binds that result to the canonical
credential URL without disclosing the URL, while `fixture_instance_sha256`
binds it to that disposable coturn instance without disclosing the container
identity. Credentials, REST secrets, URLs, addresses, candidates, SDP, RTP
counters, raw identifiers, and audio payloads are never written to it.
