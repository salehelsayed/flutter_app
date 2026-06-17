# Review-Batch-2 Gap Closure — 04 / 09 / 10 / 11 (TDD plan)

**Date:** 2026-06-17
**Scope:** Implementation/test audit of six TDD plans, with every claimed gap adversarially
verified (production-code lens + tests/git-history lens) before being recorded here.

Plans audited:
- `04-P0-SI5-nse-authoritative-dedupe-TDD-plan.md`
- `04-P0-notifications-respect-settings-and-membership-TDD-plan.md`
- `10-P2-reaction-reliability-TDD-plan.md`
- `10-P5-reaction-tombstone-TDD-plan.md`
- `09-P1-media-bounded-and-honest-TDD-plan.md`
- `11-P2-conversation-polish-TDD-plan.md`

---

## Closeout status (2026-06-17) — IMPLEMENTED (all items closed)

Executed in the proposed sequence. Every item is landed and green, including the device-gated
Tier B, which was run on a booted iPhone 16e simulator (real SQLCipher).

| Item | Status | Evidence |
|------|--------|----------|
| **G-NM-1 Tier A** (MEDIUM) | ✅ DONE + mutation-verified | `background_message_handler_test.dart` "suppresses a muted group member end-to-end…" — drives the real fallback resolver + real `groupMemberMessageDisplayEligibility`; neutering the helper's mute check turns it red. |
| **G-S5-1** (parity fixture) | ✅ DONE (Dart verified + drift-mutation-checked; Swift wired) | New `test_fixtures/si5_dedupe_keys.json`; Dart "matches the shared SI-5 dedupe-key fixture"; Swift `testGateMessageKeyMatchesSharedDedupeFixture` + `loadDedupeKeyFixture`. |
| **G-NM-2** (open-flow case) | ✅ DONE | `chat_and_group_push_open_flow_test.dart` "group push whose group is unresolvable…" (push→route→`resolveGroupNotificationRouteTarget`→missing-no-invite). |
| **G-09-2** (sim-proof location) | ✅ DONE (cross-ref comment + plan reconcile) | Header note in `media_download_slow_transfer_simulator_test.dart`; plan §3 reconciliation block. |
| **G-S5-3 / G-NM-3 / G-09-1** (doc) | ✅ DONE | `52-notification-journey-test-matrix.md` RG-009 + Slice-1 citations on SM-004/GMN-102/GMN-103/RG-006; SI-5 plan RG-006→RG-009 fix; 09-P1 plan reconciliation note. |
| **G-S5-2** (O_EXCL bonus) | ✅ DONE (Swift, inspection-verified) | `AppGroupPushDedupeStore.init(directory:)` + `testAppGroupPushDedupeStoreClaimIsFirstWinsSecondLoses`. |
| **G-NM-1 Tier B** (device) | ✅ DONE — ran on iPhone 16e sim (real SQLCipher) | New `integration_test/group_mute_notification_db_proof_test.dart` (`@Tags(['device'])`): seeds a muted group + present member into a real SQLCipher DB, exercises the resolver's `dbLoadGroup:313 → dbLoadGroupMember:315 → groupMemberMessageDisplayEligibility:320` hop, asserts the projected `is_muted` surfaces and suppresses with reason `muted` (and `allow` un-muted). `2/2 passed` on sim `CD5929A6` (Gap Closure Dana iPhone 16e). The assertion `loadedGroup['is_muted'] == 1` is inherently sensitive to a `dbLoadGroup` projection regression (drop the column → null → fail). |

**Verification run:** `flutter test` across the 4 touched Dart files = **45 passed**; `flutter analyze`
on them = 0 new issues (2 pre-existing `_SlowWritingBridge` unused-param warnings, untouched). The
device Tier-B proof = **2/2 passed** on the iPhone 16e simulator (`group_mute_notification_db_proof_test.dart`,
real SQLCipher). The two Swift `NotificationPreviewResolverTests` additions + the
`AppGroupPushDedupeStore` ctor are inspection-verified against an unchanged `gateMessageKey`/`claim()`
and run on the next RunnerTests simulator pass (iOS builds need a flutter-quiet window per the SI-5
plan §Gate caveat).

No production behavior changed (one additive Swift test seam ctor); no migration, no flag.

---

## 0. Audit verdict — what is already DONE (no action)

