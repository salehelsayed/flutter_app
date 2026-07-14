# 249 - 1:1 Shared Media Batch Forwarding

Status: accepted
Type: New Feature
Spec: forward a bounded direct Shared Media selection as independent ordinary Plan-232 messages without collapsing captions, ordering, provenance, dedup, encryption, or retry truth
Classification: host-only ordinary-send composition
Closure tier: host-only; no schema, wire, relay, native, or device boundary changes

## Planning Progress

| Time | Role | Evidence / decision | Next action |
|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | Plans 232/233 and the existing one-source picker/delivery seam could not safely define multi-source grouping, caption, provenance, or retry behavior without explicit decisions. | Resolve D-249-01..07 before implementation. |
| 2026-07-11 | Decision / decomposition review | The accepted three-session breakdown resolves D-249-01..07 as direct-only composition over independent ordinary Plan-232 sends. It rejects album/grouped output, new schema/wire state, and group/announcement destinations. | Execute Session 01's hidden atomic draft/preflight foundation after Plan-234 Session 04. |
| 2026-07-11 | Dependency refresh | Plan-234 Session 04 is accepted and supplies `qualifyCurrentDirectMediaRow`, the exact-current direct owner/private/lifecycle/download/integrity/path boundary. | Reuse that boundary; do not fork its policy matrix. |

## Problem And Landed Evidence

- Plan 233 supplies stable bounded selection from the direct Shared Media library, but intentionally has no Batch Forward action.
- Plan 232 supplies one ordinary forwarded message from one current source, including an opaque explicit-action operation token, fresh per-destination identity/encryption, existing persistence, receiver dedup, and ordinary retry.
- Plan-234 Session 04 supplies the mandatory exact-current direct-row qualification boundary. Private, unsupported, consumed, expired, corrupt, hidden, deleted, unresolved, group-owned, incomplete, or otherwise ineligible media must never reach picker or delivery work.
- The accepted Plan-249 contract composes those landed owners. It does not add an album, batch envelope, receiver payload, durable batch table, group lane, or announcement lane.
- Three selected attachments and two active direct contacts therefore mean six ordinary direct messages in canonical source-major order, with independent captions and per-source operation tokens.

## Resolved Decision Ledger

| Decision | Accepted contract | Observable consequence |
|---|---|---|
| D-249-01 output shape | Emit one independent ordinary Plan-232 forward for every selected attachment and every chosen direct contact. Never coalesce attachments that share a parent; never create an album, grouped message, or batch receiver payload. | Three selected attachments to two contacts produce six ordinary outgoing messages in source-major stable order. Receiver compatibility is unchanged. |
| D-249-02 order and captions | Order selected sources by `(parent timestamp DESC, message id DESC, attachment id DESC)`, never tap order or path. Each attachment receives its parent caption as an independent initial value that may be preserved, edited, or cleared. | Same-parent siblings remain distinct and independently editable; source rows/text are never mutated. |
| D-249-03 provenance and compatibility | Mint one opaque random Plan-232 `ForwardProvenance.operationDedupKey` per selected attachment at draft creation. Reuse that token across contact fan-out and failed-only in-route retry. Every destination still receives fresh ordinary message/blob IDs, timestamp, recipient key/nonce, and ciphertext. | No source identity enters wire provenance, outer envelopes, UI, or diagnostics. No new encrypted-inner field or legacy fallback exists. |
| D-249-04 cap and source eligibility | Selection is `1..10`. Re-read exact direct parent/attachment rows and local bytes at build and immediately before dispatch. Only incoming, live-parent, ordinary, locally complete, integrity-verified visual sources pass. Any ineligible source aborts the whole source preflight before delivery and preserves selection. | Pending, failed, corrupt, evicted, missing, deleted, outgoing, unresolved/group, private/protected/unsupported/terminal, or stale-path rows cannot produce a partial send. |
| D-249-05 result, progress, and retry | Session 02 exposes a source-by-contact `sent`/`queued`/`failed` matrix. Retry only failed cells with the same item token; never resubmit sent or queued cells. Persisted ordinary rows remain owned by existing direct retry. | No batch retry table. Pre-message upload failures can retry only while the action remains open; reopening is a new explicit action. |
| D-249-06 destinations | Load, render, and dispatch active direct contacts only. Revalidate contacts before dispatch; invalid contacts become failed cells without changing valid contacts' ordinary-send contract. | Groups and announcements remain Plans 250/251 and cannot inherit Plan-249 state or copy. |
| D-249-07 UX, privacy, and diagnostics | Session 02 supplies bounded source preview, count, independent captions, direct-contact selection, progress, batch-level denial, localized accessible small-screen/RTL behavior, and truthful cell outcomes. Diagnostics expose redacted counts/phases/outcomes only. | No provenance, source sender/conversation identity, path, key, bytes, or caption history is displayed or logged. No mid-send cancellation promise is introduced. |

