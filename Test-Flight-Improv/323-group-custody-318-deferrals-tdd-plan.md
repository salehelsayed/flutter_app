# 323 - Group Custody: the three plan-318 deferrals

Status: **PARTIALLY IMPLEMENTED 2026-08-02** — committed `6d52d2d3b`. Deferral A closed WON'T-BUILD (verdict only); deferral B shipped as B2 (subset containment + empty-set denial); deferral C classified and returned to design (see plan 326).
Type: Bug
Spec: free-text intent — the three deferrals recorded at `318-…:222`; no formal spec
Classification: implementation-ready (deferrals B and C) + one source-proven WON'T-BUILD verdict (deferral A)
Closure tier: host (Dart feature tier). No relay change, no deploy, no migration.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | `backend_redis.go`, `backend_memory.go`, `inbox.go`, `reaction_push.go`, `send_group_message_use_case.dart`, `group_offline_replay_envelope.dart` | Deferral A's enabling premise is false — verdict, not a build | Record WON'T-BUILD with blockers |
| 2026-08-02 | Evidence Collector | `retry_failed_group_inbox_stores_use_case.dart`, `group_private_media_retry_qualification_test.dart` | Deferral B's filed cause is a symptom; the real cause is a send-vs-retry asymmetry | Plan both the asymmetry fix and the relaxation |
| 2026-08-02 | Evidence Collector | `group_message_listener_system_transition_processor.dart`, `group_info_wired.dart`, `apply_on_join_group_config_resync.dart` | Deferral C is a real custody-loss defect; the implied fix is a no-op | Design the prune fix from scratch |

## Problem And Evidence

### Deferral A — historical-custody remediation → **WON'T-BUILD (source-proven infeasible)**
Plan 318 deferred this as *"enabled by the byte-identical re-store merge (`backend_redis.go:633-637`) — the durable `inboxRetryPayload` holds the signed envelope"*. That premise is false, and four further blockers stand behind it.

1. **The payload is NULL on exactly the target rows.** Historical victims are messages whose inbox store *succeeded* with a too-narrow recipient set. Every successful-store path nulls both the envelope and the retry payload: `send_group_message_use_case.dart:2113`, `:2155` (`inboxRetryPayload: inboxOk ? null : …`), `:2196`, `:2257`, `:2316`; `dbCompleteGroupInboxStoreRetry` sets `inbox_retry_payload = NULL` (`group_messages_db_helpers.dart:1379-1386`). `wire_envelope` is not a substitute — it holds plaintext publish params (`send_group_message_use_case.dart:1512`), never the replay envelope (`:1567-1571`).
2. **Envelopes are not reproducible.** `callGroupEncrypt` mints a fresh nonce per call (`group_offline_replay_envelope.dart:126-155`), so a rebuilt envelope differs by bytes and the relay returns `conflicting group inbox messageId` rather than merging (`backend_redis.go:633-635`, `backend_memory.go:370-372`).
3. **Widening the relay ACL would not deliver anyway.** The envelope carries a signed `recipientPeerIds` + `recipientSetHash`, and the receiver fail-closes on it — `throw GroupOfflineReplaySignatureException('recipient_not_entitled')` (`group_offline_replay_envelope.dart:576-581`), reached from `drain_…:931`, `:958`, `:1710`. A newly-entitled peer would retrieve and throw.
4. **Resurrection is unguarded.** The dedupe scan runs over TTL-filtered entries, so a re-store of an expired message allocates a *new* record with `Timestamp: time.Now()` (`backend_redis.go:663`, `backend_memory.go:395`) — a >7-day-old message reappearing in every member's drain with a fresh 7-day life, evicting the oldest rows against the 500 cap. No group ack/delete verb exists to undo it (`inbox.go:2356-2410`).
5. **Only the original sender device can act** (`from != remotePeer` → `not authorized`, `inbox.go:2367-2369`), so remediation is per-sender-device and cannot be orchestrated centrally.

**Disposition:** closed WON'T-BUILD. Any future attempt must first solve envelope retention at send time (a new durable cost that still cannot reach *historical* rows) and a relay "merge-only, never create" mode. Recorded so the premise is not re-derived a third time.