**Implementation is complete in all six plans. There are NO lazy implementation deferrals.**
Every deferred item is genuinely external: the out-of-process iOS NSE→app round-trip
(`simctl push` does not invoke the NSE), relay-side media retention + ACL protocol (needs a relay
build + EC2 deploy + soak), `receivedAtNano` (needs a gomobile bind + native release), and the
physical-device matrix.

| Plan | Implementation | Residual |
|------|----------------|----------|
| **10-P2 reaction reliability** | FULLY done incl. *optional* Phase 5 tombstone (mig 081 + 082, DB v91, custody-before-publish, asyncMap serialize, use-case LWW, durable buffer flushed at all 3 trigger points, exactly-once by claim-before-emit) | **None** |
| **10-P5 reaction tombstone** | FULLY done (mig 082, soft-delete `dbDeleteReaction`, `removed_at IS NULL` loaders, `removedAt ?? timestamp` LWW comparand, clear-on-readd) | **None** |
| **11-P2 conversation polish** | FULLY done (items 2/3/5 wired end-to-end on both screens; deferred 1/4/6/7 scoped with rationale & verified untouched); device-proofed iPhone16e | **None** |
| **09-P1 media bounded+honest** | FULLY done for declared scope (per-type caps, GIF fold ×3 sites, send+receive split, mig 089 bounded retries, terminal `download_failed`/`integrity_failed`, l10n). Relay 4a/4b + protocol 4c justified-deferred (relay build + deploy) | **Test-location drift only** → G-09-1, G-09-2 (both LOW, substance already covered) |
| **04-SI5 NSE dedupe** | FULLY done & **live** (not dark), committed `b63c19d5`; byte-exact key parity verified between Swift `gateMessageKey` and Dart `_messageKey` incl. `m`-alias exclusion + double-`message:` group shape | 3× LOW → G-S5-1, G-S5-2, G-S5-3 |
| **04 notifications (settings+membership)** | Slice 1 FULLY done & wired (banner sanitization, durable gate storage + telemetry, mute suppression at both producers, dead-tap feedback). Slice 2 native/relay justified-deferred | G-NM-1 (**MEDIUM**), G-NM-2 (LOW), G-NM-3 (LOW) |

Everything below is **test regression-locks + doc reconciliation**. None blocks a release; G-NM-1 is
the only item with real regression-protection value. All fixes are host-runnable and fold into
existing harness entrypoints — **zero new device builds**.

---

## P1 — Real regression lock (do this one)

### G-NM-1 (MEDIUM, test) — Background encrypted-DB mute path has no end-to-end lock

**Context.** The background producer's mute suppression is fully implemented and wired:
`background_message_handler.dart:225` registers `_resolveGroupMessageNotificationDisplayEligibilityFromEncryptedDb`,
which opens `identity.db` (readOnly), `dbLoadGroup` (:313), `dbLoadGroupMember` (:315), then consumes
`groupMemberMessageDisplayEligibility(groupRow)` at **:320** → `suppressed('muted')` when `is_muted==1`.
But **every** handler-level group test stubs the outer seam via
`debugSetBackgroundPushNotificationDisplayEligibilityResolver`, short-circuiting the real `:225→:313→:320`
chain; only the *pure helper* is unit-tested (`background_message_handler_test.dart:623-645`) and the
SQLCipher fixture was explicitly skipped (comment :620-622). **A wiring regression — dropping the :320
helper call, `dbLoadGroup` ceasing to project `is_muted`, or unregistering the :225 resolver — would pass
every existing test.** This is the plan's unmet RED test #3 (Session 3).

**RED — Tier A (mandatory, host-runnable, no SQLCipher):**
In `test/features/push/application/background_message_handler_test.dart`, add a case that does **not**
stub the eligibility resolver. Instead inject a resolver that delegates to the *real*
`resolveBackgroundPushFallbackDisplayEligibility` with
`groupMessageDisplayEligibilityResolver: (_) async => groupMemberMessageDisplayEligibility({'is_muted': 1})`,
fire `firebaseMessagingBackgroundHandler` with a `group_message`, and assert: (a) `log.where(method=='show')`
is empty, and (b) a `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` flow event with `reason == 'muted'`. This locks
helper → suppress → no-show end-to-end through the handler.