## Scope Contract And Guard

In scope across the three sessions:

- Session 01: refresh this source contract and land one hidden immutable direct-source draft/preflight builder for `1..10` exact `(messageId, attachmentId)` identities from one contact scope.
- Session 02: compose existing ordinary Plan-232 direct delivery per source/contact, add the direct-only picker/action/result matrix, failed-cell retry, l10n, accessibility, and wiring.
- Session 03: independently audit the complete feature, mutations, registrations, focused/curated gates, and synchronize stable closure documents.

Must preserve:

- Plan-232 one-source Forward reloads and qualifies the source before token/path/picker work and keeps its existing explicit-action semantics.
- Plan-233 paging, filters, bookmark, Save/Share/Delete, selection, viewers, and Go to Message remain unchanged.
- Plan-234 exact-current private/terminal/unsupported/corrupt denial remains the sole direct source qualification authority.
- Every destination gets ordinary recipient-scoped message/blob identity, key/nonce, ciphertext, persistence, and retry ownership. Source rows, bytes, keys, captions, and state are never mutated.

Hard `Do not`:

- Do not create an album, grouped direct message, shared caption, batch provenance token, provenance array, receiver codec branch, batch envelope, or legacy fallback.
- Do not add a schema/migration/version/registry/table/column or durable batch retry state. DB v100 belongs to Plan 234 and sequential v101 belongs to Plan 238.
- Do not load or dispatch group/announcement targets. Plans 250/251 own those lanes.
- Do not edit Go/libp2p/relay, native Android/iOS, platform transport, device harness, notification, or media-viewer boundaries.
- Do not expose Session-01's draft/preflight as a production Batch Forward action before Session 02 lands the complete route.
- Do not serialize or log source identity, sender/conversation identity, captions, paths, tokens, keys, nonces, or bytes.

## No-Migration And No-New-Wire Contract

- Plan 249 reserves no database version and changes neither the create/upgrade registry nor `currentIdentityDatabaseVersion`.
- It adds no batch table, message/attachment column, album field, provenance array, receiver codec branch, or transport-envelope field.
- Each output remains an existing ordinary Plan-232 direct send. In-route pre-message retry state is memory-only; once a row is persisted, existing message/attachment storage and retry use cases are authoritative.
- Device/relay proof is N/A because receiver and transport shapes are unchanged. A need for schema, new wire data, group publish, relay, or native work is a structural contradiction that stops execution for re-planning.

## Test Contract

| Case | Behavior / named proof | Owning session | Gate |
|---|---|---|---|
| TC-249-S01-01 | `rejects empty over-cap duplicate blank-identity and cross-scope selections before token mint` | 01 | new focused builder suite + both 1:1 arrays |
| TC-249-S01-02 | `qualifies every exact current direct visual source atomically` | 01 | new focused builder suite + Plan-234 boundary sentinels |
| TC-249-S01-03 | `sorts reverse tap order and same-parent siblings by the canonical library keyset` | 01 | new focused builder suite |
| TC-249-S01-04 | `creates independent captions and unique opaque tokens per attachment` | 01 | new focused builder suite |
| TC-249-S01-05 | `dispatch revalidation preserves edited captions and tokens while refreshing paths scope kind and order` | 01 | new focused builder suite |
| TC-249-S01-06 | `one source scope kind or eligibility race denies the whole revalidation with no ready subset` | 01 | new focused builder suite |
| TC-249-S01-07 | `draft and denial diagnostics expose no source payload or media secrets` | 01 | new focused builder suite |
| TC-249-S01-08 | `batch forward stays absent while only draft preflight is landed` | 01 | Shared Media widget sentinel |
| TC-249-S02-01 | Exact source-major/direct-contact ordinary delivery produces one message per source/contact with fresh recipient identity and encryption. | 02 | delivery coordinator causal suite + Plan-232 sentinels |
| TC-249-S02-02 | Picker loads only active direct contacts, revalidates sources/contacts before delivery, and exposes no group/announcement target. | 02 | picker/wiring/boundary suites |
| TC-249-S02-03 | Results remain a truthful source-by-contact sent/queued/failed matrix; failed-only retry preserves captions/tokens and never replays sent/queued cells. | 02 | delivery/retry causal suites |
| TC-249-S02-04 | Bounded preview, independent captions, progress, denial/results, l10n, semantics, small-screen, and RTL behavior remain truthful. | 02 | widget + l10n suites |
| TC-249-S03-01 | Independent counterexample/mutation audit covers ordering, sibling separation, caption isolation, token stability, eligibility bypass, preflight atomicity, direct-only destinations, and retry truth. | 03 | exact focused suites + curated `1to1` |
| TC-249-S03-02 | No schema/wire/Go/relay/group/announcement/native scope changed; all gate registrations and stable documents agree. | 03 | scope guard + inventory/completeness + closure audit |

