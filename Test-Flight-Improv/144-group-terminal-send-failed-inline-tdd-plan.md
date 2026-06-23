# 144 - Group terminal send failures keep an inline non-retryable "failed" bubble + reliable read-only banner  (Bug | Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_conversation_wired.dart, send_group_message_use_case.dart, group_message.dart, group_message_repository(_impl).dart, group_messages_db_helpers.dart, letter_card.dart, group_conversation_screen.dart, app_*.arb, run_test_gates.sh, group_conversation_wired_test.dart, letter_card_test.dart | verify→refute complete (6-agent workflow): bug confirmed & committed on HEAD; `send_failed` terminal status already exists (no migration); banner gap is ONLY unauthorized+groupNotFound; reaction failed-bubble needs migration (OUT) | Planner |
| 2026-06-23 | Planner | (as above) | Single `_terminalSendReadOnly` override drives canWrite + banner text + per-message reason; reuse `statusSendFailed`; add 2 LetterCard params; drop terminal snackbars | Reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows in this plan)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 144; files go to 143)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof)

## Exact Problem Statement
When a group send hits a **terminal** result — `groupDissolved`, `unauthorized`, or `groupNotFound` — the conversation **deletes the optimistic message and discards the user's typed text / recorded voice**, surfacing only a transient ~4s snackbar. For **text** (`group_conversation_wired.dart:2114-2148`) it calls `_removeLocalMessage(messageId)` (+ conditional `msgRepo.deleteMessage` when `prePersistedOrdinaryMediaRow`); for **voice** (`:3882-3914`) it calls `_removeLocalMessage` + **unconditional** `msgRepo.deleteMessage`. Neither branch restores the composer snapshot captured at `:1845` (cleared at `:1879-1880`), so the typed text is gone. If the 4s snackbar is missed (scrolled, backgrounded), the user believes the message sent.

Separately, the **read-only composer banner** (`_canWrite` → `_readOnlyBannerText`, rendered by `GroupConversationScreen` at `group_conversation_screen.dart:239-242`) reliably appears only for the **already-dissolved-row** case (terminal branch calls `_refreshVisibleGroup` → `_canWriteForGroup` `isDissolved` short-circuit at `:4251`). For `unauthorized` (you were removed / lost membership) and `groupNotFound` (group gone), the terminal branch calls **only** `_showFloatingSnackBar` — no refresh — so the composer can stay writable even though the next send will fail again.

What must improve:
- Terminal text/voice failures **keep the message** as a **non-retryable** inline "failed" bubble showing **"Couldn't send — <reason>"** + a **Delete** affordance (no Retry — retry into a dissolved/removed/missing group can never succeed). Typed text / recorded audio is preserved in-bubble.
- The read-only banner **reliably flips** for all terminal reasons (dissolved already works; add `unauthorized` and `groupNotFound`, plus the empty-membership `groupDissolved` sub-case which fails open today).
- The now-redundant terminal snackbars are **removed** (bubble + banner carry the message).