### Deferral B — private-media retry recipient match
- **Behavior to improve:** private-media rows that failed their inbox store are permanently denied retry.
- **Confirmed root cause (corrected — the filed framing was a symptom):** the retry lane calls `qualifyCurrentPrivateGroupMediaSend` **without** `inviteDeliveryAttemptRepo` (`retry_failed_group_inbox_stores_use_case.dart:237-242`; zero occurrences of the symbol in the file), while the send path passes it (`send_group_message_use_case.dart:916`, `:1082`, and production wiring at `production_application_bootstrap.dart:4509,4531,4552,4582`). With no repo, `inviteStatuses` is `const {}` (`send_group_message_use_case.dart:104-106`) and **no invite-status exclusion applies at retry time**, so `current` is systematically wider than the set the send computed. `_matchesCurrentPrivateRetryRecipients` demands exact-set equality (`:41-56`), so those rows are denied **on all builds, indefinitely** — not merely the pre-upgrade population plan 318 described.
- **Second, narrower cause:** genuinely pre-318 rows are also `persisted ⊊ current` because 318 widened `_loadGroupSendMembership` (`send_group_message_use_case.dart:111-120`). The asymmetry fix does not rescue these; the relaxation does.
- **Existing coverage:** `group_private_media_retry_qualification_test.dart:357` (GPL-03C) is the sole pin, and its denial arm is `persisted ⊋ current` — so it is satisfied by exact-match, by subset, **and by the inverted predicate**. Zero test pressure on direction.
- **Refuted (do NOT re-introduce):** *"318 also narrowed via `GroupInviteDeliveryStatus.unknown`"* — `unknown` is structurally unpersistable (`group_invite_delivery_attempt.dart:115-118` throws `StateError`). Plan 318's U1 rationale rests on the same false citation.
- **Safety:** the retry re-stores the **frozen** payload (`:257-260`), never the current set (`group_offline_replay_envelope.dart:455-471`, pinned by TC-318-14). So relaxing the matcher can only decide store-vs-no-store; it can never widen an ACL.

### Deferral C / U3 — config-resync roster overwrite
- **Behavior to improve:** a group member is silently deleted from other members' rosters, losing relay custody for every subsequent message.
- **Confirmed root cause:** `_applyAuthoritativeGroupConfigSnapshot` hard-deletes every local member absent from the snapshot (`group_message_listener_system_transition_processor.dart:3703-3708` → `removeMember` → `dbDeleteGroupMember`). The parameter defaults to `true` (`:3607`), and three of six call sites take the default: `:2389` `_handleMemberBanned`, `:2627` `_handleMemberRoleUpdated`, `:2706` `_handleGroupMetadataUpdated`.
- **Trigger is routine, not an edge case:** a metadata edit builds `groupConfig` from the acting admin's **own live roster** with a fresh timestamp (`group_info_wired.dart:1932-1938`). So a current, correctly-signed, watermark-passing edit by an admin who is merely missing a member prunes that member from every receiver. `isGroupConfigStateHashValid` only checks self-consistency (`group_config_payload.dart:421-433`) and cannot detect an omission.
- **Why it matters now:** plan 318 made the local roster the *sole* custody authority — `_loadGroupSendMembership` reads `getMembers` and derives `recipientPeerIds` (`send_group_message_use_case.dart:96-125`). A pruned member is simply absent, so a roster-prune bug is now a custody-loss bug.
- **Refuted (do NOT re-introduce):** *"forward `eventAt:`/`msgRepo:` to the three prune sites"* — a **no-op**. `snapshotPeerIds.add(peerId)` runs at `:3654`, six lines **before** the recency guard at `:3660-3671`; the guard's `continue` skips only `saveMember` (`:3686`), leaving the peer already in `snapshotPeerIds` and the prune loop unaffected. That guard governs stale re-add, not roster loss.
- **Refuted:** *"gate the prune on `appliesMetadataFields`"* — would suppress the prune at `:1949` and `:2389` on equal-version events, so removed and **banned** members would retain roster presence and relay entitlement. It is also a clock category error (metadata watermark vs `membershipVersion.eventAt`).
- **Existing coverage:** none. `grep -rn pruneOmittedMembers test/` returns zero hits.
- **Affected files:** `group_message_listener_system_transition_processor.dart`; `retry_failed_group_inbox_stores_use_case.dart`; `group_private_media_retry_qualification_test.dart`; `group_message_listener_test.dart`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `a5d1d9254ab1fe95`, `stale:scripts/test/probe_relay_live_digest_321.sh` (script-only drift).
- Query / profile: `python3 graphify-arch/tdd_context.py query "…" --profile tdd --budget 700` (grounding for D4/318 shared the same pass).
- Anchors: `send_group_message_use_case.dart`, `retry_failed_group_inbox_stores_use_case.dart`, `group_message_listener_system_transition_processor.dart`, `group_config_payload.dart`.
- Surfaced proof/gate files: `group_private_media_retry_qualification_test.dart`, `group_message_listener_test.dart`, `group_admin_metadata_convergence_test.dart`.
- Graph gaps that required raw source search: the six-site `pruneOmittedMembers` census and the Go relay merge predicate.
- Reuse rule: anchors are starting points; every conclusion is re-verified in current source.

