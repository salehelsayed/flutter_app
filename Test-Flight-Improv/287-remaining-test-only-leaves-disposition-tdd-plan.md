# 287 - Remaining Test-Only Leaves Disposition (DTR-11)

Status: Approved — implementation and evidence in progress  
Type: Modification  
Spec: DTR-11, roadmap Wave 3 — map and disposition remaining test-only leaves  
Classification: owner-approved exact disposition boundary  
Closure tier: host + Wave-3 aggregate

## Problem And Exact Candidate Map

DTR-01 classified 60 app sources as reachable only from test or integration
origins. Re-deriving that historical set from audit snapshot `a68aacee7482` and
subtracting the already-owned account-migration, Posts, Group-list, superseded
group, and other DTR-10 slices leaves exactly the following 11 paths. Their
current line counts total exactly 1,065 LOC.

Every path has zero production importers. The only cross-test reference is
`letter_card_test.dart`, which imports `reaction_display.dart` solely to make
negative assertions about a type the live `LetterCard` path never constructs.
All 11 paths are currently represented by generic test/integration-only
`explained-root` declarations in `runtime_roots.json`.

| # | Exact app path | LOC | Terminal disposition | Live owner / proof retained |
|---:|---|---:|---|---|
| 1 | `lib/features/contact_request/presentation/widgets/pending_requests_badge.dart` | 49 | Retire source and SUT-only test | Contact-request notification materialization and the live dialog/Feed route |
| 2 | `lib/features/conversation/presentation/widgets/reaction_display.dart` | 65 | Retire source/test and stale type-only assertions | `LetterCard._buildReactionChipWidgets` grouping, counts, own highlight, and taps |
| 3 | `lib/features/feed/application/feed_projection.dart` | 42 | Retire duplicate source; migrate its parity suite | `FeedStore.replaceContactSnapshot` and `replaceGroupSnapshot`, as called by `FeedWired` |
| 4 | `lib/features/identity/application/recover_identity_from_secure_store_use_case.dart` | 68 | Retire source and SUT-only test | Explicit manual restore and startup's no-automatic-restore policy |
| 5 | `lib/features/introduction/presentation/widgets/intros_tab.dart` | 235 | Retire source and two SUT-only suites | Orbit's `OrbitIntrosViewData`, folded intro sliver/entries, and `IntroRow` |
| 6 | `lib/features/p2p/application/discover_peer_use_case.dart` | 123 | Retire wrapper and SUT-only test | `P2PService.discoverPeer` and live bounded discovery/dial flows |
| 7 | `lib/features/p2p/application/send_message_use_case.dart` | 68 | Retire wrapper and SUT-only test | Live send funnels and `P2PService.sendMessage`/`sendMessageWithReply` |
| 8 | `lib/features/p2p/application/stop_node_use_case.dart` | 63 | Retire wrapper and SUT-only test | `P2PService.stopNode`, lifecycle teardown, and stop-race proof |
| 9 | `lib/features/push/application/push_preview_telemetry_gate.dart` | 94 | Relocate unchanged to `tool/telemetry/` | Release/TestFlight 3% calculator and curated `runtime-telemetry` gate |
| 10 | `lib/features/qr_code/application/handle_scanned_qr_use_case.dart` | 139 | Retire duplicate source/test after live-path proof migration | `QRScannerWired`, canonical build/parse functions, encrypted request/profile side effects |
| 11 | `lib/features/qr_code/domain/models/qr_payload_model.dart` | 119 | Retire stale model and SUT-only test | Canonical `buildQRPayload` and `parseQRPayload` wire contract |
|  | **Total** | **1,065** | **10 retired; 1 relocated out of `lib/`** | No deferred leaf |

Direct test disposition is exact:

- Delete ten SUT-only suites:
  `pending_requests_badge_test.dart`, `reaction_display_test.dart`,
  `recover_identity_from_secure_store_use_case_test.dart`, `intros_tab_test.dart`,
  `intros_tab_extended_test.dart`, `discover_peer_use_case_test.dart`,
  `send_message_use_case_test.dart`, `stop_node_use_case_test.dart`,
  `handle_scanned_qr_use_case_test.dart`, and `qr_payload_model_test.dart`.