**RED — Tier B (optional, closes the literal :320/`dbLoadGroup`-column coverage):**
Keep the resolver at its DEFAULT (`resolveBackgroundPushNotificationDisplayEligibilityFromLocalState`), stand
up an `identity.db` seeded with an identity row + a `groups` row (`is_muted=1`) + a matching `group_members`
row for the local peer, fire the handler, assert no `.show` + `reason 'muted'`. Reuse the fixture pattern in
`test/core/database/helpers/identity_db_helpers_test.dart`. **Because `identity.db` is SQLCipher-encrypted and
cannot run on the plain host VM, place Tier B as a `@Tags(['device'])` proof folded into the existing
DB-proof entrypoint** (mirror `integration_test/group_reaction_reliability_db_proof_test.dart`) — do **not**
spawn a new device build. Tier A is the required host floor; Tier B is the nice-to-have.

**GREEN.** Production is already correct — the test *is* the deliverable.
**Verify (mutation).** Temporarily revert `:320` to `allowCurrentMember()` and confirm Tier A goes red; restore.
**Gate.** `flutter test test/features/push/application/background_message_handler_test.dart` green; mutation-verified.

---

## P2 — Quality test items (low; do or explicitly accept)

### G-S5-1 (LOW, test) — Shared dedupe-key parity fixture was never built

**Context.** Plan §2/§5-S4 mandated a **single shared fixture** `test_fixtures/si5_dedupe_keys.json` consumed
by *both* the Swift XCTest and the Dart test so "any drift fails both" — called "the only thing standing
between works and silently never dedupes." That file does not exist. Both sides instead hardcode the expected
keys **independently** (`ios/RunnerTests/NotificationPreviewResolverTests.swift:148-207` uses `peer-alice`/`msg-1`;
`test/core/notifications/recent_remote_notification_gate_test.dart:276-314` uses `peer-123`/`msg-7` — different
ids, proving no shared source). The literals currently match, so dedupe works **today**; the drift-resistance
the plan demanded is what's missing.

**RED.** Create `test_fixtures/si5_dedupe_keys.json` as an array of canonical cases:
`{kind, peerId|groupId, messageId, expectedKey}` covering 1:1 (`message:<peer>|<id>`), group (double-`message:`
shape `message:group:<g>|message:<m>|<m>`), the relay `from`/`id` aliases, and the `m`-only alias → `expectedKey: null`.
Replace the hardcoded literals on both sides with iteration over the loaded fixture: the Dart test loads +
`jsonDecode`s it and asserts the gate's key/consume per case; the Swift XCTest loads the same file (relative path
from the test `#file`, or repo-root `test_fixtures/`) and asserts `RecentRemoteShownMarkerStore.gateMessageKey == expectedKey`.

**GREEN.** No production change.
**Verify (mutation).** Edit one `expectedKey` in the fixture → both the Swift and Dart targets must fail.
**Gate.** RunnerTests + `recent_remote_notification_gate_test.dart` green.

### G-S5-2 (LOW, test — explicit "bonus") — `AppGroupPushDedupeStore.claim()` O_EXCL untested

**Context.** Plan §5 Session 2 listed a bonus: lock `claim()` first-wins/second-loses on a real filesystem. Not
done — `AppGroupPushDedupeStore` has only `init?(appGroupIdentifier:)` (no injectable dir), and dedupe is exercised
only via the in-memory `MemoryPushDedupeStore` fake, so the real `O_EXCL`/`open()` path is untested.

**GREEN (tiny prod seam).** Add `init(directory: URL)` to `AppGroupPushDedupeStore`
(`ios/NotificationService/NotificationPreviewResolver.swift`), mirroring `RecentRemoteShownMarkerStore.init(directory:)` (:485).
**RED.** Add one XCTest (temp-dir pattern from `testRecentRemoteShownMarkerWriterReproducesTheDartGateKey`):
construct `AppGroupPushDedupeStore(directory: tmp)`, assert first `claim(type:"new_message", messageId:"msg-1") == true`,
second identical `== false` (EEXIST second-loses), exactly one marker file exists; clean up.
**Gate.** RunnerTests green. *(Bonus-tier — defer if release-pressed.)*

### G-NM-2 (LOW, test) — `chat_and_group_push_open_flow_test` not augmented for missing-no-invite

**Context.** Plan Session 4 RED #1 asked to augment `chat_and_group_push_open_flow_test.dart` so the
missing-no-invite branch yields "show feedback" (not a silent miss). The file still has only success-path tests.
The behavior **is** covered elsewhere (`resolve_group_notification_route_target_use_case_test.dart` discriminator +
`group_missing_notification_tap_feedback_test.dart` SnackBar/Retry/route-home), so user risk is low.

