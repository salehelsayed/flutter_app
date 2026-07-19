# 261 Review — Fix-List (apply against `261-orbit-sole-admin-group-exit-tdd-plan.md`)

Source: second-round `$tdd-review`, 10-agent adversarial audit (3 verifiers incl. Go-bridge domain verification, 6 dimension assessors, completeness critic) + orchestrator source cross-checks, 2026-07-19. Verdict: **ready-with-tightening** — execute after applying §A-§D; §E trims are recommended but not gating. All three load-bearing bets are verified sound: timeout-as-uncertain (Go `group:leave` runs detached after Dart's 30s abandon and `LeaveGroupTopic` is local + idempotent — `GoBridge.kt:161`, `GoBridge.swift:201`, `pubsub.go:203`), `GroupPendingBroadcast` reuse (verbatim signed payload; runner clears only after publish AND inbox; awaitable `drainForGroup`), prepare-sign-first promotion (stale gate precedes all writes; a non-stale explicit `eventAt` passes through unchanged, so the canonical-event match is guaranteed on success).

Decisions:
- **OPEN — user must sign off before step 5: offline-leave policy.** Today a soft publish failure does NOT block leaving (`broadcast_voluntary_leave_use_case.dart:145-158` discards the `callGroupPublish` result; the native leave is local). The plan's `preworkFailed`-on-soft-publish makes leaving impossible while the bridge is down, and Group Info inherits it via step 5. Recommended: **block with honest localized copy** (protocol honesty; peers otherwise never learn the member left), recorded as an Accepted difference + TC-10 fixture (A6/B1 below). Alternative: allow offline leave and enqueue the signed self-removal as a pending broadcast — bigger scope, new producer kind.
- Next action locked: findings + this fix-list; plan file itself not edited.

Verified facts this list relies on (checked against source by the orchestrator):
- Orbit swallows the sole-admin `StateError` silently — `orbit_wired.dart:2744-2780`. ✅
- No `SwipeableGroupRow` widget exists; group rows reuse `SwipeableFriendRow` (`orbit_screen.dart:1337-1441`; `swipeable_group_row_test.dart` imports `swipeable_friend_row.dart`). ✅
- Archived sentinel asserts Unarchive **presence only**, no exclusivity — `swipeable_group_row_test.dart:167-186`. ✅
- `classify_path` ends with a `test/features/**/(application|…|presentation|…)` glob, so `completeness-check` passes with the four headline files **unregistered**; the `groups` lane runs only the `GROUP_TESTS` array (`run_test_gates.sh:320`, classify_path fallback). ✅
- Repush skips the inbox leg when `recipientPeerIds` is empty (`group_pending_broadcast_repush.dart:49`); no group-missing guard (`:22-47`); runner removes rows only on success (`group_pending_broadcast_runner.dart:41-59`); resume `drainAll` fires unawaited; no drain mutex. ✅
- Stale gate at `update_group_member_role_use_case.dart:166-188` runs before the first write at `:205`; `nextMembershipEventAt` returns a non-stale provided time unchanged (`group_membership_event_watermark.dart:97-103`). ✅
- `callGroupInboxStore` **throws** on `ok != true` / timeout (`bridge_group_helpers.dart:849-912`). ✅
- Orbit stuck-row Leave is silent on error while the Group List sibling shows a snackbar (`orbit_wired.dart:2820-2825` vs `group_list_wired.dart:790-798`). ✅
- The l10n integrity scanner cannot see `showConfirmationDialog(title:/description:/confirmLabel:)` string args (`l10n_integrity_test.dart:105-111`), and the retained dissolved-delete dialog is hardcoded English (`orbit_wired.dart:2752-2758`). ✅

Gloss: "headline files" = `group_exit_policy_test.dart`, `group_exit_actions_test.dart`, `group_exit_recovery_sheet_test.dart`, `swipeable_group_row_test.dart`. "Bare leave" = `leaveGroup` without the signed voluntary self-removal broadcast.

---

## §A — Gates that currently let regressions ship green (material)

- **A1.** Amend TC-04: after swipe on an `isArchived: true` row, assert archived rows expose **only** Unarchive — `expect(find.text('Leave'), findsNothing)` and `expect(find.text('Delete'), findsNothing)` — and make "expose active actions on an archived row" the mandatory representative re-red. *Why:* the current sentinel checks presence only; TC-04 is the sole proof for Must-preserve :66 / Done :226, and the edited widget is shared with friend rows, making cross-state leakage the likeliest regression.
- **A2.** Note in TC-03/step 3 that the "group swipe row" is `SwipeableFriendRow` reused (no group-row widget exists): the Leave presentation change modifies the friend-row widget's API, and TC-04's friend-row sentinel is the only guard on that shared surface. *Why:* unstated repo fact the executor needs before editing.
- **A3.** Add a runnable registration gate to Acceptance Gates, e.g. `grep -Ec 'group_exit_policy_test|group_exit_actions_test|group_exit_recovery_sheet_test|swipeable_group_row_test' scripts/run_test_gates.sh` must equal the expected count, and reword the plan-:205 pass interpretation — `completeness-check` and `feature-host-all --list` pass regardless of registration; only the `GROUP_TESTS` array membership puts files in the curated `groups` lane. *Why:* a forgotten step-9 registration is currently undetectable while every closure command exits 0.
- **A4.** Add a first-tap sole-admin wired fixture (TC-03 or TC-11) + a Done checkbox: sole admin's FIRST swipe-Leave opens the recovery sheet (not only the TC-11 race-reopen variant). *Why:* the headline scenario has no direct wired proof; every named test can green while initial-disposition wiring routes imperfectly.
- **A5.** In TC-05/TC-11, assert user-facing dialog/sheet copy via l10n getters (compare against `AppLocalizations` values), and add the retained dissolved-delete confirmation dialog (`orbit_wired.dart:2752-2758`, currently hardcoded English) to the TC-14 key list. *Why:* the l10n scanner is blind to `showConfirmationDialog` string args — exactly the copy shape this plan edits.
- **A6.** Add one positive TC-02 fixture: a member with an identity warning / pending sibling device but current joined evidence **remains eligible**. *Why:* Accepted difference :88 currently has no guard in either direction; an over-strict exclusion passes every gate.

## §B — Undeclared behavior changes & overbroad done criteria (material)

- **B1.** Add an Accepted-differences line declaring the offline-leave block (per the OPEN decision above), pin the localized copy key, and add a TC-10 fixture asserting the blocked-offline outcome + message. *Why:* undeclared availability regression; without a decision rule the executor's likeliest "fix" is re-ignoring the publish result — the exact bug this plan closes.
- **B2.** Fix Done :224 by ONE of: (preferred) move target pending-broadcast cleanup into `leaveGroup`'s success path so every caller inherits it, or reword :224 to the migrated surfaces only. *Why:* as written it is false — bare-leave surfaces (`orbit_wired.dart:2814`, `group_list_wired.dart:785`) and the four remote-initiated exits in `group_message_listener.dart` (:3820, :3974, :4077, :4570 — audit-verified) still orphan rows, which repush retries on every drain forever (no group-missing guard).
- **B3.** Scope Done :223 / Do-not :76 ("never a second publish/leave") to **in-session** behavior and add an accepted-difference line for the crash-after-native-success case. *Why:* `leftCleanupIncomplete` is a session-scoped return value; a durable confirmed-native-leave marker would need the schema change :79 forbids — as written the criterion is unenforceable and invites false sign-off.
- **B4.** One-line parity fix while editing `orbit_wired.dart` anyway: give `_onLeaveStuckGroup`'s catch (`:2820-2825`) the same `group_info_leave_failed` snackbar the Group List sibling shows. *Why:* the deferred stuck-row surface otherwise keeps a silent sole-admin failure — the exact UX sin this plan exists to fix, one line away.

## §C — Queue-contract tightening (material)

- **C1.** TC-07 must assert the enqueued `member_role_updated` row round-trips through the real `GroupPendingBroadcast` model with **non-empty `recipientPeerIds`** (plus kind/sysText/eventAt). *Why:* repush silently skips the inbox leg and clears on publish alone when recipients are empty (`group_pending_broadcast_repush.dart:49`) — degrading the exact publish+inbox invariant TC-07 enforces, and host fakes will mirror the bug.
- **C2.** TC-06/TC-07 unlock condition: assert **the row is gone**, never drain return-counts, and do not assert FIFO-across-failures (load-order only). *Why:* no drain mutex; resume `drainAll` fires unawaited — a concurrent drain can clear the row mid-Retry and return 0 from the awaited `drainForGroup`.

## §D — Slicing (material, D2)

- **D1.** Insert an early slice between steps 3 and 4: wire step-2 policy's sole-admin disposition to the recovery sheet in **guidance + Dissolve-only** mode (promotion hidden/disabled with localized "not yet available" copy), reusing the unchanged `dissolveGroup`; make TC-05 and TC-12's Orbit dissolve wiring green here. *Why:* the user-visible fix currently lands at step 7 behind both risky extractions; if step 4/5 stalls (promotion reordering is the likeliest stall), the branch dies with zero user-visible improvement despite this slice being independently shippable.

## §E — Trims & cuts (over-engineering; recommended, non-gating except E1)

- **E1. CUT** step 6's "or add one narrowly named helper in the same file" option; harden `deleteGroupAndMessages` in place. *Why:* the helper branch leaves `group_info_wired.dart:728` on the live fall-through (`delete_group_and_messages_use_case.dart:23-34`) while TC-13 greens against the helper — pure divergence risk at identical cost. (Gating: this is a correctness fork, not just fat.)
- **E2. TRIM** TC-06: collapse pending-drain/failed-drain into one blocked "promotion syncing" state; drop exact per-state callback/command counters; keep blocked-while-row-exists, unlocked-when-row-cleared, promotion-invoked-once, and the drain-don't-repromote mutation. Spend the savings on one dispose/re-pump case proving Continue stays blocked from the durable row after the sheet is rebuilt.
- **E3. TRIM** TC-08 into TC-11: keep its two unique guards (zero destructive sibling calls on a gone-stale candidate; no leave-from-`finally`), drop the duplicated Continue-disabled assertions.
- **E4. TRIM** TC-02 to three representative exclusion fixtures (never-accepted, stale-before-removal, admin-add/`joinedAt`-only) + the trust-roster-presence mutation; add the A6 positive fixture.
- **E5. TRIM** TC-15: semantics/roles/RTL/back stay pass-fail; demote 200% text-scale and focus-order to best-effort assertions in the same test.

## §F — Bookkeeping (nits, fold into step 1)

- **F1.** Re-anchor drifted citations during the step-1 dirty-diff snapshot: stale gate `update_group_member_role_use_case.dart:166-188` (not :137-180); `callGroupPublish` `bridge_group_helpers.dart:305-413`; `_onDeleteGroup` ends :2780. Prefer symbol anchors over line spans.
- **F2.** Fix RED-evidence wording: Done :215 must except TC-04 (sentinel-only by design); relabel TC-05/06/13/15 as compile-RED-then-assertion-RED (new files/types cannot produce assertion RED first).
- **F3.** Keep the canonical-event match check in step 4 as a free assertion but do not write a test for its failure branch — it is unreachable on success paths (verified: non-stale `eventAt` passes through unchanged).

## Priority order to apply

1. **B1 + OPEN decision** (product behavior change must be decided before step 5), **E1** (correctness fork), **B2** (false done criterion / forever-retry orphans).
2. **A1, A3, A4** (the three gates that currently cannot fail), **C1, C2** (queue contract trapdoors).
3. **D1** (early shippable slice), **B3, B4, A5, A6**.
4. **E2-E5** trims, **F1-F3** bookkeeping.