- Retain and migrate `feed_projection_test.dart` onto `FeedStore`.
- Retain `letter_card_test.dart`, removing only the stale import and
  `ReactionDisplay` absence assertions; its live inline-reaction assertions stay.
- Retain `push_preview_telemetry_gate_test.dart`, changing only its import to
  `tool/telemetry/push_preview_telemetry_gate.dart`.
- Add the missing blank-introducer/long-name assertion to the live Orbit screen
  suite and the encrypted-envelope/profile-download assertion to the live QR
  scanner suite before retiring the duplicate SUTs.
- Remove all 11 matching runtime-root declarations atomically.

## Authorization Recorded (`DTR11-AUTH-01`)

On 2026-07-27, the current authenticated project owner explicitly identified
themself as owner and authorized DTR-11 to finish the missing work.

`DTR11-AUTH-01` authorizes:

1. The exact 11-path, 1,065-LOC candidate map above.
2. Deletion of ten app sources and relocation of the 94-line push telemetry
   calculator unchanged to `tool/telemetry/`.
3. The exact test migration/deletion set above and removal of all 11 matching
   `runtime_roots.json` declarations.
4. Removal of only the now-write-only
   `GroupBacklogRetentionNotice.listSummary` field and constructor/factory
   arguments.
5. Removal of exactly two newly orphaned localization keys from all three ARB
   locales, followed by `flutter gen-l10n`:
   `group_backlog_mixed_list_summary` and
   `group_backlog_expired_list_summary`.
6. Removal of the inert routing-smoke
   `CHAT_MSG_SEND_RELAY_PROBE_BEGIN` filter, `s15ProbeEvents`,
   `probeAttempted` signal field, and print-only runner output, with S15's real
   send-path/outcome/e2e proof retained.
7. Registration of `test/unit/**/*_test.dart` under `core-host-all`, including
   usage text, documentation, and exact batch-contract proof.
8. Current roadmap, index, C4, inventory, gate, and dead-code reconciliation.

`DTR11-AUTH-01` explicitly does **not** authorize:

- removal or semantic refactoring of `_RaceResult.relayProbeEligible`;
- changes to relay selection, failure classification, message/introduction
  transport, `P2PService.probeRelay`, native or Go code, wire formats, storage,
  migrations, or schemas;
- automatic identity restoration from a surviving secure-store mnemonic;
- behavior changes to live Orbit Intros, LetterCard reactions, Feed snapshots,
  QR scanning, P2P lifecycle, or backlog banner/empty-state behavior; or
- DTR-13's separate QA + release decision. Clearing its temporal Wave-3
  dependency is not approval of that scope.

## Four Upstream Carry-Ins

### `_RaceResult.relayProbeEligible`

Disposition: **Retain without a production edit**. The field is read while
aggregating race failures and determines which failure reason wins. Removing it
is a live behavior refactor, which must not be combined with this deletion
slice. The structural contract requires both its read and classification
writes to remain; the `FDC-03-03b` test remains the causal behavior sentinel.

### `GroupBacklogRetentionNotice.listSummary`

Disposition: **Remove the dead field only**. The enclosing
`groupBacklogRetentionNoticeFor` factory remains live-called. Remove the field,
its constructor/factory arguments, and the two exact orphan keys while
preserving `bannerText`, the empty-state fields, the live factory call, and the
IR-016/history-gap-repair tests.

### Routing-smoke relay-probe filter

Disposition: **Remove inert diagnostics only**. Delete the retired event
filter, derived signal field, and runner interpolation. Rename stale S15 prose
to describe rendezvous-gap relay delivery, while preserving success,
`sendPath`, and end-to-end receive evidence.

### `test/unit/**` family registration

Disposition: **Register under `core-host-all`**. The family becomes the union
of `test/core/**/*_test.dart`, `test/unit/**/*_test.dart`, and the existing
Android renderer manifest contract when not Dart-only. The shell contract must
prove the exact sorted current `test/unit` inventory is present once.

## Test Contract