## Scope Contract And Guard

In scope:
- **B1** Pass `inviteDeliveryAttemptRepo` into the retry lane so `persisted` and `current` are computed like-for-like.
- **B2** Relax `_matchesCurrentPrivateRetryRecipients` from exact-set equality to **subset containment** (`persisted ⊆ current`, after the existing ±`senderPeerId` normalization), with an **explicit empty-`persisted` denial**.
- **C1** Stop the wholesale roster prune at the three non-membership call sites, and flip the parameter default to safe.

Must preserve:
- Frozen-payload replay semantics (retry never re-stores the current set) → TC-318-14 remains green; TC-323-04 sentinel.
- A departed/no-longer-qualified peer still denies retry → TC-323-03.
- `member_removed` dissolve pruning still works (`:1949`, `pruneOmittedMembers: snapshotHasNoActiveMembers`) → TC-323-07 sentinel.
- Ban and removal still delete their targets — both do so **explicitly and independently** of the prune (`:2385`, `:1936`) → TC-323-08 sentinel.
- Relay untouched → no Go file changes in this plan.

Hard `Do not`:
- Do not build deferral A in any form.
- Do not widen `RecipientPeerIds` semantics, add relay-side backfill, or change the relay.
- Do not change `qualifyCurrentPrivateGroupMediaSend`'s own predicate — B1 supplies an argument it already accepts (`send_group_message_use_case.dart:865`).
- Do not gate the prune on `appliesMetadataFields` (refuted above).