What must stay unchanged (→ preserved-green sentinels):
- The **transient** failure path (network/publish/no-custody) that already keeps a **retryable** `'failed'` bubble + Retry and preserves text (`_restoreComposerSnapshot` `:2505-2555`, voice else `:3915-3924`).
- The existing **retry-exhausted** `send_failed` treatment in a still-writable group (must NOT show a terminal "group dissolved" reason).
- LetterCard's existing retryable-`failed` Retry control (`letter_card_test.dart:969`).
- Group gates (groups suite), feed/LetterCard suites, `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed)
**Confirmed & committed on HEAD** (git blame `b711227dd` 2026-03-26 for the remove+delete; `0e0ac0de5` 2026-05-29 for the snackbar; tree clean — NOT build-skew):
- Text terminal branch destroys the bubble + text: `group_conversation_wired.dart:2118` `_removeLocalMessage`, `:2130` conditional `deleteMessage`, no composer restore in `:2114-2148`.
- Voice terminal branch: `:3887` `_removeLocalMessage`, `:3895` **unconditional** `deleteMessage`, no composer restore in `:3882-3914`.
- Banner gap: `unauthorized` (`:2140-2143`/`:3904-3908`) and `groupNotFound` (`:2144-2147`/`:3909-3913`) call only `_showFloatingSnackBar`; no `_refreshVisibleGroup`, no `_refreshSendCapabilityAndCanWrite`.
- Terminal results derive from **local** reads in the use-case (`send_group_message_use_case.dart`: `groupNotFound` `:763` getGroup==null; `groupDissolved` `:766/:906`; `unauthorized` `:807/:864/:877/:957`), and `_onSend`'s pre-gate `_refreshSendCapabilityAndCanWrite` (`:1823`) aborts on a locally-known cannot-write — so the terminal branch is reached on derivation divergence, exactly when the user has stale local state and most needs durable feedback.

Refuted / do-NOT-re-introduce:
- ❌ "deletion/text-loss already fixed" — **SURVIVES**; no path restores text for terminal reasons.
- ❌ "banner already wired for all reasons" — **PARTIAL**; `groupDissolved` IS wired (`:2134/:3898` → `:4251/:4272`). Gap is **only** `unauthorized` + `groupNotFound`. Do not re-plan a dissolved-banner fix.
- ❌ "empty-membership auto-flips read-only" — **FALSE**; active-member check **fails open** (`members.isEmpty → active=true`, `:1175`/`:4327`). The empty-membership `groupDissolved` (`uc:906`, row NOT marked dissolved) needs the explicit override, not a membership refresh.
- ❌ "voice and text terminal branches identical" — voice `deleteMessage` is **unconditional** (`:3895`); text guards it (`:2129-2131`).
- ❌ "needs a DB migration for the message terminal state" — **FALSE**; `GroupMessage.status` is unconstrained TEXT and `statusSendFailed='send_failed'` already rides it (`group_message.dart:49`). A migration is required **only** for a persisted failed-*reaction*, which is OUT of scope.
- ❌ "build-skew" — **REFUTED**; destructive logic is committed on HEAD, tree clean.

## Real Scope
In scope:
- Replace bubble-deletion in the **text** (`:2114-2148`) and **voice** (`:3882-3914`) terminal branches with: keep the bubble, mark it `GroupMessage.statusSendFailed`, persist it (parity with the transient failed path), preserve attachments/audio.
- Add a single private read-only override `_terminalSendReadOnly` (enum: `none|dissolved|removed|unavailable`) set in the terminal branches; fold it into `_canWrite` and `_readOnlyBannerText`; use it as the source for the per-message reason text.
- Extend the reaction terminal handling (`:4658-4688`) to set the override for `unauthorized`/`groupNotFound` too (currently only `groupDissolved`); **keep the silent reaction revert** (no failed-reaction bubble).
- `GroupConversationScreen.buildLetterCard` (`group_conversation_screen.dart:565-576,650-662`): make terminal `send_failed` **non-retryable** (Retry only for retryable `'failed'`), allow **Delete even when `!canWrite`**, and pass a `failedReasonText` for terminal `send_failed` rows.
- `LetterCard` (`letter_card.dart:433-478`): add `failedReasonText` (String?) + `onDeleteFailedMessage` (VoidCallback?); render reason line + Delete in the failed-action row.
- Drop the 7 terminal snackbars (`:2136/:2141/:2145`, `:3900/:3906/:3911`, `:4685`).
- l10n: 4 new keys × 3 locales (below). Reuse `conversation_context_delete` for the Delete label.
- Harness: **add `group_conversation_wired_test.dart` to `GROUP_TESTS`** in `scripts/run_test_gates.sh`.

Out of scope (owning work named):
- **Persisted failed-reaction bubble** — needs a `MessageReaction` status field + migration + `UNIQUE(message_id, sender_peer_id)` redesign. Owner: a future "reaction reliability" session. Reaction here keeps silent-revert + banner parity only.
- Reworking the **transient** failed/retry path, the relay/custody layer, or the use-case result enum.
- Any 1:1 conversation parity (this plan is groups-only).

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — terminal branches `:2114-2148` (text), `:3882-3914` (voice), `:4658-4688` (reaction); `_canWrite` `:4404`; `_canWriteForGroup` `:4250`; `_readOnlyBannerText` `:4270`; `_updateLocalMessageStatus` `:3302`; `_persistMessageStatus` `:3331`; `_removeLocalMessage` `:3314`.
- `lib/features/groups/presentation/screens/group_conversation_screen.dart` — `buildLetterCard` flags `:565-576`, callback wiring `:650-662`, read-only banner `:239-242,913-917`, ctor params `:48,84-86,98`.
- `lib/features/conversation/presentation/widgets/letter_card.dart` — failed-action row `:433-478`; status icon/color/semantic `:975,995,1015`.
- `lib/features/groups/domain/models/group_message.dart` — `status` `:44`, `statusSendFailed` `:49`.
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` — append-by-key (line offsets diverge en vs ar/de).
Direct tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart` — rewrite `:2505` (unauthorized), `:2549` (groupNotFound), `:2585`/`:2666` (media terminal); add dissolved/voice/reaction/separation cases.
- `test/features/conversation/presentation/widgets/letter_card_test.dart` — add non-retryable terminal render; keep `:969` retryable test green.
Dependency-only context:
- `lib/features/groups/application/send_group_message_use_case.dart` (result origins — not edited).
- `lib/features/groups/data/group_messages_db_helpers.dart` (status persistence — not edited).

## Existing Tests Covering This Area
- `group_conversation_wired_test.dart:2505` "unauthorized text send shows a concrete error instead of disappearing silently" — asserts row **not** persisted + `group_send_permission_lost` snackbar. PASSES on HEAD. **Locks OLD behavior → must be rewritten.**
- `group_conversation_wired_test.dart:2549` "missing-group text send …" (groupNotFound) — asserts row not persisted + `group_unavailable_snackbar`. PASSES. **Rewrite.**
- `group_conversation_wired_test.dart:2585/:2666` ordinary-media groupNotFound/unauthorized — assert messages empty + `deletedDirs hasLength(1)` + no publish; no snackbar asserted. PASSES. **Rewrite (retain bubble; deletedDirs empty).**
- groupDissolved **send-path**: NO test (gap). Voice terminal: NO test (gap).
- Banner branch coverage exists (`:5210` admin_only, `:5239` dissolved, `:5404`/`:5476` not_active, `:5418` waiting_key, `:5671` waiting_identity) — but **never from a terminal SEND** (only direct group-state). Gap: send-path banner flip for unauthorized/groupNotFound.
- `letter_card_test.dart:273` failed icon; `:969` failed-text Retry; `:830` failed-media retry/delete; `:889` MD-012 unavailable-vs-failed. Suite 81/81 green. Retry tests exercise generic `'failed'` only.

Missing coverage gaps: terminal-failed **bubble retained** (text/voice/media); **reason text**; **Retry absent / Delete present** for terminal; **banner flip from send** (unauthorized/groupNotFound/empty-membership-dissolved); retry-exhausted-vs-terminal **separation**; reaction banner parity.

Already in curated family arrays?: `letter_card_test.dart` ✅ in `GROUP_TESTS` (`run_test_gates.sh:128`) + baseline (`:61`). **`group_conversation_wired_test.dart` ❌ NOT in `GROUP_TESTS`** (`:115-130` lists `group_conversation_screen_test.dart`); it runs only via auto-glob/whole-dir. → registration step required.

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

1. `group_conversation_wired_test.dart`::"dissolved text send keeps a non-retryable failed bubble and flips read-only banner"
   - Tier: integration/widget (wired screen, fakes + real migrations in setUp)
   - Shape/setup: group whose row `isDissolved=true` (or empty-membership chat → `uc:906`); enter text; `onSend`; pump.
   - RED on HEAD because: HEAD `_removeLocalMessage` deletes the row → `find` for the message text finds nothing; asserting the bubble PRESENT with `status==statusSendFailed` fails.
   - GREEN after fix asserts: message present, `status==GroupMessage.statusSendFailed`; reason text `group_send_failed_dissolved` visible; **no** `ValueKey('failed-message-retry-failed-text')`; Delete affordance present; composer banner shows `group_read_only_dissolved`; `group_dissolved_snackbar` **absent**.
   - Mutation that re-reds: restore `_removeLocalMessage(messageId)` in the dissolved branch → message gone → red.

2. `group_conversation_wired_test.dart`::"unauthorized text send keeps failed bubble (removed) and flips read-only banner"  *(rewrite of `:2505`)*
   - Tier: integration/widget
   - RED on HEAD because: HEAD removes the row and shows `group_send_permission_lost` snackbar **and leaves composer writable**; new asserts (bubble present + `send_failed` + `group_send_failed_removed` + `screen.canWrite isFalse` + banner `group_read_only_not_active` + **no** snackbar) fail.
   - GREEN asserts: bubble present `send_failed`; reason `group_send_failed_removed`; no Retry; Delete present; `canWrite isFalse`; banner `group_read_only_not_active`; no `group_send_permission_lost`.
   - Discriminator (banner gap): assert `screen.canWrite isFalse` — on HEAD it stays writable for unauthorized (this is the banner-gap RED).
   - Mutation: revert the unauthorized branch override+keep-bubble → red.

3. `group_conversation_wired_test.dart`::"missing-group text send keeps failed bubble (unavailable) and flips read-only banner"  *(rewrite of `:2549`)*
   - Tier: integration/widget
   - RED on HEAD because: HEAD removes row + `group_unavailable_snackbar`, banner not shown; new contract fails.
   - GREEN asserts: bubble present `send_failed`; reason `group_send_failed_unavailable`; no Retry; Delete present; `canWrite isFalse`; banner `group_read_only_unavailable`; no `group_unavailable_snackbar`.
   - Mutation: revert groupNotFound override+keep-bubble → red.

4. `group_conversation_wired_test.dart`::"voice terminal send keeps failed bubble instead of deleting"
   - Tier: integration/widget (drive `onRecordStop` → terminal result)
   - RED on HEAD because: voice branch `_removeLocalMessage` + **unconditional** `deleteMessage` → message gone; asserting present fails.
   - GREEN asserts: voice message present `send_failed`; audio attachment retained (not deleted); no Retry; Delete present; banner flips per reason; no snackbar.
   - Mutation: revert voice keep-bubble (restore `:3887`/`:3895`) → red.

5. `group_conversation_wired_test.dart`::"ordinary media terminal rejection retains the failed media bubble"  *(rewrite of `:2585`/`:2666`)*
   - Tier: integration/widget
   - RED on HEAD because: HEAD asserts `messages` empty + `deletedDirs hasLength(1)`; new asserts (media bubble retained `send_failed` + `deletedDirs` **empty** + Delete present) fail.
   - GREEN asserts: media message present `send_failed`; durable media dir NOT auto-deleted; Delete affordance present.
   - Mutation: revert media keep-bubble → red.

6. `group_conversation_wired_test.dart`::"retry-exhausted send_failed in a writable group shows no terminal reason"  *(separation guard)*
   - Tier: integration/widget
   - RED on HEAD: n/a pre-feature (no reason concept). Becomes mutation-verifiable: after fix, mutate `failedReasonText` to be derived from group state **regardless** of `_terminalSendReadOnly` → this test reds.
   - GREEN asserts: a `send_failed` row whose group is still writable (`_terminalSendReadOnly==none`) shows the existing send_failed icon and **no** "Couldn't send — group …" reason text; `canWrite isTrue`.
   - Mutation: drop the `_terminalSendReadOnly != none` guard on `failedReasonText` → reason leaks → red.

7. `group_conversation_wired_test.dart`::"reaction terminal result reverts reaction and flips read-only banner without a bubble"
   - Tier: integration/widget
   - RED on HEAD because: HEAD only special-cases `groupDissolved` (snackbar) and silently reverts `unauthorized`/`groupNotFound` with `canWrite` unchanged; asserting `canWrite isFalse` + banner for those fails.
   - GREEN asserts: optimistic reaction reverted to `previousReactions`; **no** message bubble created; `canWrite isFalse`; banner shows the right string; no `group_dissolved_snackbar`.
   - Mutation: revert reaction override extension (`:4658-4661`) → red.

8. `letter_card_test.dart`::"send_failed with failedReasonText renders reason + Delete and no Retry"
   - Tier: widget
   - Shape/setup: pump `LetterCard(status:'send_failed', failedReasonText:'Couldn't send — …', onDeleteFailedMessage: cb, onRetryFailedMessage: null)`.
   - RED on HEAD because: `failedReasonText`/`onDeleteFailedMessage` params don't exist → compile-time red.
   - GREEN asserts: reason text visible; Delete key present + fires cb; retry key `findsNothing`.
   - Mutation: remove the reason/Delete render branch in `letter_card.dart` → red.
   - Pitfall: inline-WidgetSpan U+FFFC — assert via `find.byKey`/`find.textContaining` where the bubble uses a WidgetSpan body (see 137 closure note).

9. `letter_card_test.dart`::"retryable failed still shows Retry (preservation)"  *(sentinel — existing `:969` kept green)*
   - Tier: widget
   - Asserts: `status:'failed'` + `onRetryFailedMessage!=null` still shows the Retry key. No change expected; guards against the retry/terminal split breaking retryable rows.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 dissolved text bubble+banner | screen state + reason + banner | integration/widget | wired::"dissolved text send keeps …" | HEAD `_removeLocalMessage` deletes row | restore `_removeLocalMessage` dissolved | `./scripts/run_test_gates.sh groups` | **add wired_test to `GROUP_TESTS`** |
| TC-02 unauthorized=removed bubble+banner | screen + banner-gap | integration/widget | wired::"unauthorized text send keeps …" | HEAD removes row + snackbar + writable | revert unauthorized keep-bubble+override | `./scripts/run_test_gates.sh groups` | add wired_test to `GROUP_TESTS` |
| TC-03 groupNotFound=unavailable bubble+banner | screen + banner-gap | integration/widget | wired::"missing-group text send keeps …" | HEAD removes row + snackbar, no banner | revert groupNotFound keep-bubble+override | `./scripts/run_test_gates.sh groups` | add wired_test to `GROUP_TESTS` |
| TC-04 voice terminal bubble | screen (voice path) | integration/widget | wired::"voice terminal send keeps …" | HEAD `_removeLocalMessage`+uncond `deleteMessage` | revert voice keep-bubble | `./scripts/run_test_gates.sh groups` | add wired_test to `GROUP_TESTS` |
| TC-05 media terminal retained | screen (media path) | integration/widget | wired::"ordinary media terminal …" | HEAD messages empty + deletedDirs len1 | revert media keep-bubble | `./scripts/run_test_gates.sh groups` | add wired_test to `GROUP_TESTS` |
| TC-06 retry-exhausted separation | guard logic | integration/widget | wired::"retry-exhausted send_failed …" | post-fix guard; mutate to leak reason | drop `_terminalSendReadOnly!=none` guard | `./scripts/run_test_gates.sh groups` | add wired_test to `GROUP_TESTS` |
| TC-07 reaction banner parity | screen (reaction path) | integration/widget | wired::"reaction terminal result …" | HEAD only dissolved handled; others writable | revert reaction override extension | `./scripts/run_test_gates.sh groups` | add wired_test to `GROUP_TESTS` |
| TC-08 LetterCard terminal render | widget render | widget | letter_card_test::"send_failed with failedReasonText …" | new params absent → compile red | remove reason/Delete branch | `./scripts/run_test_gates.sh groups` | AUTO (glob) + already in `GROUP_TESTS` |
| TC-09 retryable Retry preserved | preservation | widget | letter_card_test::"retryable failed still shows Retry" | n/a (sentinel) | split retry to require `'failed'` only — if it also drops retryable, reds | `./scripts/run_test_gates.sh groups` | AUTO (glob) |

## Invariants (locked by tests)
- INV-1: a terminal text/voice/media send **retains** the optimistic message at `statusSendFailed` (never `_removeLocalMessage`/`deleteMessage`) → TC-01/04/05.
- INV-2: a terminal `send_failed` bubble shows the reason + Delete and **never** a Retry control → TC-01/08.
- INV-3: after a terminal send, `_canWrite` is **false** and the banner shows the reason-correct string for dissolved/removed/unavailable → TC-01/02/03/07.
- INV-4: a `send_failed` row in a still-writable group (retry-exhausted) shows **no** terminal reason and keeps `canWrite` true → TC-06.
- INV-5: terminal snackbars are **not** shown (no `group_dissolved_snackbar`/`group_send_permission_lost`/`group_unavailable_snackbar` from the send path) → TC-01/02/03/07.
- INV-6: the retryable `'failed'` Retry control is unchanged → TC-09.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`; run the 9 RED/rewritten tests; confirm each fails for its documented reason.
2. `group_conversation_wired.dart`: add `enum _TerminalReadOnly { none, dissolved, removed, unavailable }` + field `_terminalSendReadOnly = none`. Change `_canWrite` getter → `_terminalSendReadOnly == _TerminalReadOnly.none && _canWriteForGroup(_group)`. In `_readOnlyBannerText`, branch on `_terminalSendReadOnly` first (dissolved→`group_read_only_dissolved`, removed→`group_read_only_not_active`, unavailable→`group_read_only_unavailable`) before the existing logic.
3. Text terminal branch `:2114-2148`: remove `_removeLocalMessage` + attachment/dir/row deletes; instead `setState`-mark `statusSendFailed` (`_updateLocalMessageStatus` + persist — `saveMessage` first if the plain-text row isn't pre-persisted, matching the transient failed path's durability); set `_terminalSendReadOnly` per result; delete the 3 snackbars; keep `_refreshVisibleGroup` for dissolved (harmless, refreshes other group UI).
4. Voice terminal branch `:3882-3914`: same — keep bubble + audio, mark `statusSendFailed`, set override, drop snackbars; do not call unconditional `deleteMessage`.
5. Reaction caller `:4658-4688`: extend to also catch `unauthorized`/`groupNotFound` reaction results → set `_terminalSendReadOnly` (removed/unavailable) + keep the existing `_restoreReactionState` revert; drop the dissolved snackbar. **Do not** fabricate a failed-reaction bubble (Stop-if: requires a `MessageReaction` schema change → that's the out-of-scope reaction session).
6. `group_conversation_screen.dart` `buildLetterCard`: split Retry from terminal — `showFailedTextRetry`/`showFailedMediaActions` require `status=='failed'` (exclude `statusSendFailed`); allow **Delete** for `statusSendFailed` even when `!canWrite`; when `statusSendFailed` AND a terminal read-only reason is active, pass `failedReasonText` (resolved from the override) + `onDeleteFailedMessage`.
7. `letter_card.dart` `:433-478`: add `failedReasonText` (String?) + `onDeleteFailedMessage` (VoidCallback?); render the reason line + a Delete button (reuse `conversation_context_delete`) in the failed-action row; when `failedReasonText != null` show the non-retryable layout (no Retry).
8. l10n: add `group_send_failed_dissolved`, `group_send_failed_removed`, `group_send_failed_unavailable`, `group_read_only_unavailable` to en/ar/de (append-by-key). Proposed en copy: "Couldn't send — this group was dissolved" / "Couldn't send — you're no longer in this group" / "Couldn't send — this group is unavailable" / "This group is no longer available." Regenerate l10n.
9. `scripts/run_test_gates.sh`: add `test/features/groups/presentation/group_conversation_wired_test.dart` to the `GROUP_TESTS` array.
10. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Reason bleed** into retry-exhausted `send_failed` rows (a live group) → pinned by TC-06 (`_terminalSendReadOnly != none` guard).
- **Plain-text durability**: ordinary text rows may not be pre-persisted; `_persistMessageStatus` is a no-op on a missing row → must `saveMessage` before marking failed (so the bubble survives reopen). Impl step 3; assert in-memory presence (TC-01) and rely on existing `send_failed` round-trip for durability.
- **Empty-membership groupDissolved** (`uc:906`, row not dissolved) → covered by the explicit override, NOT membership (which fails open). TC-01 can use this exact setup as one variant.
- **Delete while `!canWrite`**: Delete must remain reachable so a user can clear a stuck bubble in a dead group → asserted in TC-01/04/05.
- **WidgetSpan U+FFFC** breaking `find.text` on bubble bodies → use `find.byKey`/`textContaining` (137 closure note).

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — all behavior is local screen-state + render. No `integration_test/` scenario, no device-proof, no migration. Deferred device work: none.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'dissolved text send keeps a non-retryable failed bubble'
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart \
  --plain-name 'send_failed with failedReasonText'

# Direct GREEN (after fix)
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart   # expect 81 + new

# Preservation + named gate (after adding wired_test to GROUP_TESTS)
./scripts/run_test_gates.sh groups        # expect prior green count + the 7 new wired cases; the 2 PRE-EXISTING wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine
./scripts/run_test_gates.sh feed          # LetterCard feed variants stay green

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the 9 catalog tests before the fix (deletion/no-params/banner-writable).
- Pre-existing dirty (NOT mine): `group_conversation_wired_test.dart` shows **138 passed / 2 failed on HEAD** — `GMAR-004 reopen hydration …` and `incoming group image refreshes on open recipient route …` (media reopen/hydration, unrelated). Record before execution; do not "fix" by reverting.
- The wider tree is already dirty on `new-feed` (uncommitted Feed/Orbit work per `git status`) — snapshot `git status --short` first; touch only the files in Real Scope.
- Scope drift (BLOCKING): any failure outside the listed files/tests.

## Done Criteria
- [ ] RED added/rewritten first, failed for the expected reason.
- [ ] Each fix mutation-verified (re-red revert named in the matrix).
- [ ] Direct GREEN + groups/feed preservation gates pass; the 2 pre-existing wired fails unchanged.
- [ ] No migration introduced (message terminal state rides `statusSendFailed`).
- [ ] `group_conversation_wired_test.dart` added to `GROUP_TESTS` and confirmed running in `./scripts/run_test_gates.sh groups`.
- [ ] 4 new l10n keys present in en/ar/de; l10n regenerated; `flutter analyze` 0-new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump `currentIdentityDatabaseVersion` (no schema change needed).
- Do not build a persisted failed-**reaction** bubble (model+migration+unique-key — out-of-scope reaction session).
- Do not alter the transient failure / retry path, the use-case result enum, or 1:1 conversation code.
- Do not keep any terminal snackbar "just in case" — bubble + banner are the replacement (INV-5).

## Accepted Differences / Intentionally Out Of Scope
- Reactions keep **silent revert** + banner parity (no inline failed marker) — accepted because the model can't carry a failed state without a migration; owner = future reaction-reliability session.
- Per-message reason is derived from the **current group terminal state** (one reason at a time), not stored per message — accepted (avoids a reason column/migration); a message that transitions reasons reflects the latest group state.

## Dependency Impact
- None outbound. The harness-registration fix (adding `group_conversation_wired_test.dart` to `GROUP_TESTS`) also retroactively gates ALL pre-existing terminal-result + banner behavior under the curated Group gate — a standalone hardening win.

## Reviewer Findings
(pending sufficiency review)

## Arbiter Decision
(pending)

## Final Execution Verdict
(pending execution)