All new direct/cross-feature Plan-249 suites must be registered in both `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` and classified in `Test-Flight-Improv/test-gate-definitions.md`.

## Ordered Session Ledger

| Session | Title | Depends on | Current status |
|---|---|---|---|
| 01 | Source-plan refresh and atomic direct-source draft/preflight | accepted Plan-234 Session 04 | accepted |
| 02 | Direct-contact cell delivery, picker UX, and failed-cell retry | Session 01 | accepted |
| 03 | Independent acceptance, mutations, registration, and closure synchronization | Sessions 01-02 | accepted |

Plan 249 is accepted and closed. Sessions 01-02 provide the complete
user-visible host flow; Session 03 independently accepted the combined feature
and synchronized its durable maintenance record without production changes.

## Implementation Steps

1. Session 01 authors the builder/action-absence REDs before production, lands the sole hidden application builder, registers its suite, and proves exact Plan-232/233/234 preservation.
2. Session 02 authors delivery/picker/retry REDs before production, wires the complete direct-only route, adds localized accessible UX, and proves ordinary-send identity/encryption/retry ownership.
3. Session 03 independently reviews the combined implementation, runs representative mutations and all proportional gates, then synchronizes source, breakdown, index, closure reference, and gate-definition evidence.

## Acceptance Gates

Per implementation session, run its exact focused causal suites, exact preservation sentinels, the curated `1to1` lane, host `1to1 --list`, completeness, scoped analyzer/formatter, `git diff --check`, and a baseline-safe scope guard. Run Graphify `affected` over attributable production files.

- Do not run `core-host-all`, `feature-host-all`, a performance family, or full `host-all` as a per-session gate.
- Full `host-all` runs once at the relevant Wave-1 batch boundary and once at final rollout/release closure.
- Device, SQLCipher, Go, relay, and native gates are N/A for Plan 249's unchanged ordinary-send boundary.

## Risks And Blind Spots

- Partial source eligibility could leak a private/stale selection into delivery; all-source exact-current preflight must finish before token minting/dispatch.
- Tap order, path order, or asynchronous callback order could drift from Shared Media's stable keyset; the immutable draft and revalidation both sort the persisted timestamp/message/attachment strings descending.
- A shared caption or operation token could collapse sibling meaning/dedup; every attachment owns independent immutable values.
- A race after preview could retain stale scope/kind/path/bytes; dispatch revalidation reloads every complete identity and denies the whole source batch.
- Flattened retry could replay sent/queued cells; Session 02 retains a source-by-contact matrix and existing persisted-send retry ownership.

## Execution Interpretation And Done Criteria

- [x] D-249-01..07 form one consistent direct-only ordinary-send contract.
- [x] Selection cap, canonical order, independent captions/tokens, all-source policy, result cells, compatibility, and privacy negatives are explicit.
- [x] No schema, wire, group/announcement, Go/relay, native, or device proof is required by the accepted design.
- [x] Session 01 hidden draft/preflight and registrations are accepted.
- [x] Session 02 direct delivery/picker/result/retry UX is accepted.
- [x] Session 03 independent mutations, aggregate Plan-249 gates, and closure synchronization are accepted.
- [x] Plans 232/233/234 and ordinary direct behavior remain preserved through Session 02.
- [x] Session-01/02 implementation evidence and Session-03 mutation, scope, analyzer, registration, completeness, QA, and closure evidence are recorded.

## Handoff