| Case | Guarantee | Proof |
|---|---|---|
| TC-287-01 | Exact 11 app paths are gone, telemetry exists only in tooling, ten SUT-only suites and 11 manifest rows are gone, and every live owner remains | `dtr11_remaining_test_only_leaves_disposition_test.dart` |
| TC-287-02 | Incremental contact/group snapshots equal a projected cold reload | Migrated `feed_projection_test.dart`; `feed_store_test.dart`; Feed gate |
| TC-287-03 | LetterCard reactions, Orbit intro fallbacks/actions, and manual/no-auto identity restore policy remain | LetterCard, Orbit screen, startup recovery, restore suites |
| TC-287-04 | P2P discovery/send/stop and QR build/parse/scanner behavior remain covered | Service/lifecycle and QR live-path suites |
| TC-287-05 | `listSummary` and two keys are absent while live retention and history-gap UI remains | DTR structural contract, l10n integrity, IR-016/repair selectors |
| TC-287-06 | Relay failure classification remains while obsolete routing diagnostics are absent | DTR structural contract and `FDC-03-03b` |
| TC-287-07 | `core-host-all` contains every `test/unit/**` suite exactly once | `host_test_gate_batch_contract_test.sh`; actual core family |
| TC-287-08 | Current architecture, inventory, gate, roadmap, and aggregate totals match the disposition | Current-doc census and diff hygiene |

TC-287-01 and the unit-family shell assertion are written before implementation
and must fail for their documented reasons. Existing live-owner sentinels are
honest preservation GREENs, not invented behavioral REDs.

## Execution And Gate Cadence

1. Complete and archive the separate Wave-2 aggregate before DTR-11 source
   edits.
2. Record `DTR11-AUTH-01`; capture the exact line census and working-tree state.
3. Add and run TC-287-01 and the host family assertion to record causal RED.
4. Migrate retained Feed, LetterCard, Orbit, QR, and telemetry proof before
   deleting their duplicate SUTs.
5. Apply the exact source/test/manifest dispositions and four carry-ins; run
   `flutter gen-l10n`.
6. Run focused causal/preservation tests, runtime-root and l10n integrity,
   strict analysis, completeness, shell gate contracts, and curated
   `runtime-roots`, `feed`, `intro`, `runtime-telemetry`, `groups`, and `1to1`.
7. Run affected `feature-host-all` and `core-host-all`. Full `host-all` is not
   a per-plan gate.
8. Refresh Graphify once with
   `./graphify-arch/refresh_arch_graph.sh --incremental`.
9. Mark the plan Plan-green, freeze the integrated Wave-3 state, and run the
   separate Wave-3 aggregate:

   ```bash
   ./scripts/run_host_test_gates.sh host-all \
     --continue-on-failure \
     --batch-flutter \
     --concurrency 4 \
     --reporter failures-only
   ```

10. Only after that aggregate passes: mark DTR-11 and Wave 3 Wave-accepted,
    unblock DTR-12 planning, and clear DTR-13's temporal label while leaving it
    decision-blocked on its separate QA + release owner decision.

No device proof is required: the approved work changes no mobile OS boundary,
native implementation, wire protocol, storage, or user-visible behavior.

## Rollback

Rollback is file-local and has no data/native migration:

1. Restore the ten retired sources and ten SUT-only suites.
2. Move the telemetry calculator back under `lib/` and restore its import.
3. Restore the eleven manifest declarations.
4. Restore `listSummary`, both keys in all locales, and regenerate l10n.
5. Restore the routing diagnostic field/filter/output.
6. Restore the former `core-host-all` inventory and docs.
7. Re-run the focused, runtime-root, l10n, and gate-contract checks.

A Wave-3 aggregate failure blocks wave acceptance; it does not authorize an
unrelated rollback or scope expansion.

## Done Criteria

DTR-11 is complete only when the exact map and owner receipt are recorded,
every candidate and carry-in has a terminal disposition, runtime-root drift is
zero, migrated/preserved behavior is green, `test/unit/**` is registered and
executed, current docs reconcile, Graphify is refreshed, and the separately
archived Wave-3 `host-all` passes.

## Execution Evidence

Pending. This section will record causal RED, focused/curated/family results,
the tested integrated tree, Graphify fingerprint, Wave-3 aggregate totals,
stable log hashes, and the final roadmap transition.
