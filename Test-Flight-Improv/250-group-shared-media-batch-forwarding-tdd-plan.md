# 250 - Group Shared Media Batch Forwarding

Status: accepted
Type: New Feature
Wave: Track 2 / Wave 2 / Forwarding
Dependencies: accepted Plan 236, accepted Plan 237, and the shared Plan 249 forwarding foundation
Closure tier: host composition over already-proven ordinary direct/group media delivery

## Outcome

Discussion-group shared-media libraries now expose internal Batch Forward for an eligible selection of 2..10 items. The implementation creates one ordinary forwarded message per selected attachment and target, preserves an independent editable caption for every item, validates current source and target state, and reports a truthful source-item-by-target result matrix. It does not introduce albums, a new wire format, transport behavior, database migration, or durable batch job.

Single-item Forward remains the Plan 236 route. Existing Save, OS Share, Bookmark, Delete and Evict actions remain unchanged.

## Accepted Decision Ledger

Accepted on 2026-07-12 for Track 2 / Wave 2.

| Decision | Accepted contract | Executable oracle |
|---|---|---|
| Output unit | One ordinary destination message per selected attachment per target; never combine the selection into an album. | Draft and delivery suites assert exact item-by-target calls and settled identities. |
| Ordering | Canonical source order is parent timestamp DESC, message ID DESC, attachment ID DESC. | `GBF-02 owner scoped draft output order and captions match approved contract`. |
| Captions | Each output starts with its own parent caption and is independently editable or clearable. No first-caption, concatenation or batch-caption fallback. | Draft test plus the real routed picker test. |
| Provenance and idempotency | Generate an opaque random base per source item, then domain-separate by target kind and target. Keys are retry-stable and contain no source group/message/attachment identity. | Delivery and announcement provenance suites. |
| Selection bound | The reusable foundation accepts 1..10; the visible batch route accepts 2..10. Enforce current per-MIME limits and at most 500 MiB aggregate current bytes before picker/delivery. No additional duration cap was introduced. | Draft, preflight and presentation suites. |
| Source policy | Exact ordinary incoming, verified, group-owned image/video entries from one active discussion source. Re-resolve the current row/file/hash; no redownload and no caller path trust. | Draft, source-gate and delivery suites. |
| Destination policy | Current active contacts and current active writable `GroupType.chat` groups only. Announcement and QA groups are excluded for a discussion source. | Presentation, picker and authorization suites. |
| Authorization race | A contact is reloaded at final dispatch. A group requires a coherent current group/member/key-generation snapshot and exact send-time role; missing capability or any drift fails before upload. | `GBF-04` authorization suite and real SQL helper test. |
| Partial result and retry | Track every source-item × target cell as sent, queued or failed. Sent/queued cells are immutable; retry only failed cells for the same route and stable operation identity. | `group_media_batch_forward_delivery_test.dart`. |
| Restart behavior | Route-local only. Closing/restarting abandons the batch; there is no durable resume/cancel promise and no migration. | Delivery coordinator model and absence of persistence/schema change. |
| Recipient contract | Reuse the accepted Plan 236 ordinary forwarded-message marker, destination-specific upload/encryption/access and recipient rendering. | Plan 236 preservation sentinels and batch delivery tests. |

All previously unresolved decisions are closed. No product choice remains as an implementation blocker.

## Scope And Invariants

In scope:

- A bounded 2..10-item batch action from a `GroupType.chat` shared-media library.
- Exact `GroupSharedMediaIdentity` values from one source group.
- Independent caption editing and one ordinary output per item/target.
- Active contact and writable discussion-group targets.
- Current source verification, current destination authorization, partial truth and failed-cell retry.

Preserved:

- Plan 236 single-item Forward and its forwarded marker, fresh destination IDs/crypto/access, retry behavior and origin-minimizing payload.
- Plan 237 library identity, ordering, selection and sibling actions.
- Source message, attachment, file and bookmark state.
- Announcement/QA authorization and destination policy.
- Existing direct/group transport, pubsub, group-key and recipient behavior.

Explicitly absent:

- Album semantics or attachment-level wire captions.
- Original sender, source group, source message or source attachment metadata in destination payloads or recipient-visible diagnostics.
- Cross-target ciphertext, nonce, key, blob ID or allowed-peer reuse.
- Source redownload, source publish/inbox commands or source-row mutation.
- Durable batch persistence, a database migration, a new group message type, or Go/libp2p production changes.

## Implementation Manifest

Primary production surfaces:

- `lib/features/groups/application/group_media_batch_forward.dart`
- `lib/features/share/application/group_media_batch_forward_delivery_coordinator.dart`
- `lib/features/share/presentation/screens/group_media_batch_forward_picker_screen.dart`
- `lib/features/share/presentation/screens/group_media_batch_forward_picker_wired.dart`
- `lib/features/share/presentation/navigation/group_media_batch_forward_picker_route.dart`
- `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_forward_authorization_db_helpers.dart`
- `lib/main.dart`

Supporting compatibility/test surfaces:

- `lib/features/groups/application/group_shared_media_library_controller.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/share/application/announcement_forward_test_harness.dart`

The database helper reads group state, fully aliased ordered member rows and `MAX(key_generation)` in one SQL `SELECT`. `GroupRepositoryImpl` exposes that as the optional coherent-snapshot capability. Picker eligibility and final dispatch fail closed without the capability; final dispatch uses it as the last awaited group authority before upload.

## Actual Test Contract

The following nine files are registered in `GROUP_TESTS` in this exact order. Rows 1..5 are the shared Plan 250/251 foundation, row 6 is the Plan 250 presentation owner, and rows 7..9 are Plan 251 owners. The core/feature host families discover and sort matching tests automatically; they do not promise this manual order.

1. `test/features/groups/application/group_media_batch_forward_draft_test.dart`
2. `test/features/groups/application/group_media_batch_forward_preflight_test.dart`
3. `test/features/groups/application/group_media_batch_forward_authorization_test.dart`
4. `test/core/database/helpers/group_forward_authorization_db_helpers_test.dart`
5. `test/features/groups/application/group_media_batch_forward_delivery_test.dart`
6. `test/features/groups/presentation/group_shared_media_batch_forward_test.dart`
7. `test/features/groups/presentation/announcement_media_batch_forward_test.dart`
8. `test/features/share/presentation/announcement_batch_forward_target_policy_test.dart`
9. `test/features/share/application/announcement_batch_forward_provenance_test.dart`

Plan 250 causal coverage includes:

- `GBF-02` exact scope/order/caption construction, 1..10 foundation bound, invalid scope/duplicate/source-derived token denial.
- `GBF-03` per-MIME and 500 MiB aggregate preflight before target or delivery work.
- `GBF-04` strict contact reload and coherent group snapshot denial for missing capability, membership/role/key drift, inactive/unsupported/source targets and discussion-to-announcement widening.
- Real single-statement SQL alias/no-member/current-generation mapping.
- Source×target delivery settlement, stable retry and no resend of sent/queued cells.
- 2..10 discussion-library entry behavior, typed size denial, single-item preservation and discussion-only target policy.

## Executed Evidence

Focused GREEN on 2026-07-12:

```bash
flutter test --no-pub \
  test/features/groups/application/group_media_batch_forward_draft_test.dart \
  test/features/groups/application/group_media_batch_forward_preflight_test.dart \
  test/features/groups/application/group_media_batch_forward_authorization_test.dart \
  test/core/database/helpers/group_forward_authorization_db_helpers_test.dart \
  test/features/groups/application/group_media_batch_forward_delivery_test.dart \
  test/features/groups/presentation/group_shared_media_batch_forward_test.dart \
  test/features/groups/presentation/announcement_media_batch_forward_test.dart \
  test/features/share/presentation/announcement_batch_forward_target_policy_test.dart \
  test/features/share/application/announcement_batch_forward_provenance_test.dart \
  --reporter compact
```

Result: exit 0, 30/30 tests passed.

Controlled mutation re-RED evidence captured on 2026-07-12:

| Mutation | Command/oracle | RED result | Restoration |
|---|---|---|---|
| Shared route minimum `2 -> 3` | Run the draft, discussion presentation and announcement presentation files together. | Exit 1. The exact route-min assertion failed (`expected 2, actual 3`) and both Plan 250/251 two-item Batch Forward entry tests failed because the action disappeared. | Restore `2`; exact nine-file aggregate returned 30/30. |
| Plan 250 authorization: temporarily treat a chat `MemberRole.reader` as writable in `canDeliverAnnouncementForwardToGroup`. | `flutter test --no-pub test/features/groups/application/group_media_batch_forward_authorization_test.dart --plain-name 'GBF-04 chat own-member writer to reader prevents upload' --reporter expanded` | Exit 1. The mutation crossed the denial boundary, performed upload/send work and changed the expected failure count from 1 to 0. | Restore admin-or-chat-writer policy; exact test returned 1/1 and the final nine-file aggregate returned 30/30. |

