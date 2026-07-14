# 251 - Announcement Shared-Media Batch Forwarding

Status: accepted
Type: New Feature
Wave: Track 2 / Wave 2 / Forwarding
Dependencies: accepted Plans 240 and 241, the shared Plan 249 forwarding foundation, and Plan 250 shared batch infrastructure
Closure tier: host composition over already-proven ordinary direct/group/announcement-safe delivery

## Outcome

Announcement shared-media libraries now expose Batch Forward for an eligible selection of 2..10 incoming verified image/video attachments. Every selected attachment becomes one ordinary forwarded destination message per target with its own editable caption. The route can target active contacts, writable discussion groups and other active announcement groups where the local user is currently an administrator. It never publishes back into the source announcement.

Single-item Forward remains the Plan 240 route, including reader access to incoming media while announcement compose stays read-only. Plan 241 Save, OS Share, Bookmark, Delete and Evict actions are preserved.

## Accepted Decision Ledger

Accepted on 2026-07-12 for Track 2 / Wave 2.

| Decision | Accepted contract | Executable oracle |
|---|---|---|
| Output unit | One ordinary destination message per selected attachment per target; no batch album. | Shared draft/delivery tests and provenance command log. |
| Ordering | Parent timestamp DESC, message ID DESC, attachment ID DESC. | Shared `GBF-02` draft test with announcement-typed items. |
| Captions | Preserve an independent parent caption for each item; each may be edited or cleared before send. | Announcement draft and real route tests. |
| Selection bound | Reusable foundation 1..10; visible batch route 2..10. Enforce current per-MIME caps and at most 500 MiB aggregate current bytes before picker/delivery. No new duration cap. | Shared preflight plus announcement presentation test. |
| Source policy | Exact ordinary incoming, verified, group-owned image/video from one active announcement. Re-resolve current row/file/hash; no redownload, caller path trust, protected/private leakage or source mutation. | Source gate, presentation and provenance suites. |
| Target policy | Active contacts, active writable chat groups and other active announcement groups where both current group role and own member role are admin. Exclude source announcement and QA; a discussion source never widens to announcement targets. | Routed picker target-policy and authorization suites. |
| Send-time authorization | Strict final contact reload. Group display and final dispatch require a coherent group/member/key-generation snapshot; missing capability, membership/role drift, key drift or inactive state fails closed before upload. | Target-policy, `GBF-04` and real SQL helper tests. |
| Provenance/idempotency | Opaque random base per source item, domain-separated by target kind and target; stable for retry and anonymous with respect to all source IDs. | Announcement provenance suite plus shared delivery suite. |
| Failure/result model | Settle every source-item × target cell as sent, queued or failed. Sent/queued cells remain immutable; retry only failed cells for the same route and identity. | Shared delivery suite and real route completion assertion. |
| Restart behavior | Route-local only; no durable resume/cancel, persistence or migration. | Delivery coordinator state model. |
| Source boundary | Destination commands only. Never publish or inbox-store a message whose target is the source announcement; preserve source message/attachment/file bytes exactly. | Announcement provenance/source-boundary assertions. |
| Transport/crypto | Reuse the ordinary Plan 232/236/240 send paths and existing Forwarded marker. Fresh destination IDs, upload/encryption/access are owned by those paths. | Dependency sentinels and shared delivery tests. |

All formerly unresolved rows are accepted. There is no outstanding grouping, caption, cap, atomicity, retry, provenance or announcement-destination product decision.

## Scope And Invariants

In scope:

- A 2..10-item Batch Forward action from one active announcement shared-media library.
- Incoming verified image/video only, with current source revalidation.
- Independent caption editing and one ordinary output per item/target.
- Active contacts, writable chat groups and authorized non-source announcement groups.
- Truthful partial results and failed-cell retry within the route.

Preserved:

- Plan 240 one-item Forward, reader-forward capability, caption behavior, no-source-publish rule and target policy.
- Plan 241 multi-select library identities and every non-forward action.
- Plan 232/236 legacy-safe Forwarded markers, per-target encryption/access, send authorization and retry identity.
- Source announcement message, attachment, file, bookmark and caption state.
- Announcement compose/write restrictions and native topic authorization.

Explicitly absent:

- Album grouping, caption concatenation or attachment-level wire caption metadata.
- Source sender/group/message/attachment identity in output payloads, operation keys or recipient-visible logs.
- Source-announcement publish/inbox commands or source state mutation.
- Cross-target crypto/blob/access reuse.
- A new message field, codec, topic, pubsub/fanout/key rule, database migration, durable job or Go/libp2p production edit.

## Implementation Manifest

Shared batch production:

- `lib/features/groups/application/group_media_batch_forward.dart`
- `lib/features/share/application/group_media_batch_forward_delivery_coordinator.dart`
- `lib/features/share/presentation/screens/group_media_batch_forward_picker_screen.dart`
- `lib/features/share/presentation/screens/group_media_batch_forward_picker_wired.dart`
- `lib/features/share/presentation/navigation/group_media_batch_forward_picker_route.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`

Announcement entry/composition and authorization:

- `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/core/database/helpers/group_forward_authorization_db_helpers.dart`
- `lib/main.dart`

Supporting compatibility/test surfaces:

- `lib/features/groups/application/group_shared_media_library_controller.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/share/application/announcement_forward_test_harness.dart`

The picker prehydrates the current key and then uses the coherent snapshot as its final awaited group eligibility authority. The delivery coordinator repeats the current authorization at dispatch. Announcement targets require both the group-level admin role and the exact local roster member's admin role; split-role or absent-member states fail closed. The source announcement is excluded structurally and again at dispatch.

## Actual Test Contract

The nine files registered in `GROUP_TESTS`, in exact order, are:

1. `test/features/groups/application/group_media_batch_forward_draft_test.dart`
2. `test/features/groups/application/group_media_batch_forward_preflight_test.dart`
3. `test/features/groups/application/group_media_batch_forward_authorization_test.dart`
4. `test/core/database/helpers/group_forward_authorization_db_helpers_test.dart`
5. `test/features/groups/application/group_media_batch_forward_delivery_test.dart`
6. `test/features/groups/presentation/group_shared_media_batch_forward_test.dart`
7. `test/features/groups/presentation/announcement_media_batch_forward_test.dart`
8. `test/features/share/presentation/announcement_batch_forward_target_policy_test.dart`
9. `test/features/share/application/announcement_batch_forward_provenance_test.dart`

Rows 1..5 are the shared Plan 250/251 foundation, row 6 is Plan 250, and rows 7..9 are Plan 251.

The core/feature host families discover and sort matching tests automatically; they do not promise the manual `GROUP_TESTS` order.

Plan 251 causal coverage includes:

- `ABF-02 announcement draft stays source typed and caption independent`.
- Announcement Batch Forward is bounded while single-item and Plan 241 actions remain unchanged.
- `routed batch picker target set is exact`.
- `discussion batch never widens to announcement targets`.
- `real route sends edited draft to selected target through coordinator once`.
- `picker fails closed without coherent capability or exact key generation`.
- Target/unit keys stay stable and domain-separated without carrying source identity.
- Initial send and retry leave the source `GroupMessage`, group-owned `MediaAttachment` and source file bytes unchanged.
- Exactly one destination publish occurs for the successful fixture and zero publish/inbox-store commands target the source announcement.

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

Result: exit 0, 30/30 tests passed. The final target-policy file is 4/4 and the provenance file is 2/2 within that aggregate.

Controlled mutation re-RED evidence captured on 2026-07-12:

| Mutation | Command/oracle | RED result | Restoration |
|---|---|---|---|
| Shared route minimum `2 -> 3` | Run the draft, discussion presentation and announcement presentation files together. | Exit 1. The exact route-min assertion failed and both Plan 250/251 two-item Batch Forward entry tests failed because the action disappeared. | Restore `2`; exact nine-file aggregate returned 30/30. |
| Plan 251 authorization: temporarily treat an announcement roster `MemberRole.reader` as writable while the group-level role remains admin. | `flutter test --no-pub test/features/groups/application/group_media_batch_forward_authorization_test.dart --plain-name 'GBF-04 announcement own-member admin to reader prevents upload' --reporter expanded` | Exit 1. The mutation crossed the split-role denial boundary, performed upload/send work and changed the expected failure count from 1 to 0. | Restore exact announcement-admin roster policy; exact test returned 1/1 and the final nine-file aggregate returned 30/30. |