- Accepted Session 01: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-01-plan.md`.
- Session-01 production owner remains only `lib/features/conversation/application/build_direct_media_library_batch_forward.dart`.
- Accepted Session 02: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-02-plan.md`.
- Accepted Session 03: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-03-plan.md`.
- No Plan-249 session remains open.
- Overall verdict: `accepted`; Plan 249 is closed.

## Execution Progress

| Time | Phase | Evidence | Result / next |
|---|---|---|---|
| 2026-07-11 | source-contract refresh | Accepted Plan-249 three-session breakdown and closed Plan-234 Session 04 | D-249-01..07 are now executable as direct-only ordinary-send composition. Session 01 owns the hidden draft/preflight foundation; overall Plan 249 remains open. |
| 2026-07-11 | Session-01 acceptance | RED-first builder implementation; exact Plan-232/233/234 preservation; curated `1to1` `1,909/1,909`; host inventory `81`; completeness `1,167/1,167`; clean static/scope checks; fresh independent QA `ACCEPTED`, `fix_passes=0`; exactly one post-QA incremental Graphify refresh | Session 01 is accepted and closed. Session 02 is pending/runnable; Session 03 remains blocked on Session 02; overall Plan 249 remains `implementation-in-progress`. |
| 2026-07-11 | Session-02 acceptance | RED-first direct coordinator/strict seam/picker/action/wiring/l10n implementation; final primary `45/45`; Plan-234 `27/27`; Plan-232 `3/3`; Plan-233 `13/13`; generic picker `16/16`; l10n `3/3`; curated `1to1` `1,962/1,962`; host inventory `87`; completeness `1,174/1,174`; clean static/scope checks; fresh independent QA `ACCEPTED` with explicit bounded `fix_passes=3` exception; exactly one post-QA incremental Graphify refresh | Session 02 is accepted and closed. Session 03 is pending/runnable and owns combined mutations plus stable closure synchronization; overall Plan 249 remains `implementation-in-progress` / `still_open`. |
| 2026-07-11 | Session-03 final acceptance | Complete 42-file SHA/status audit; nine mutations repeated RED/inverse/GREEN with exact restoration; focused `7 + 45 + 1 + 19 + 3 + 12 + 16 + 3`; curated `1,962/1,962`; host inventory `87`; completeness `1,174/1,174`; analyzer exact parity `1,626`; independent QA `ACCEPTED`, `fix_passes=0`; no Graphify refresh | Session 03 and overall Plan 249 are accepted and closed. Stable index, closure reference, and gate-definition guidance now own maintenance. |

## Final Execution Result

`accepted`

Plan 249 forwards `1..10` exact eligible direct Shared Media visual sources to
active direct contacts as independent ordinary messages in canonical
source-major order. Captions and opaque operation tokens remain per source;
source/contact rows are current-revalidated; results remain truthful by cell;
and in-route retry touches failed cells only while persisted rows remain owned
by ordinary retry. No album, batch wire/schema, group/announcement target,
native/device, Go/relay, or private-media forwarding contract was added.

Final acceptance is backed by exact restored mutations, curated `1to1`
`1,962/1,962`, host inventory `87`, completeness `1,174/1,174`, full analyzer
parity, independent QA, and synchronized durable docs. Session 03 ran no
Graphify refresh because it changed no production/test architecture.

## Direct Revalidation Status

Status: `accepted` (revalidated 2026-07-12 after the Wave-1 shared
private-media viewer/download changes).

- Changed by this revalidation: this canonical status section only; no
  Plan-249 production or test file required a change.
- Tests added or updated: none. The five Plan-249 causal suites and the two
  exact Plan-234 current-direct/private qualification sentinels remain
  registered and non-vacuous.
- `flutter test test/features/conversation/application/build_direct_media_library_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/application/private_media_action_eligibility_test.dart test/features/conversation/application/direct_private_media_boundary_test.dart --reporter compact` -> PASS, `46/46`.
- `./scripts/run_test_gates.sh 1to1` -> PASS, `2,062/2,062`.
- `dart format --output=none --set-exit-if-changed <13 Plan-249 production/test files>`
  -> PASS, `13` files checked, `0` changed.
- `flutter analyze <13 Plan-249 production/test files>` -> PASS, no issues.
- Dedicated production scope guard -> PASS: no database/schema,
  group/announcement, Go/relay, platform-channel, or native dependency was
  introduced. Existing ordinary direct-send wire/persistence remains the sole
  delivery boundary, so SQLCipher, relay, native, and device proof remain N/A.
- Remaining blocker: none. The Wave-1 boundary `host-all` completed on
  2026-07-12: all `1,130` commands executed (`1,125` initial passes, including
  all eight Go legs), followed by an exact clean `53/53` rerun of the five
  remediated files.
