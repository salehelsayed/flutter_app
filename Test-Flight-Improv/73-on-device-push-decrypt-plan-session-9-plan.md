# Session 9 Plan - Legacy Cleanup, Compatibility Retirement, and Closure

## Scope

- Remove dead plaintext preview plumbing now that Session 8 accepted the full simulator smoke matrix:
  - relay `pushTitle` / `pushBody` request fields and group push function parameters
  - Dart `callGroupInboxStore` and group offline replay helper `pushTitle` / `pushBody` parameters
  - client fallback parsing of legacy `pushTitle` / `pushBody` and v1 plaintext preview fields
- Retire the rollout-only relay legacy plaintext metric.
- Keep routing, ciphertext decrypt handling, and frozen fixture assets intact unless a call site proves they are unused.
- Update maintained docs and this session ledger with final ciphertext-only closure evidence.

## Regression Contract

- Message push payloads stay ciphertext-only and do not contain sender names, group names, message text, media descriptors, `pushTitle`, or `pushBody`.
- Contact request, group invite, and introduction static notification contracts remain unchanged.
- Legacy retry rows with extra preview keys remain safe to decode, but retries must not re-emit plaintext preview fields.
- Final acceptance requires the Session 8 accepted gates to remain green for touched surfaces.

## Required Verification

- `dart format` on touched Dart files.
- `go test ./...` from `go-relay-server`.
- Focused Flutter suites for group inbox helper/retry/fallback behavior.
- Named gates touched by cleanup: `baseline`, `1to1`, `groups`, `runtime-telemetry`, `completeness-check`, plus the push release gate.

## Acceptance

Session 9 is accepted only if the cleanup lands without reopening compatibility leaks, docs record the final ciphertext-only contract, and the breakdown final program verdict is updated to accepted.