Deferred / accepted difference:
- **Relay group-reaction ACL fail-open (NEW, found during this plan's grounding — not a 318 deferral).** `reaction_push.go:192-196` returns `valid=false` when the request recipient set differs from the signed set; `inbox.go:1608` then **skips** the signed-set override, so the client-supplied wider set is what reaches `s.store` (`:1616`) and is unioned by `mergePeerIds`. The check meant to reject a mismatch instead disables the binding that constrains it. Requires an authenticated sender acting on its own envelope; the client-side `recipient_not_entitled` check is the only remaining barrier and is skipped when `expectedRecipientPeerId` is null (`group_offline_replay_envelope.dart:577`). Fix shape: reject the store when `recognizedReaction && !validReaction` rather than falling through. **Owner: needs its own plan — it is a relay change requiring a deploy, outside this plan's host-only closure.**
- **B2's denial arm may be over-broad.** `current` is narrowed by `membershipCutoff` (`send_group_message_use_case.dart:906-919`) and `hasDeliverableGroupMemberIdentity` (`group_config_payload.dart:153-161`), so "absent from current" does not always mean "departed". Denying those remains the status quo, not a regression — recorded, not fixed here.

Dependencies:
- Plan 322 touches different files; no ordering constraint.

## Test Contract
Zero empty cells.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-323-01 | Retry qualification uses the same invite-status exclusion the send used | `group_private_media_retry_qualification_test.dart::318B retry qualification applies invite-status exclusion` | unit / fakes + `GroupInviteDeliveryAttemptRepository` seeded with a `needsResend` peer | causal RED (HEAD: `current` includes the excluded peer ⇒ mismatch ⇒ retry returns 0) → retry proceeds, bridge `group:inboxStore` called once | drop `inviteDeliveryAttemptRepo:` at the retry call → TC-323-01 red | `flutter test test/features/groups/application/group_private_media_retry_qualification_test.dart`; AUTO (`GROUP_TESTS` `:648`) |
| TC-323-02 | A persisted set that is a strict SUBSET of current is allowed | `group_private_media_retry_qualification_test.dart::318B subset persisted recipients are retry-eligible` | unit / fakes; persisted `['peer-other']`, current `['peer-other','peer-incumbent']` | causal RED (exact equality denies) → retry stores the FROZEN `['peer-other']` set with `preserveRecipientPeerIds: true` | restore `sameGroupPrivateMediaRecipientPeerIds` equality → TC-323-02 red | same as TC-323-01 |
| TC-323-03 | A persisted peer absent from current still DENIES (direction pin) | `group_private_media_retry_qualification_test.dart::318B persisted peer missing from current denies retry` | unit / fakes; persisted `['peer-other','peer-gone']`, current `['peer-other']` | GREEN sentinel (denied today) → still denied, zero bridge calls | invert the predicate to `current ⊆ persisted` → TC-323-03 red | same as TC-323-01 |
| TC-323-04 | An EMPTY persisted set never becomes retry-eligible | `group_private_media_retry_qualification_test.dart::318B empty persisted recipient set denies retry` | unit / fakes; persisted `[]`, current `['peer-other']` | GREEN sentinel (exact-match denies today) → still denied — `[] ⊆ anything` must not become a tautology | remove the empty-set guard → TC-323-04 red | same as TC-323-01 |
| TC-323-05 | A metadata-only update never prunes the roster | `group_message_listener_test.dart::318C group_metadata_updated does not prune members absent from the snapshot` | unit / fakes; local roster has `peer-incumbent`, admin's snapshot omits it | causal RED (HEAD hard-deletes `peer-incumbent`) → member still present after the event; metadata fields still applied | restore `pruneOmittedMembers` default `true` at `:3607` → TC-323-05 red | `flutter test test/features/groups/application/group_message_listener_test.dart`; AUTO (`GROUP_TESTS` `:566`) |
| TC-323-06 | Role-update and ban events never prune the roster | `group_message_listener_test.dart::318C role update and ban do not prune unrelated members` | unit / fakes; snapshot omits a third member | causal RED (both hard-delete it) → third member retained on both paths | pass `pruneOmittedMembers: true` at `:2389` or `:2627` → TC-323-06 red | same as TC-323-05 |
| TC-323-07 | The dissolve prune still works | `group_message_listener_test.dart::318C member_removed with an empty snapshot still clears the roster` | unit / fakes; `members: []` | GREEN sentinel → roster cleared as today | force `pruneOmittedMembers: false` at `:1949` → TC-323-07 red | same as TC-323-05 |
| TC-323-08 | Ban and removal still delete their own targets | `group_message_listener_test.dart::(existing ban/removal tests)` | unit / fakes | GREEN sentinel → target removed on both paths | delete `removeMember` at `:2385` → the existing ban test reds | same as TC-323-05 |
| TC-323-09 | A pruned member's custody loss is the thing being prevented (relationship pin) | `group_message_listener_test.dart::318C member surviving a metadata update remains a send recipient` | unit / fakes; run `_loadGroupSendMembership` after the metadata event | causal RED (HEAD: pruned ⇒ absent from `recipientPeerIds`) → peer present in the computed recipient set | revert the prune fix → TC-323-09 red | same as TC-323-05 |

### Test Notes
- TC-323-02/03/04 exist as a set because no current test distinguishes subset from the inverted predicate; `sameGroupPrivateMediaRecipientPeerIds` is symmetric (`send_group_message_use_case.dart:157-176`), so an asymmetric `containsAll` invites an argument-order slip. All three directions must be pinned.
- TC-323-09 asserts the *relationship* (roster survival → recipient-set membership) on one node rather than two independent presence checks, so it cannot pass for the wrong reason.
- TC-323-05 must also assert the metadata fields still applied, or a fix that skips the whole snapshot would pass.

## Implementation Steps
1. Snapshot `git status --short`. Add TC-323-01..09 first; confirm 01/02/05/06/09 red for the documented reasons, and 03/04/07/08 green.
2. **B1** — add an optional `GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo` to `retryFailedGroupInboxStores` (`:88-95`, matching the existing optional-repo pattern), thread it to the private arm (`:206-212`) and pass it at `:237-242`. Wire it at the production construction sites. Stop-if: the repo is not reachable at a retrier construction site without a new singleton → stop and replan rather than constructing a second instance.
3. **B2** — replace `_matchesCurrentPrivateRetryRecipients` (`:41-56`) with subset containment against both existing arms (bare `currentRemoteRecipients` and `currentRemoteRecipients + senderPeerId`), returning `false` when `persisted.isEmpty`. Keep the fail-closed null/duplicate handling in `_privateRetryRecipientPeerIds` (`:25-38`) unchanged.
4. **C1** — pass `pruneOmittedMembers: false` at `:2389`, `:2627`, `:2706`; flip the declaration default at `:3607` from `true` to `false` so future call sites are safe-by-default; leave `:1949`'s explicit conditional and `:1528`/`:1690`'s explicit `false` untouched.
5. **A** — no code. Record the WON'T-BUILD verdict in `00-INDEX.md` and in plan 318's deferral line.
6. No harness registration needed — both test files are already in `GROUP_TESTS` (`:566`, `:648`). Grep-verify anyway.
7. Run focused GREEN → sentinels → graph-affected → the `groups` lane.

## Risks And Blind Spots
- Flipping a default from `true` to `false` is invisible to callers → guarded by TC-323-05/06/07 covering all three behaviors (must-not-prune, must-not-prune, must-still-prune).
- Lifecycle / derived-state durability: roster rows are durable; the change only stops a delete → TC-323-09.
- Sibling-surface consistency: all six `_applyAuthoritativeGroupConfigSnapshot` call sites enumerated and classified above → TC-323-05/06/07.
- Destructive-action side effects: this plan *removes* a destructive action (hard `removeMember`) from three paths; the two paths that legitimately delete do so explicitly (`:2385`, `:1936`) → TC-323-08.
- Invariant re-verification under new transitions: retry eligibility widens, so the frozen-replay invariant is re-pinned → TC-323-04 + TC-318-14.
- Construction/call-site census: `grep -n 'pruneOmittedMembers'` → 5 hits (3 call sites + declaration + use); `grep -n '_applyAuthoritativeGroupConfigSnapshot'` → 6 call sites + declaration. Both re-derived at execution time, never inherited.
- Build-artifact provenance: N/A — no native artifact.
- Permission/ACL verb symmetry: the relay ACL finding is recorded as deferred with a named owner (above), not silently absorbed.

## Gate Cadence
- Per-plan closure: TC-323-01..09 focused + sentinels + the `groups` curated lane.
- Graph-affected first: after the production edits and BEFORE the lane, run `tdd_context.py affected …` and execute the named test files directly.
- Full `host-all` is **not** a per-plan gate. It is owned by the notification-reliability wave closure (this plan is the last of that wave) and again at final rollout.
- Shared tests outside the feature/core globs: N/A — none touched.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# Causal RED (before production edits) — must FAIL for the documented reasons
flutter test test/features/groups/application/group_private_media_retry_qualification_test.dart \
  --plain-name '318B retry qualification applies invite-status exclusion'
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name '318C group_metadata_updated does not prune members absent from the snapshot'

# Focused GREEN (after the fix) — exit 0, zero failures
flutter test test/features/groups/application/group_private_media_retry_qualification_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart

# Preservation sentinels — exit 0
flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case.dart 2>/dev/null || \
  flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected \
  lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart \
  lib/features/groups/application/group_message_listener_system_transition_processor.dart --budget 600

# Curated lane — exit 0
./scripts/run_test_gates.sh groups

# Registration is grep-verified, never run-verified
grep -c 'test/features/groups/application/group_private_media_retry_qualification_test.dart' scripts/run_test_gates.sh  # expect: 1
grep -c 'test/features/groups/application/group_message_listener_test.dart' scripts/run_test_gates.sh                   # expect: 1
./scripts/run_test_gates.sh completeness-check   # expect: PASS, 0 unmatched

# Hygiene
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: TC-323-01 (invite-status exclusion missing at retry), TC-323-02 (exact equality denies a subset), TC-323-05/06 (metadata/role/ban events hard-delete an omitted member), TC-323-09 (pruned member absent from the recipient set).
- GREEN sentinel: TC-323-03 (departed peer still denied), TC-323-04 (empty set still denied), TC-323-07 (dissolve prune intact), TC-323-08 (ban/removal still delete their targets).
- Pre-existing dirty tree / known failure: the three user-owned claude-docker files — never staged.
- Environment blocker (NOT a product blocker): none — host-only.
- Scope drift (BLOCKING): any relay/Go change; any attempt at deferral A; any change to `qualifyCurrentPrivateGroupMediaSend`'s predicate.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration is implemented AND verified.
- [ ] Conditional migration / device / relay proof passes when applicable — N/A.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected.
- [ ] Deferral A's WON'T-BUILD verdict is recorded in `00-INDEX.md` and plan 318.

## Handoff
- First causal RED command: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name '318C group_metadata_updated does not prune members absent from the snapshot'`.
- Preservation command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`.
- Manual registration: none — both test files already in `GROUP_TESTS`.
- Migration: none.
- Boundary closure: host-only. The relay ACL finding is deferred to its own plan and is the only item in this area needing a deploy.
- Unresolved evidence: none.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |

## Reviewer Findings (2026-08-02, `wf_d8df3c95-e44`)
**Verdict: not-ready · disposition: replan (deferral C) + apply-plan-fixes (deferral B).** Deferral A's WON'T-BUILD verdict is unaffected and stands.

### Deferral B — BLOCK: drop B1, ship B2 only
1. **B1 is redundant AND harmful.** Subset containment is monotone in `current`: omitting the repo only *widens* `current`, which still satisfies `persisted ⊆ current`. So B2 alone closes the population. B1 *narrows* `current` by re-applying invite-status exclusion, which can only turn allows into **denies** — reintroducing the exclusion→custody-loss failure mode plan 318 closed. **Delta: drop B1 and restate the root cause as "exact equality vs a widened qualification", not the send/retry asymmetry.**
2. **TC-323-01's mutation does not re-red** (`323-…` contract row 1): once B2 is in, dropping `inviteDeliveryAttemptRepo` leaves the row GREEN. The row is unpinnable except by asserting the regression as desired behavior. **Delta: delete TC-323-01 with B1.**
3. **Fixture gap (moot once B1 is dropped):** no shared fake for `GroupInviteDeliveryAttemptRepository` exists; the only in-memory impl is the private `_InMemoryInviteDeliveryAttemptRepository` (`send_group_message_use_case_test.dart:375-532`), not importable.
4. **PLAN-FIX — protect the shared helper.** `sameGroupPrivateMediaRecipientPeerIds` (`send_group_message_use_case.dart:157-177`) has **three** other production callers where equality is by design — `:996-1003` (media-ACL drift; relaxing it would widen a **blob ACL**), `:1728-1732`, `:2010-2013`. Add to Hard `Do not`: the relaxation is local to `_matchesCurrentPrivateRetryRecipients` (single caller, `:248-252`). TC-323-02's mutation wording must say "restore exact equality in the local matcher".
5. **PLAN-FIX — the sender arm is untested.** No fixture puts `senderPeerId` in `persisted`, so a rewrite keeping only `persisted ⊆ current` silently kills the `[...current, senderPeerId]` arm (`:52-55`) and denies every sender-inclusive legacy row with zero red. Add a sentinel: persisted `['peer-other','peer-self']`, current `['peer-other']` → allowed.
6. **PLAN-FIX — TC-323-04 misses the real change.** Today `persisted == [] && current == []` *matches* and proceeds to a bridge call the relay rejects (`backend_redis.go:602-604`). B2's empty denial removes that call — an improvement, but the row's fixture (`current == ['peer-other']`) does not cover it. Add a `current == []` arm.
7. **Recorded, not fixed:** B2 widens the row population that can resurrect a TTL-expired relay record (no age gate at `group_messages_db_helpers.dart:1174-1189`; re-create at `backend_redis.go:663`) — the same mechanism used to kill deferral A. Low severity (ordinary rows already do this unconditionally) but the reasoning is asymmetric and must say so.
8. **Gate nit:** the sentinel command references `test/.../retry_failed_group_inbox_stores_use_case.dart` (a lib filename); the real file is `…_test.dart`.

### Deferral C — BLOCK: the fix is unsafe as designed; needs redesign
Census CONFIRMED exactly as planned (6 sites, library-private, no other caller, no tear-offs). Ban/removal proven to delete their targets independently (`:2385`, `:1936`), so no removal depends on the prune. But:

1. **BLOCKER — removing the prune removes the ONLY downward roster-convergence path.** The complete set of roster-shrinking writes is processor `:1936`, `:2385`, `:3706` (the prune), `remove_group_member_use_case.dart:221` (local admin), and the self-removed shell; the on-join resync is metadata-only. A device that misses one `member_removed` (offline past inbox TTL, or upstream rejection) keeps the ghost **permanently** → the ghost stays in `recipientPeerIds` (`send_group_message_use_case.dart:110-124`) **and receives the rotated group key** (`rotate_and_distribute_group_key_use_case.dart:296`) — a forward-secrecy leak strictly worse than the custody loss being fixed.
2. **BLOCKER — the local roster is a signed-transition hash input, unexamined by the plan.** `buildGroupTransitionStateHash` reads `getMembers` (`signed_group_transition_audit.dart:439`), and `group_metadata_updated`, `member_role_updated`, `member_banned` are all audited (`:61,63,65`) — the exact three sites C1 changes. Two consequences: **(i)** the plan's severity claim is wrong — in the strict path a signer missing M computes a different hash and the receiver *rejects the event before the snapshot applies*, so prune-by-omission fires only in the relaxed path; **(ii)** the relaxed-path prune is today the only mechanism that re-converges a diverged roster and therefore the state hash, so retaining the ghost diverges it forever and every subsequent audited transition is rejected on that device — **a group freeze**, larger than the bug being fixed.
3. **BLOCKER — TC-323-09 is not constructible.** `_loadGroupSendMembership` is a file-private top-level function (`send_group_message_use_case.dart:97`) with no `part`/`@visibleForTesting` alias, and `group_message_listener_test.dart` never imports the send use case. Relocate to `send_group_message_recipient_eligibility_test.dart` (registered, `run_test_gates.sh:556`) driven through public `sendGroupMessage`.
4. **PLAN-FIX — the default flip has zero test pressure.** TC-323-05/06/07/08 are satisfied identically by (a) flipping the default only or (b) adding three explicit `false`s only. The Risks line claiming the flip is guarded is false.
5. **PLAN-FIX — TC-323-05/06 fidelity gap.** They are constructible only because unit fixtures compute the signed pre-hash from the same fake repo, producing a state (hash matches AND snapshot omits a local member) production reaches only via the relaxation. They prove the code change, not the production defect, and cannot see the freeze in (2).
6. **New divergence:** the three changed sites sync the **remote** config to the Go validator (`:2394`, `:2632`, `:2707`) while `:1528/:1690/:1949` sync the **local** snapshot (`:3828`). Post-fix the local roster and the Go topic-validator config permanently disagree.

**Disposition: deferral C returns to design.** Any successor must keep a downward convergence path (candidate: prune an omitted member only with local tombstone evidence — `getLatestSystemEventTimestampForTarget`, the API already used at `:3661-3666` — but note that a *missed* removal leaves no tombstone, so this does not by itself restore convergence) and must pin the post-change behavior of a subsequent audited transition.
