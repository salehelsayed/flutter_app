# Relay call-control observability validation

Owned production changes: `go-relay-server/call_control_handler.go` and new `go-relay-server/call_control_metrics.go`. Focused tests: `go-relay-server/call_control_metrics_test.go`. The outer inbox gateway and wire responses remain unchanged.

The handler now emits exactly one `relay_call_control_requests_total{action,outcome,wake}` observation per invocation. Each label has an explicit finite allowlist. Wake results are observed whether or not the client requests the additional wire receipt field. Metrics describe signaling handler results, not media success or confirmed response delivery.

Journal diagnostics contain only fixed `action`, `outcome`, and `wake` fields for request failures, failed wake dispatch, and explicit cancel/endpoint/token/wake-grant revoke results. They preserve server log timestamps. Successful store, retrieve, and ACK operations do not create these diagnostic rows. No request identifiers, token material, provider error text, event envelopes, or candidates enter the new metrics or diagnostic rows.

## Validation

The first focused run failed because all expected observations had delta zero. After implementation:

```sh
cd go-relay-server
go test -count=1 -run '^TestCallControlMetrics' .
```

Passed. The five tests cover store admission, failed and successful wake dispatch, legacy wake-receipt opt-in preservation, duplicate wake suppression preservation, ACK/noop/empty polling, cancellation and replay rejection, malformed/unsupported requests, unavailable-backend error precedence, stale/current token withdrawal, endpoint withdrawal, log volume, exact one-observation accounting, and privacy fallback for unknown values.

```sh
go test -race -count=1 -timeout=120s -run '^TestCallControlMetrics|^TestVC202(CallActionsAreRegisteredOnAuthenticatedInboxProtocol|ProductionProtocolRegistrationRoutesCallControlActions|RetrieveResponseFitsFrameAndPreservesHasMore)' .
```

Passed, 14.709 seconds test runtime; no race reported.

```sh
go test -count=1 -timeout=90s -run '^TestVC202(RedisBootstrapComposesCallControlOnlyForDurableBackend|CallHandlerEnforcesActionLocalFieldsAndSignedAuthorityLifecycle)$' .
```

Passed, 57.485 seconds test runtime. `git diff --check` passed for the owned files.

Graphify branch context: query `70e7b4a51dc54b1c`, evidence digest `c41ae9d743a48087`. Affected analysis completed for all three owned files, query `1c277903bcf24e95`. Aggregate architecture refresh belongs to the coordinating task.

## Build handoff

Read-only production `uname -m` returned `x86_64`. Local toolchain: `go1.27.0`, Darwin arm64. Starting HEAD: `d8b919c5b34575d570a78eb5fbbc4203f56f875b`; the task includes uncommitted source changes, so that commit alone does not identify a release binary.

After aggregate source changes and checks settle, the coordinating task can build from `go-relay-server`:

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=true -o /absolute/evidence/path/relay-server-linux-amd64 .
go version -m /absolute/evidence/path/relay-server-linux-amd64
shasum -a 256 /absolute/evidence/path/relay-server-linux-amd64
```

Preserve the build-info output, binary hash, toolchain, and hashes of the aggregate changed source files for exact provenance. This worker did not build a release binary, modify the server, or deploy.