**RED.** Add one case to `chat_and_group_push_open_flow_test.dart`: drive
`resolveGroupNotificationRouteTarget` with empty group + invite repos, assert `result.hasGroup == false &&
result.hasPendingInvite == false`, then call `showGroupMissingNotificationFeedback` and assert a SnackBar shows
(not a silent miss). Reuse the existing harness pattern.
**GREEN.** No production change.
**Gate.** `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart` green.

### G-09-2 (LOW, test) — one direct assertion missing on the retry sim proof

**Context.** Plan Phase 3 sim proofs #1/#2 prescribed a `_NotFoundBridge` in
`media_download_slow_transfer_simulator_test.dart`. The full substance landed instead in
`download_media_use_case_test.dart:646-777` (increment+flip, not-found 0-budget, reset-to-0, no-infinite-retry) —
a **location drift, not a coverage hole**. The only assertion not covered *directly* is that a `download_failed`
row is excluded by `_shouldRecoverVisibleAttachment` (covered indirectly via
`GroupMediaIntegrityPolicy.isRetryableDownloadFailure == false`).

**Lowest-cost close (pick one):**
- *(preferred)* Add a one-line cross-reference comment at the top of
  `media_download_slow_transfer_simulator_test.dart` pointing to `download_media_use_case_test.dart:646-777` as the
  home of the INV-DL-1/2/4 sim proofs, so the un-extended simulator file is not misread as missing coverage; **and**
  reconcile the 09-P1 plan Phase-3 gate text to record that proofs #1/#2 landed there.
- *(if literal deliverable is required)* Add a small `_NotFoundBridge` (returns `{ok:false,'not found'}`) to the
  simulator file and one assertion that a `download_failed` row is not re-recovered by `_shouldRecoverVisibleAttachment`.

---

## P3 — Documentation reconciliation (no code; trivial)

### G-S5-3 — Add the SI-5 dedupe row to the notification journey matrix
`Test-Flight-Improv/52-notification-journey-test-matrix.md` has no SI-5 row (plan §6's "RG-006" reference is stale —
RG-006 already denotes removed/rejoined eligibility). Append **RG-009**: "NSE-authoritative cross-process dedupe
(SI-5)" — out-of-process NSE shows + writes the app-group sidecar marker, app process later reads it and suppresses
the duplicate Dart banner; sim layers A/B/C green (RunnerTests writer, Dart gate union-read,
`integration_test/app_group_path_simulator_test.dart`); genuine NSE→app round-trip = device/TestFlight-only. Then fix
the stale "RG-006" reference in the SI-5 plan §6 to "RG-009".

### G-NM-3 — Cite Slice-1 coverage in the matrix rows
Update `52-notification-journey-test-matrix.md` rows **SM-004 / GMN-102 / GMN-103 / RG-006** to cite the landed
Slice-1 Dart proofs (`background_message_handler_test.dart` `is_muted`, `resolve_group_notification_route_target_use_case_test.dart`
`group_muted`, `background_push_notification_fallback_test.dart` foreground-muted no-show). **Leave the iOS-NSE
citations for when Slice 2 lands** — those are legitimately deferred, do not fabricate them.

### (09-P1) G-09-1 — Reconcile the e2e deliverable note
`integration_test/media_message_journey_e2e_test.dart` was intentionally **not** extended with the oversized→no-blob
and download-terminal-render scenarios; the closure note already justifies this (the journey harness fires the
send-gate before its network layer and has no oversized/upload seam) and the equivalent assertions exist in
`group_conversation_wired_test.dart:1342-1446` (no `group:publish` on oversized/GIF) and
`audio_player_widget_test.dart:139-161` / `media_grid_cell_test.dart` (terminal label, no-retry). **No action needed
beyond confirming this note stays in the 09-P1 closure log** — recorded here so a downstream reviewer does not
mistake the un-extended e2e file for missing coverage.

---

## Suggested order & effort
1. **G-NM-1 Tier A** — ~1 short host test, real value. *(P1)*
2. **G-S5-1** — parity fixture; the plan itself flagged it as load-bearing. *(P2)*
3. **G-NM-2**, **G-09-2 (comment+doc variant)** — trivial host/doc. *(P2)*
4. **G-S5-3, G-NM-3, G-09-1** — pure doc, batch together. *(P3)*
5. **G-S5-2** (bonus) and **G-NM-1 Tier B** (`@Tags(['device'])`) — optional; do alongside the next device build. *(P2/opt)*

No DB migration, no flag, no production-behavior change in any item.