The mutations were applied and reversed with exact patches; neither mutation remains in the production diff.

Preservation evidence completed before final integrated gates:

| Dependency | Evidence result |
|---|---|
| Plan 236 | Group forward policy/intent/flow 9/9; `GMF-` coordinator 3/3; `GMF-08` listener 1/1; non-admin announcement send denial 1/1. |
| Plan 237 | `GML-05` 1/1, `GML-06F` 1/1, transport boundary 1/1, batch actions 2/2, current `GML-10 production nested route consumes bounded anchor result` 1/1. |
| Plan 240 | Canonical eight-file family 10/10; wired picker 16/16; native announcement writer lifecycle regex passed. |
| Plan 241 | `AML-07` + `AML-11` 2/2; native writer/validator regex passed. |
| Plan 249 | Canonical five-file foundation/picker/transport set 30/30; received-media transport baseline 1/1. |

Scoped analysis of the changed forwarding/authorization/picker surfaces completed with no issues. The final hygiene and affected-graph checks are recorded at handoff.

## Device And Boundary Decision

This plan composes the already-accepted one-item Plan 236/Plan 249 ordinary sends. It adds no payload field, codec, schema, pubsub behavior, crypto primitive or native boundary claim. Therefore the real device/crypto proof is inherited from those plans and the new proof tier is host orchestration. No unavailable device is a closure condition, and no simulator-only claim is made.

## Final Acceptance Gates

Per the project TDD cadence, do not run full `host-all` for this individual plan. Final integrated closure requires the affected curated lane plus the justified core and feature family sweeps because this wave changes a core database helper and feature orchestration:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all
```

Integrated gate results on 2026-07-12:

- `groups`: `2171/2171` Flutter tests plus every registered Go leg passed, exit 0; retained log `/tmp/track2_groups_rerun.log`.
- `core-host-all`: `310/310` discovered files and `2485` tests passed with `0` skipped, exit 0; retained log `/tmp/track2_core_host_all_rerun.log`.
- `feature-host-all`: user-provided external all-green run (2026-07-12; no local count/log).
- Wave-level `host-all` (2026-07-13): all `1151/1151` commands passed across
  `1143` Flutter files (`11502` tests passed, `1` skipped) and `8/8` Go legs;
  former failures `#407` and `#616` passed in full-suite context. Retained log:
  `/tmp/track2_wave2_host_all_rerun2.log`.

Closure checklist:

- [x] Decision ledger resolved with exact executable semantics.
- [x] Production flow and actual nine-file causal manifest implemented.
- [x] Focused 30/30 batch aggregate green.
- [x] Plans 236/237/240/241/249 preservation sentinels green.
- [x] No migration, wire, Go/libp2p or durable-restart scope was introduced.
- [x] New suites are registered in `GROUP_TESTS` in exact order and auto-discovered by the core/feature host families.
- [x] Shared entry-bound and Plan 250 authorization mutations re-RED, then restore to focused GREEN.
- [x] Scoped analyzer is clean.
- [x] Curated `groups` gate passes on the integrated tree.
- [x] `core-host-all` passes on the integrated tree.
- [x] `feature-host-all` passes on the integrated tree.
- [x] The single Wave-2 `host-all` closure sweep passes on the integrated tree.

All required per-plan named gates are green and Plan 250 is accepted/closed.
Full `host-all` was not a Plan-250 closure obligation; the later single
Wave-2 closure sweep is now complete and does not change this plan's scope.

## Execution Progress

| Date | Phase | Result | Next |
|---|---|---|---|
| 2026-07-12 | Contract resolution | Output, ordering, captions, cap, provenance, authorization, retry and restart rows accepted. | Implement causal foundation and route. |
| 2026-07-12 | Implementation and focused verification | Production flow complete; shared entry-bound and Plan 250 authorization mutations re-RED; exact restoration aggregate 30/30; dependency preservation green; scoped analysis clean. | Run integrated named gates. |
| 2026-07-12 | Integrated closure | `groups` 2171/2171 plus Go, `core-host-all` 310/310 files and 2485 tests with 0 skipped, and the user-provided external all-green `feature-host-all` run passed. | Accepted/closed; wave-level `host-all` was pending at this checkpoint. |
| 2026-07-13 | Wave-2 final closure | Wave-level `host-all` passed `1151/1151` commands: `1143` Flutter files, `11502` tests passed, `1` skipped, and `8/8` Go legs; `#407` and `#616` passed in context. | Final wave evidence recorded; Plan 250 remains accepted/closed. |
