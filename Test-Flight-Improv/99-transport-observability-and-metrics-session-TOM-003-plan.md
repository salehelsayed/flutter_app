# TOM-003 - Relay Prometheus Metrics Contract Tests Plan

Status: accepted

## Planning Progress

- 2026-05-29 21:03:04 CEST - Evidence/planning/reviewer/arbiter completed locally under the batch fallback. Files inspected: `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`, `go-relay-server/metrics.go`, `go-relay-server/main.go`, `go-relay-server/inbox.go`, existing relay tests, and Prometheus handler usage. Decision/blocker: no structural blocker; add Go-only tests around existing global collectors using deltas, plus a `promhttp` scrape contract. Next action: execute this plan.

## real scope

Add relay-side tests for the existing Prometheus metrics contract. Do not change metric names, server behavior, relay protocol, inbox semantics, stream handlers, dashboards, or telemetry policy.

## closure bar

TOM-003 is closed when:
- A dedicated `go-relay-server/metrics_test.go` pins representative counter, gauge, counter-vector, gauge-vector, and histogram behavior with delta assertions.
- The live Prometheus handler contract is tested through an HTTP scrape using `promhttp.Handler`.
- Tests assert existing aggregate metric names/labels without peer IDs, message contents, multiaddrs, or per-conversation data.
- `cd go-relay-server && go test ./...` passes.

## source of truth

- Active session contract: TOM-003 in `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`.
- Current Go code/tests beat stale docs.
- `go-relay-server/metrics.go` owns metric names and labels.
- `go-relay-server/main.go` owns the production `/metrics` handler shape through `promhttp.Handler()`.

## session classification

`implementation-ready`

This is Go relay-server test coverage only.

## exact problem statement

Relay Prometheus metrics exist, but no focused test pins representative metric deltas or verifies the handler scrape contract. That leaves the relay-visible half of transport diagnostics under-evidenced.

## files and repos to inspect next

- `go-relay-server/metrics.go`
- `go-relay-server/main.go`
- `go-relay-server/metrics_test.go`

## step-by-step implementation plan

1. Add `go-relay-server/metrics_test.go`.
2. Use `prometheus/testutil.ToFloat64` for counter/gauge delta assertions.
3. Use a histogram metric helper to compare `relay_stream_duration_seconds` sample-count deltas.
4. Use unique non-identifying label values such as `metrics_contract` and `ok`.
5. Scrape `promhttp.Handler()` through `httptest` and assert representative metric names and labels appear.
6. Run `cd go-relay-server && go test ./...`.

## exact tests and gates to run

```bash
cd go-relay-server && go test ./...
```

Final hygiene:

```bash
git diff --check
```

## accepted differences / intentionally out of scope

- No Flutter named gate is required for TOM-003.
- No new relay 1:1-vs-group classification is added.
- No new metric names are introduced unless existing code already exposes them.

## Execution Verdict

Verdict: accepted.

Landed TOM-003 evidence:
- Added `go-relay-server/metrics_test.go`.
- The test pins representative existing counter, gauge, counter-vector, gauge-vector, and histogram behavior with delta assertions.
- The test scrapes `promhttp.Handler()` and verifies representative `/metrics` output for existing relay metric names/labels.
- The scrape test checks for absence of representative identifier/content fragments.

Tests/gates:
- `cd go-relay-server && go test ./...` passed.

Residuals: none for TOM-003. Relay 1:1-vs-group traffic classification remains intentionally out of scope.
