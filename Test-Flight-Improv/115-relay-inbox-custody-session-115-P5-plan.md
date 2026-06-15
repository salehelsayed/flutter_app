Status: residual_only

# Doc 115 Session 115-P5 Plan - Acceptance, Gate Capture, Deploy Evidence, And Closure

## Planning Progress

- 2026-06-13T07:22:00Z - Intake started after `115-P4` was accepted with P5 gate policy and deployment evidence still pending.
- 2026-06-13T07:24:00Z - Graph-first orientation ran against `graphify-arch` for `offline_inbox_roundtrip FakeP2PNetwork withDeliveryReceipts`, gate docs/scripts, and `relay_test InboxStoreDetailed ErrInboxFull`.
- 2026-06-13T07:27:00Z - Source reads confirmed two P5 acceptance gaps:
  `offline_inbox_roundtrip_test.dart` uses the local `FakeP2PNetwork` from
  `two_user_message_exchange_test.dart`, whose inbox has no cap/reject model;
  and `sendChatMessage` still calls only bool `P2PService.storeInInbox`, so a
  P4 typed `INBOX_FULL` cannot yet be handled as retryable `sent`.
- 2026-06-13T07:29:00Z - Source reads confirmed the local Go relay integration
  harness stores inbox messages without cap/reject metadata, so the typed
  `ErrInboxFull` proof belongs in `go-mknoon/integration` by extending that
  harness rather than depending on the external production relay.
- 2026-06-13T07:42:00Z - Implementation and QA accepted host-side P5. The
	  remaining evidence is external release evidence: staging/production relay
	  deploy, live TTL/cap probes, two-device drain/receipt proof, and old
	  TestFlight interop.
- 2026-06-13T15:07:40Z - Final deploy re-audit completed. Production relay
  deployment to `mknoun.xyz` is verified; two-device, lowered-cap/TTL staging,
  and old-TestFlight proof remains unclaimed residual lab evidence.

## Real Scope

Implement Phase 5 host-side acceptance and closure prep:

- Wire a detailed inbox-store seam into `sendChatMessage` without changing the
  `P2PService` interface, so P4 `INBOX_FULL` persists a truthful retryable
  `sent` row with retained `wireEnvelope`.
- Add fake-network whole-system coverage for cap-rejected send repair and
  lost-receipt repair.
- Extend the local Go relay integration harness to prove typed `INBOX_FULL`
  through `Node.InboxStoreDetailed` against a cap-limited local relay.
- Capture doc-115 gate classification in `test-gate-definitions.md` and
  `scripts/run_test_gates.sh` for host-run suites.
- Resolve or explicitly policy-close the broad `go-mknoon` gate caveat left by
  `115-P4`.
- Update this session plan, the breakdown ledger, and the source doc with
  closure evidence.

Out of scope:

- No fabricated two-physical-device screenshots or TestFlight old-app proof. If
  devices/builds are not available in this run, record those as unclaimed
  residual lab evidence under final doc status.
- No broad refactor of the two independent fake-network classes beyond the
  acceptance surfaces needed by P5.
- No `P2PService` or `MessageRepository` interface changes.

## Source Of Truth

- `Test-Flight-Improv/115-relay-inbox-custody.md` Phase 5.
- `Test-Flight-Improv/115-relay-inbox-custody-session-breakdown.md`.
- P4 plan verdict:
  `Test-Flight-Improv/115-relay-inbox-custody-session-115-P4-plan.md`.
- Acceptance files:
  `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`,
  `test/features/conversation/integration/two_user_message_exchange_test.dart`,
  `lib/features/conversation/application/send_chat_message_use_case.dart`,
  `go-mknoon/integration/local_relay_harness_test.go`,
  `go-mknoon/integration/relay_test.go`,
  `Test-Flight-Improv/test-gate-definitions.md`, and
  `scripts/run_test_gates.sh`.

## Implementation Steps

1. Add an optional `StoreInInboxDetailedFn? storeInInboxDetailed` parameter to
   `sendChatMessage` and use it only for the sequential inbox fallback. Keep
   `P2PService.storeInInbox` as the default compatibility path.
2. On detailed accepted outcomes, persist `inboxed` with retained envelope and
   `relayExpiresAt`; on `rejectedFull`, persist `sent` with retained envelope
   and emit truthful telemetry; on other failures, preserve the existing
   generic `failed` behavior.
3. Thread the real impl-level detailed store from production call sites that
   already hold `P2PServiceImpl`, where locally safe. Test-only callers may pass
   the seam directly.
4. Extend the local `FakeP2PNetwork` in
   `two_user_message_exchange_test.dart` with optional `maxInboxPerPeer`,
   reject-new behavior, and a detailed outcome helper used by P5 tests.
5. Add/extend `offline_inbox_roundtrip_test.dart` coverage for:
   cap reject -> sender row stays non-delivered `sent` with envelope;
   recipient drains accepted entries;
   sender custody/retry re-stores after capacity frees;
   receipt flips to `delivered`; and lost receipt after drain/ack-delete is
   repaired by re-store + duplicate receipt.