The mutations were applied and reversed with exact patches; neither mutation remains in the production diff.

Preservation evidence completed before integrated gates:

| Dependency | Evidence result |
|---|---|
| Plan 232/236 | Existing direct/group markers and group-forward flow preserved; Plan 236 policy/intent/flow 9/9, `GMF-` coordinator 3/3, `GMF-08` 1/1 and announcement non-admin send denial 1/1. |
| Plan 237 | `GML-05` 1/1, `GML-06F` 1/1, transport boundary 1/1, batch actions 2/2 and current `GML-10 production nested route consumes bounded anchor result` 1/1. |
| Plan 240 | Canonical eight-file family 10/10, wired picker 16/16 and native announcement writer lifecycle regex passed. |
| Plan 241 | `AML-07` + `AML-11` 2/2 and native announcement writer/validator regex passed. |
| Plan 249 | Canonical five-file foundation/picker/transport set 30/30 and received-media transport baseline 1/1. |

Scoped analysis of the forwarding coordinator, atomic authorization helper/repository and routed picker completed with no issues. Final hygiene and affected-graph evidence are recorded at handoff.

## Device And Boundary Decision

Plan 251 only composes ordinary one-item sends whose direct/group payload, crypto, device and announcement-source boundary were already proven by Plans 232, 236 and 240. It introduces no new schema, wire field, codec, transport or crypto behavior. The new claim is host orchestration, so no additional simulator/device run is required and unavailable hardware is not a closure condition. No simulator-only claim is made.

## Final Acceptance Gates

Per project cadence, full `host-all` is not a per-plan requirement. Final integrated closure requires the affected curated group lane and the justified core/feature sweeps because the shared wave changes a core database helper and feature orchestration:

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

- [x] Decision ledger resolved with exact announcement semantics.
- [x] Actual route, target policy, source boundary and shared batch infrastructure implemented.
- [x] Exact nine-file focused aggregate 30/30.
- [x] Real routed picker invokes the coordinator once with the edited draft and exact selected target.
- [x] Source state/bytes and no-source-publish boundary proven through initial attempt and retry.
- [x] Plans 232/236/237/240/241/249 preservation sentinels green.
- [x] No migration, wire, Go/libp2p or durable-restart scope introduced.
- [x] New suites registered in `GROUP_TESTS` in exact order and auto-discovered by the core/feature host families.
- [x] Shared entry-bound and Plan 251 split-role authorization mutations re-RED, then restore to focused GREEN.
- [x] Scoped analyzer is clean.
- [x] Curated `groups` gate passes on the integrated tree.
- [x] `core-host-all` passes on the integrated tree.
- [x] `feature-host-all` passes on the integrated tree.
- [x] The single Wave-2 `host-all` closure sweep passes on the integrated tree.

All required per-plan named gates are green and Plan 251 is accepted/closed.
Full `host-all` was not a Plan-251 closure obligation; the later single
Wave-2 closure sweep is now complete and does not change this plan's scope.

## Execution Progress

| Date | Phase | Result | Next |
|---|---|---|---|
| 2026-07-12 | Contract resolution | Grouping, caption, order/cap, item atomicity, retry, provenance and announcement target rows accepted. | Implement shared draft/delivery and announcement route. |
| 2026-07-12 | Implementation and focused verification | Production flow complete; shared entry-bound and Plan 251 split-role authorization mutations re-RED; exact restoration aggregate 30/30; route/source boundary and dependency preservation green; scoped analysis clean. | Run integrated named gates. |
| 2026-07-12 | Integrated closure | `groups` 2171/2171 plus Go, `core-host-all` 310/310 files and 2485 tests with 0 skipped, and the user-provided external all-green `feature-host-all` run passed. | Accepted/closed; wave-level `host-all` was pending at this checkpoint. |
| 2026-07-13 | Wave-2 final closure | Wave-level `host-all` passed `1151/1151` commands: `1143` Flutter files, `11502` tests passed, `1` skipped, and `8/8` Go legs; `#407` and `#616` passed in context. | Final wave evidence recorded; Plan 251 remains accepted/closed. |