6. Extend the local Go relay harness with cap-limited store responses carrying
   `INBOX_FULL`, `rejected_full`, `occupancy`, and `capacity`; add an
   integration test proving `errors.Is(err, node.ErrInboxFull)` via
   `InboxStoreDetailed` and accepted entries remain retrievable.
7. Update gate docs/scripts for doc-115 host suites and run completeness.
8. Re-run the P4 broad go-mknoon gate or record a final accepted gate policy if
   the broad suite still times out only through existing order/runtime
   accumulation while focused and isolated tests pass.
9. Run focused host gates, `git diff --check`, and
   `./graphify-arch/refresh_arch_graph.sh` from the repo root.

## Closure Bar

`115-P5` is accepted locally when host-side acceptance tests prove the end-to-end
cap/lost-receipt contract, Go integration proves typed local-relay
`INBOX_FULL`, gate docs/scripts classify the new suites, P4's broad go-mknoon
gate caveat is resolved or explicitly policy-closed, and the source doc records
which external deploy/device evidence remains unavailable versus completed.

## Execution Summary

- Added the detailed inbox-store seam to `sendChatMessage` while keeping the
  `P2PService` interface unchanged. Detailed accepted outcomes persist
  `inboxed`; typed `INBOX_FULL` persists a retryable non-delivered `sent` row
  with `wireEnvelope` retained.
- Added shared fake-network capacity/reject behavior and P5 offline-inbox
  acceptance tests for cap-reject repair and lost-receipt repair through
  re-store plus duplicate receipt.
- Added local relay harness capacity metadata and
  `TestInboxStoreFull_TypedRejectionAgainstLocalRelay`, proving
  `errors.Is(err, node.ErrInboxFull)` against a cap-limited local relay.
- Expanded the 1:1 gate scripts/docs to include Doc 115 custody, receipt,
  migration, router, retrier, bridge, media, and identity guard suites.
- Updated `delivered_status_minting_sites_test.dart` to remove the stale
  `retry_unacked_messages_use_case.dart` temporary delivered-write exception;
  unacked retry now persists `inboxed` and waits for receipts.

## Verification Evidence

- `flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart test/features/conversation/application/verify_inbox_custody_use_case_test.dart` passed (`/tmp/doc115_p5_focused_flutter_combined.log`, 19 tests).
- `flutter test test/features/conversation/application/delivered_status_minting_sites_test.dart` passed after the guard update and format (`/tmp/doc115_p5_delivered_status_guard_after_format.log`, 2 tests).
- `./scripts/run_test_gates.sh 1to1 --list` and
  `./scripts/run_host_test_gates.sh 1to1 --list` agreed on 38 host files.
- `./scripts/run_test_gates.sh completeness-check` passed (`841/841`).
- `./scripts/run_test_gates.sh 1to1` passed on rerun
  (`/tmp/doc115_p5_1to1_gate_rerun.log`, 788 tests).
- `cd go-relay-server && go test -count=1 ./...` passed
  (`/tmp/doc115_p5_relay_all.log`).
- `cd go-mknoon && go test -tags integration ./integration -run TestInboxStoreFull_TypedRejectionAgainstLocalRelay -count=1` passed
  (`/tmp/doc115_p5_go_integration_inbox_full_2.log`).
- Direct rechecks for the two files implicated by the first noisy expanded-gate
  run passed: `p2p_bridge_client_test.dart` and
  `pending_message_retrier_upload_ordering_test.dart`.
- `dart format test/features/conversation/application/delivered_status_minting_sites_test.dart` completed.
- `git diff --check` passed after formatting.
- `./graphify-arch/refresh_arch_graph.sh` passed from the repo root and
  regenerated `graphify-arch/GRAPH_SELECTION.md` plus `comparison.json`.

## Gate Policy

The broad P4 `cd go-mknoon && go test -count=1 -timeout=180s ./...` timeout is
policy-closed for Doc 115 P5. The timed-out aggregate run was isolated to
pre-existing long-running group-history/multi-device tests in `bridge` and
`node`; the named culprit tests passed in isolation during P4, all non-node /
non-bridge packages passed, focused P4 node/bridge/testpeer gates passed, and
the P5 local-relay integration proof passed. Until the broad go-mknoon suite is
split or its aggregate timeout is fixed, Doc 115 relies on focused package
gates plus the local relay integration proof for this acceptance slice.

## Residual Evidence Archive

- Production relay deploy was completed after the initial P5 acceptance pass:
  `/tmp/relay-server-doc115-linux-amd64`
  (`sha256=3d732c11f4d4ce4ba72a03d2440571c66f2b183677f4e6c19850bddddffe1bf5`)
  was installed on `mknoun.xyz`, the previous binary was backed up as
  `/usr/local/bin/relay-server.backup.20260613T145030Z`, `relay-server` was
  active, `relay-server v1.5.1` reported, the installed hash matched the local
  artifact, and SSH-local metrics exposed the new Doc 115 counters.
- Public `:2112` metrics remains firewall-blocked, so production metrics proof
  is SSH-local.
- No live lowered-cap/TTL staging probe was run.
- No two-physical-device drain/receipt proof was collected.
- No old TestFlight interop proof was collected.

Those are archived residual lab evidence items, not host-code blockers.
