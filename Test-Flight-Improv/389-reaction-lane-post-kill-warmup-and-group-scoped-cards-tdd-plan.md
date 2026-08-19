# 389 - Reaction lane: a post-kill warm-up the graded assertions can survive

Status: **EXECUTED (host tier) 2026-08-19** — all ten host rows green, 6 causal REDs recorded against HEAD in a worktree, 7/7 mutations re-red, `lib/` diff empty. **Device tier (TC-389-11) pending** — see Execution Progress.
Type: Bug
Spec: free-text intent (no formal spec) — gap **G11** of `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md` §4.8, taken from Plan 386's `Residual And Handoff`
Classification: implementation-ready
Closure tier: device

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-19 | Evidence Collector | 386's `Residual And Handoff`, the criteria + capture drivers, 386's blocked-run capture | 386 is EXECUTED; capture-side dispatch already centralized; six suffix tests remain in the validator half | verify→refute |
| 2026-08-19 | Planner (wf_02989606-172, 10 agents) | + `group_reaction_e2e_probe.dart`, `send_group_reaction_use_case.dart`, `opaque_wake.go`, `HeadlessCanonicalRecoveryWorker.kt`, the muted captures | Both of 386's ruled-out alternatives are wrong; the generic refactor is over-engineering | write plan |
| 2026-08-19 | Reviewer (wf_5876555f-52c, 3 workers + lead source verification) | + `_expectExactKeys` sites, `_validateNotificationRaw` control flow, `_createAndAcceptGroup`, the four muted-REACTION captures | **Core bet CONFIRMED; the Test Contract was not.** ~12 findings; the widening design accepted artifacts HEAD rejects | apply deltas (this document) |

## Problem And Evidence

- **Behavior to improve:** two device scenarios — `android_group_reaction_recipient` and `android_announcement_reaction_recipient` — cannot be run to completion. The killed recipient's first FCM wake exhausts the 2s `display_eligibility` budget (G21), no card is posted, and the lane has no way to warm the isolate first because its graded assertions forbid the only warm-up it can send.
- **Impact:** the reaction lane's headline author-alert legs have **no current device evidence**. Plan 386 closed ten of eleven rows and left TC-386-11 at 3/5. Plan 388's TC-388-13 re-runs one of these two and inherits the block.

### Confirmed root cause / current gap

A post-kill warm-up text into a second group trips these, in the order they fire. Verified at HEAD `0687c251e`:

1. **`_waitForNotificationCard()` requires exactly one active notification record across the whole app package** — `capture:4338-4348`, count at `:4345`, package-only filter at `reaction_notification_proof_support.dart:6467`. Its predicate returns `null` rather than failing, so a foreign card makes it **hang for two minutes**, not fail. **Four** call sites: `:2284`/`:2297` (message lane — must not change) and `:2634`/`:2665` (reaction lane).
2. **`_validateNotificationRaw` rejects any block that does not hold exactly one content card** — `criteria:2847-2851`. **This is the primary HEAD failure**, emitted twice as `$.evidence[android_notification_records] has malformed raw card`.
3. **Because `:2851` `continue`s before `cards.add(...)` at `:2861`, three downstream checks pass vacuously today**: the replacement-identity check at `:2863` (guarded by `cards.length == 2`), the "New Message copy" check at `:2869-2877`, and the title/body equality at `:2878-2888`. `:2878` is therefore **not** the primary gate — it is the guard that becomes operative once the count check is widened. (An earlier draft called it "the unavoidable one"; that was wrong.)
4. **`_validateUiRaw` scans every UI block for the bare substring `'unread message'` with no group qualifier** — `criteria:2950-2954`. The Orbit row label is `'Open group $groupName, N unread message(s)'` (`capture:4302-4306`).

**Only `:2878` sits inside the `!messageScenario` arm.** `messageScenario` at `criteria:2822-2831` selects only the two evidence **file names**; everything from `:2832` to `:2877` — including the per-block count and the New Message check — is **shared with the message branch**. Any widening there must be made under an explicit `messageScenario ? <today's package-wide form> : <graded form>` selector or it silently relaxes the three scenarios that already pass.

### Two hard constraints on any new rule

- **The measurements map is exact-keyed.** `criteria:1377-1390` `_expectExactKeys(measurements, {appPackage, groupName, actorName, firstMarker, secondMarker, targetMarker, expectedRelayWakeAttempts})`. Adding a measurement key fails every artifact. There are 14 `_expectExactKeys` sites in the file.
- **Evidence kinds are catalog-declared.** `criteria:1277-1296` builds `requiredByKind` from each scenario's `evidenceRequirements` and rejects any record whose kind is not declared. A new evidence file is blocked without a catalog edit.

So the warm-up rule must be derived from an **already-declared** evidence kind — `recipient_app` — and may add neither a measurement key nor an evidence kind.

### Three corrections to Plan 386's handoff, all source-verified

- **`capture:2593` is not the authorship line.** It is a Plan-330 media-receipt file write. The authorship is `capture:2611` — `await _sendGroupText(recipientId, _targetMarker);`.
- **`unread=0,0,0`, `orbit_indicators=0` and `unread_after_tap=0` are read by no validator.** `EvidenceRequirement.markers` has exactly one consumer in the repo — the host fixture builder's `markerOnly` synthesis (`test/integration/group_reaction_notification_device_criteria_test.dart:1207`, used at `:720`/`:738`). The identical strings in `integration_test/one_to_one_reaction_notification_proof_test.dart:204-250` are that lane's own hard-coded literals, not a consumer of this field. **Re-scoping those strings gates nothing.**
- **A warm-up MESSAGE cannot move `expectedRelayWakeAttempts`.** `_relayWakeAttemptsSince` reads `relay_group_reaction_wake_total{outcome="attempted"}` (`capture:4769-4779`), a reaction-only family.

### Refuted findings (do NOT re-introduce)

- **"Only an incoming group MESSAGE can wake the killed recipient."** False. `_runAndroidMutedReactionBackgroundLifecycle` (`capture:3552-3665`) already kills the recipient (`:3584`), sends a throwaway text into a **different** group (`:3610-3612`), and grades reactions with group-scoped selectors.
- **"A warm-up REACTION cannot work because a non-author is never nominated."** The mechanism is wrong: `_reactionRecipientsFromMembers` nominates the **target message's author** (`send_group_reaction_use_case.dart:1291-1338`), and the recipient authors the target (`capture:2611`). The plan still uses a text warm-up, because a reaction warm-up would move the reaction-only counters.
- **"Warming the install avoids the deferral."** All three scenarios in the blocked run shared one install, the recipient cold-started five more times inside the blocked scenario, and no scenario log holds a `PackageInstaller`/`installd`/`dexopt` line. `ProfileInstaller` still fires **on the wake process** at +0.247 s and the deferral still lands at +2.388 s. Warmth is **per-process** — `capture:3589-3609` says so in a measured source comment.
- **"A non-message wake could warm without a card."** The fixed opaque wake's capability is set by no build config, selection is **per-route** (`inbox.go:280-288`) so enabling it would make the *graded* pushes content-free, and its warm path posts its own package-scoped cards.
- **"The fix is a declarative per-scenario expectation refactor."** Refuted as scope: the true suffix surface is **18 live sites across 5 files** (criteria 7, capture 4, host fixture 5, muted host test 1, shipped probe 1), including `capture:2141-2143` (decides who creates the group) and shipped app code at `lib/core/debug/group_reaction_e2e_probe.dart:107`.
- **"Every widening is inside the `!messageScenario` arm."** Refuted — only `:2878` is. See above.
- **"The second group can be created after the kill."** Refuted. For both blocked ids the creator is the **recipient** (`capture:2141-2143`), `_createAndAcceptGroup` immediately calls `_launchAndroid(creator.deviceId)` (`:2146`) and runs a 3-minute invite/accept round trip (`:2184-2202`). Either role assignment relaunches a process the lane just killed. The muted lane does **not** do this either: it creates both groups in `group_fixture_setup` (`capture:747-756`) and only the **send** is post-kill.

### The #1 bet, verified — with the citation corrected

**A post-kill warm-up leaves a resident background isolate that still serves the graded push.** The evidence is four **muted-REACTION** captures on the pinned Pixel, each with one resident pid serving the warm-up plus both graded pushes: pids 22904 / 26742 / 9897 / 3244 across gaps of 114 / 57 / 57 / 57 s.

An earlier draft cited "pid 24955, 44 s". That capture is `android_group_text_killed_app_card`, a **TEXT→TEXT** lane with no negative arm, and its "zero storage deferrals" is true only of the literal string — the same log carries three `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED`, a structurally different non-fatal branch (`handler:1102-1109` vs `:724-731`). Do not cite it as an A/B.

**Measured gaps for this lane:** in the blocked run the kill lands 14:15:05.407 and the graded reaction is received 14:15:24.952 — **19.5 s**. The binding constraint is the *second* graded push: warm-up → replacement card is roughly **40–55 s**, inside the 57–114 s the pinned Pixel has already held a resident isolate.

### The discriminator, newly measured

Putting the blocked reaction cold wake beside a passing group-text cold wake on the same Pixel, same install, same debug APK: the difference is **where the Go-runtime dlopen lands relative to the phase start**. Reaction (deferred): ProfileInstaller +0.19 s, `libgojni` +1.09 s, SQLCipher keying +1.46 s, store read +2.05 s, deferral +2.33 s — the dlopen sits **inside** the `display_eligibility` window. Text (passed): the expensive work lands earlier, outside the graded phase.

**The trip is intermittent.** The reaction lane tripped once (blocked run, 08-19 12:15, `display_eligibility`, +2.388 s), but four cold first-wakes-after-kill on the same pinned Pixel did **not** trip. "Remove the warm-up and it comes back" is therefore not a sound mutation — see TC-389-11.

### Existing coverage

- `_mutedAttributableCards(dump, {required String groupName})` (`capture:3029`) is the group-scoped card selector. It depends only on `appPackage` and is reusable as-is. **15 call sites** at HEAD (`:3048`, `:3089`, `:3116`, `:3169`, `:3536`, `:3641`, `:3713`, `:3717`, `:3746`, `:3751`, `:3906`, `:3911`, `:4009`, `:4029`, `:4036`).
- `_waitForRecipientStorageWarm()` (`capture:3150-3155`) waits for `GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS`; its doc states the warm-up's own outcome is deliberately **not** graded, only that it paid the cold cost. This is the correct warm-up oracle.
- `_waitForGroupNotificationBodyChange(group, [staleBodies])` (used at `capture:3630-3637`) is the muted lane's card-grading pattern: a body-change wait with stale-body exclusion, which is what proves an in-window arrival rather than re-observing an earlier card.
- `_requireCleanNotificationSlate()` (`capture:4652-4664`) requires **zero** app records and runs at `capture:772` of every scenario, with the comment "unrelated cards are never cancelled".
- Host homes: `test/integration/group_reaction_notification_device_criteria_test.dart` (the fixture builder, which imports the capture driver as `fixture_driver`) and `test/integration/group_muted_notification_criteria_test.dart` (which imports **only** the two criteria files).

### Missing coverage

No host row asserts that a warm-up-group card is tolerated while an *unrelated* extra card is still rejected, that the UI unread scan is group-qualified, or that the graded reaction is not the first wake. All are new.

### Affected production / test / gate files

- `integration_test/scripts/capture_group_reaction_notification_device.dart`
- `integration_test/scripts/group_reaction_notification_device_criteria.dart`
- `test/integration/group_reaction_notification_device_criteria_test.dart`
- **No `lib/` change. No new file. No new scenario id. No new measurement key. No new evidence kind.**

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `aa8e807a0d9f407b`, `stale:integration_test/scripts/notification_android_payload_campaign.dart`. **Not usable for line-level work on this surface** — it resolves "none" for caller/bypass candidates and its anchors drift (`_waitForRecipientStorageWarm` anchored at `:3098`, real line `:3150`).
- Query / profile: `--profile tdd --budget 700` for planning, `--profile review --budget 800` for the audit; both `confidence=anchored` on symbol anchors only.
- Anchors: `_mutedAttributableCards` → `capture:3029`; `groupReactionNotificationExpectedAndroidReactionBody` → `criteria:35`.
- Graph gaps that required raw source search: all of `integration_test/scripts/`, `scripts/**/*.sh`, `lib/core/debug/`, and the on-disk device captures.
- Reuse rule: anchors are search starting points; every line here was read in current source or a device artifact.

## Scope Contract And Guard

**In scope:**
- A **second group created in `group_fixture_setup`** (a new branch beside `capture:747-756`), with `_groupName` restored to the graded group exactly as `:746`/`:756` do.
- A **post-kill throwaway text send** into that second group inside `_runAndroidReactionLifecycle`, modelled on `capture:3610-3614`, gated on `_waitForBackgroundPushWakes(1)` then `_waitForRecipientStorageWarm()` then the settle delay.
- Widening four graded assertions to an **allow-list of exactly {graded group, warm-up group}**, under an explicit `messageScenario` selector so the message branch keeps today's package-wide form.
- A validator rule that machine-enforces the warm-up, derived from the already-declared `recipient_app` evidence kind.

**Must preserve:**
- The three scenarios that passed in 386's run → TC-389-08.
- The message branch's package-wide card contract → TC-389-06 (its mutation is the guard).
- The shipped-app probe's fail-closed contract and an empty `lib/` diff → TC-389-09.
- Discovery classification and the device contract census → TC-389-10.

**Hard `Do not`:**
- **Do not add a scenario id, a measurement key, or an evidence kind.** `criteria:1377-1390` exact-keys the measurements; `criteria:1277-1296` rejects undeclared evidence kinds. Seven id-registration surfaces exist, three dangerous: `lib/core/debug/group_reaction_e2e_probe.dart:19-40` is a shipped-app allow-list with **no host census** (its absence throws on the phone at `capture:5050`); `integration_test/group_announcement_reaction_notification_proof_test.dart:16-45` is one `test()` per id, `@Tags(['device'])`, and a missing block exits 79 *after* the validator already accepted; and discovery fails closed.
- **Do not create a new file under `integration_test/scripts/`.** `check_reliability_simulation_discovery.sh:719` finds every file there and routes unruled paths to `record "unclassified"` (`:713`), failing at `:1233-1234`.
- **Do not touch `lib/`.** `group_reaction_e2e_probe.dart:107` gates marker shape on the id suffix and is fail-closed.
- **Do not change `_waitForNotificationCard()`'s call sites `:2284`/`:2297`** — they are the message lane.
- **Do not widen `criteria:2843-2852` or `:2869-2877` unconditionally.** They are shared with the message branch.
- **Do not re-scope `unread=0,0,0`, `orbit_indicators=0` or `unread_after_tap=0`.** No validator reads them.
- **Do not use a same-group warm-up**, and do not attempt the generic 18-site suffix refactor here.

**Deferred / accepted difference:**
- **The full G11 structural fix — 18 live suffix sites across 5 files** → owner: unowned, costed above. Two of the six criteria sites (`:1928`, `:1967`) are the byte-identical predicate `!id.endsWith(...) && !processAliveReaction`; three more are already expressible with the two fields `GroupReactionCaptureDispatch` carries. The natural home is `GroupReactionNotificationScenario` (`criteria:222-246`). Not needed here.
- **A 1:1 warm-up helper** → owner: unowned. None exists in the 6492-line capture driver; `_prepopulateAndroidContacts` (`capture:2107-2132`) is the only prerequisite already in place.
- **`_mutedAttributableCards` has no host-tier mutation cover** — it is a private instance method of the capture driver, so no host test can red on its behaviour. Accepted; TC-389-06's guard is the criteria-side selector instead.
- **Accepted difference:** the warm-up's card stays in the package dump for the run. It is admitted by the allow-list, not dismissed.

**Dependencies:**
- **Plan 386 is EXECUTED**; this plan is its named residual.
- **Plan 388 is in flight.** File sets are disjoint, but the two also share the `build/sims/cache/android.production_fcm` APK slot, which `docker-ws/run_reaction_scenario_386.sh:24` selects **by mtime**, and 388 owns the `PUSH_BACKGROUND_STORAGE_DEFERRED` emitter this plan's TC-389-07 rule reads. Serialize the device work and re-read the emitter's field set before writing the rule.
- Plan 388's TC-388-13 consumes this plan's outcome.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.
Rows were renumbered by review; the pre-review contract had 9 rows and two of its mutations were unbuildable.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| **TC-389-01** | A warm-up-group card in the same dump block as the graded card does not red the artifact | `group_reaction_notification_device_criteria_test.dart::'a warm-up-group card alongside the graded card validates'` | integration host / **one block carrying two records**: graded title + warm-up title | causal RED — `criteria:2847-2851` emits `$.evidence[android_notification_records] has malformed raw card` **once per block**, and `continue`s before `cards.add` → the artifact is rejected for the count, never the title | revert the per-block count to the package-wide form → TC-389-01 red | `flutter test test/integration/group_reaction_notification_device_criteria_test.dart`; host-all-only → direct command; auto-classified at `run_test_gates.sh:1526-1529` |
| **TC-389-02** | The replacement-identity guard stays reachable: an artifact whose second block holds no graded card is rejected | `…::'a replacement block without a graded card is rejected'` | integration host / block 1 = graded + warm-up, block 2 = warm-up only | causal RED against the **naive** widening ("at least one graded card across the accumulated list") — that shape leaves `cards.length == 1`, so `criteria:2863`'s `cards.length == 2` guard never fires and an artifact proving the lane posted one card and never replaced it VALIDATES, while HEAD rejects it | widen to "at least one across the accumulated list" instead of **exactly one graded card per block** → TC-389-02 red | same command; AUTO (glob) |
| **TC-389-03** | The allow-list is closed: an extra app card outside {graded group, warm-up group} is still rejected | `…::'an app card outside the graded and warm-up groups is rejected'` | integration host / block carrying graded + warm-up + one foreign-titled card | causal RED against a widening that merely *excludes* the warm-up group (it would accept any third card) → the artifact is rejected with a named failure | drop the warm-up group from the allow-list and accept any non-graded card → TC-389-03 red | same command; AUTO (glob) |
| **TC-389-04** | The graded card is still pinned exactly: a graded-group card with the wrong body reds | `…::'a graded-group card with the wrong body still reds'` | integration host / graded-title card carrying message copy | causal RED after the widening lands (before it, `:2878` never evaluates — see root cause item 3) → an artifact whose graded card body is not `groupReactionNotificationExpectedAndroidReactionBody(actorName)` is rejected | relax `:2878` from equality over graded cards to `cards.any(...)` → TC-389-04 red | same command; AUTO (glob) |
| **TC-389-05** | The UI unread scan is group-qualified by one whole-label match, not two independent scans | `…::'unread semantics are graded per group'` | integration host / **one** block containing BOTH Orbit labels as sibling nodes (on device they share one `<hierarchy>`) | causal RED (`criteria:2950-2954` matches the bare substring in any block) → the warm-up group's badge passes, the graded group's reds | implement the qualifier as `block.contains('Open group $groupName') && block.contains('unread message')` — two independent scans → TC-389-05 red on the single-block fixture | same command; AUTO (glob) |
| **TC-389-06** | The message branch keeps today's package-wide card contract | `…::'the message branch still rejects a foreign card'` | integration host / message-scenario artifact with graded + foreign card | GREEN sentinel (passes today; the message branch rejects it) → still passes after the widening, because `:2843-2852` and `:2869-2877` are widened under an explicit `messageScenario ?` selector | apply the graded-group form unconditionally (drop the selector) → TC-389-06 red | same command; AUTO (glob) |
| **TC-389-07** | The warm-up is machine-enforced: an artifact whose graded reaction is among the first two post-kill wakes is rejected | `…::'the graded reaction may not ride the first post-kill wake'` | integration host / `recipient_app` fixtures with 2 wakes and with 3 wakes | causal RED (no such rule exists) → an artifact with **fewer than three** post-kill `PUSH_BACKGROUND_MESSAGE_RECEIVED` entries is rejected; three or more passes | port 379/384's `>= 2` / `graded != received.first` form → TC-389-07 red, because the lane already emits two post-kill wakes with no warm-up (ADD + re-ADD; `expectedRelayWakeAttempts` is pinned to 2 and the capture waits for attempts 1 then 2 at `capture:2632`/`:2663`) | same command; AUTO (glob) |
| **TC-389-08** | The three device-passing scenarios keep passing at host tier | existing rows for `android_group_message_unread_lifecycle`, `android_announcement_message_unread_lifecycle`, `android_group_reaction_recipient_background_connected` | integration host / existing fixture builder | GREEN sentinel (passes today) → still passes | remove the `messageScenario` selector from the count widening → TC-389-08 red alongside TC-389-06 | same command; AUTO (glob) |
| **TC-389-09** | The shipped app is untouched and its probe contract holds | `test/core/debug/group_reaction_e2e_probe_test.dart` + `git diff --name-only -- lib/` | unit host / existing tests | GREEN sentinel (passes today) → still passes with an empty `lib/` diff | edit `group_reaction_e2e_probe.dart:107`'s suffix gate → the probe test reds and the diff is non-empty | `flutter test test/core/debug/group_reaction_e2e_probe_test.dart`; `git diff --name-only -- lib/` expect empty; AUTO (`test/core/**`) |
| **TC-389-10** | Discovery and the device contract census are unchanged | `./scripts/check_reliability_simulation_discovery.sh` + `scripts/test/group_reaction_notification_device_contract_test.sh` | host shell / real repo tree | GREEN sentinel (passes today) → still passes; no file added, no id changed | add any new file under `integration_test/scripts/` → discovery reds at `:1233-1234` | `./scripts/check_reliability_simulation_discovery.sh` (exit 0); `/claude-host-bin/host-run bash scripts/test/group_reaction_notification_device_contract_test.sh` (exit 0 — **in-container it reds at `:65` on a host-bridge path artifact**) |
| **TC-389-11** | On the real pair, both blocked scenarios reach their graded card, and the artifact proves the resident-isolate mechanism rather than luck | device runs of `--scenario android_group_reaction_recipient` and `--scenario android_announcement_reaction_recipient` | device proof / recipient = physical `21071FDF600CSC`, sender = `emulator-5554`, real relay, `android.production_fcm` | manual/device-only proof (both fail today: no card, deferral at +2.388 s) → each writes a validating artifact, and TC-389-07's `>= 3` wake rule plus a **same-pid** assertion (the graded pushes' flow lines carry the pid the warm-up forked) are what prove the mechanism | delete the warm-up **send** and re-run → TC-389-07's wake-count rule reds deterministically. Do **not** rely on "the deferral returns": the trip is intermittent — four cold first-wakes on the same Pixel did not trip it | `/claude-host-bin/host-run bash docker-ws/run_reaction_scenario_386.sh <id>` per scenario, then `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.reaction_notification_campaign`; existing registration, no new entry |

### Test Notes

- **TC-389-01 and TC-389-02 must use different fixtures.** The pre-review draft specified the foreign card in *both* blocks; that fixture never reaches `:2878` because `:2851` `continue`s on the count, so it cannot prove what the row claimed. TC-389-01 exercises the count in one block; TC-389-02 removes the graded card from block 2 to keep the replacement-identity guard reachable.
- **The correct widening shape is "exactly one graded-group content card per block", not "at least one across the accumulated list".** `criteria:2863`'s replacement-identity check is guarded by `cards.length == 2`; an accumulated-list shape can leave it at 1 and silently skip it.
- **TC-389-05's fixture must put both Orbit labels in ONE block.** On device they are sibling nodes of one `<hierarchy>`. A two-block fixture lets the most likely wrong qualifier — two independent `contains` on the same block — pass at host and red on device. The qualifier must be one regex over the whole label: `Open group <graded>, \d+ unread message`.
- **TC-389-07 cannot be identity-bound.** The graded reaction push's flow event carries `details: {'kind': 'group_reaction'}` with no `messageId`, so no rule can bind a specific wake to the graded reaction from `recipient_app` alone. The rule is therefore **cardinal** (`>= 3` post-kill wakes) plus the device-tier same-pid assertion in TC-389-11. Say this rather than implying an identity binding.
- **Warm-up gating.** Model `capture:3610-3614` exactly: send, then `_waitForBackgroundPushWakes(1)`, then `_waitForRecipientStorageWarm()` (which waits for `GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS`, `capture:3150-3158`), then the settle delay. Do **not** gate on a notification disposition — the warm-up's own outcome is deliberately not graded.
- **`_groupName` must be restored.** `_createAndAcceptGroup` overwrites it unconditionally (`capture:2136`); both existing two-group lanes restore it (`:746`, `:756`).
- **Cross-scenario slate hazard.** `_requireCleanNotificationSlate()` (`capture:4652-4664`) requires **zero** app records and runs at `:772` of every scenario, and `_dismissNotificationCard()` is called only in the message lane (`:2288`). Confirm on the first device run whether the warm-up card survives into the next catalog scenario; if it does, dismiss it at the end of the lane. The muted lane never hit this because it is out-of-catalog.
- **The probe's global badge fields change.** A second group moves `group_reaction_e2e_probe.dart:355-364`'s global counters. The reaction validator does not read them today and must not start.

## Implementation Steps

1. Snapshot `git status --short` and `git log --oneline -5`. **Stop-if** `integration_test/scripts/` or `test/integration/group_reaction_*` is dirty. Plan 388's files are expected to be dirty and are **not** a stop-if. Add TC-389-01…05 and 07 as REDs and confirm TC-389-06, 08, 09, 10 green before any capture edit.
2. **Criteria widenings**, each under an explicit `messageScenario ? <today's form> : <graded form>` selector:
   - `:2843-2852` — count content cards attributed to the **allow-list** {graded group, warm-up group}, requiring exactly one **graded** card per block.
   - `:2869-2877` — scope the "New Message copy" check to graded-group cards; a warm-up text card legitimately carries that copy.
   - `:2878-2888` — keep the equality, applied to graded-group cards.
   - `:2950-2954` — qualify by one whole-label regex on the graded group.
   - Add the `>= 3` post-kill wake rule, derived from `recipient_app`.
   - **Stop-if:** the rule needs a new measurement key or evidence kind (`criteria:1377-1390`, `:1277-1296`) → replan.
3. **Capture edits**:
   - create the warm-up group in `group_fixture_setup`, in a new branch beside `capture:747-756`, and restore `_groupName` to the graded group;
   - inside `_runAndroidReactionLifecycle`, after the kill, send the throwaway text into the warm-up group and gate as in Test Notes;
   - switch **only** `:2634` and `:2665` to the group-scoped card wait; leave `:2284`/`:2297` alone.
   - **No new file, no new scenario id, no `lib/` edit.**
4. Run focused GREEN → sentinels → the device contract shell → the two isolated device runs → the full campaign.

## Risks And Blind Spots

- **The widening is a gate relaxation.** Three regressions would become invisible without TC-389-03's closed allow-list: a duplicate or leaked card in an unrelated conversation, a second card in the graded group, and a card posted by a path the lane does not exercise. TC-389-03 is the row that keeps them covered — it is not optional.
- **The naive widening breaks the replacement proof** → TC-389-02.
- **A host-green wrong qualifier that reds on device** → TC-389-05's single-block fixture.
- **A ported wake rule that passes with no warm-up** → TC-389-07's `>= 3`.
- **The device row proving luck rather than mechanism** → TC-389-11's same-pid assertion; the "deferral returns" mutation is explicitly rejected as non-deterministic.
- **Lifecycle / derived-state durability:** N/A — no persisted state changes. The warm-up's message row lives in a different group and is never asserted on.
- **Sibling-surface consistency:** the four widened assertions are the parallel gates for one capability; the message branch is held by TC-389-06 and TC-389-08.
- **Destructive-action side effects:** the warm-up card is admitted, never dismissed — except possibly at end-of-lane for the slate hazard in Test Notes.
- **Invariant re-verification under new transitions:** the new post-kill send re-verifies what the pre-transition state justified — TC-389-07 (wake count) and TC-389-11 (same pid, graded card present).
- **Construction / call-site census:** re-derive at execution time. At HEAD: `_mutedAttributableCards` **15** call sites; `_waitForNotificationCard()` **4** (`:2284`, `:2297`, `:2634`, `:2665`); `_expectExactKeys` **14** sites in the criteria file; `_groupName` assigned at `:746`, `:756`, `:1322`, `:3403`, `:3934`, `:3949`, `:4066`. Never assert the fixed lists.
- **Build-artifact provenance:** no `lib/` change, so a stale APK is harmless for the code under test — but 388 and 389 share the `build/sims/cache/android.production_fcm` slot, selected **by mtime** (`run_reaction_scenario_386.sh:24`). Serialize the device work.
- **Permission / ACL verb symmetry:** N/A.
- **Fake side-effect fidelity:** the host fixtures are artifact maps fed to the real validator, so the production grading path runs unfaked. The hand-seeded foreign card is shown reachable by the production writer — the step-3 warm-up send is what produces it.
- **Composite-node / relationship assertions:** TC-389-01/04 bind title and body on the **same** card object; TC-389-05 binds the group name and the unread count in one label match.

## Gate Cadence

- **Per-plan closure:** six causal host rows, four sentinels, the device contract shell, and the two device scenarios.
- **Graph-affected first:** `python3 graphify-arch/tdd_context.py affected integration_test/scripts/group_reaction_notification_device_criteria.dart integration_test/scripts/capture_group_reaction_notification_device.dart --budget 600`, then `flutter test` the files it names — **hint only on this surface**; the graph resolves no caller candidates here.
- **Full `host-all` is not a per-plan gate.** Owned by the notification wave (383/384/385/386/388) and final rollout.
- **Shared tests outside the feature/core globs:** `test/integration/group_reaction_notification_device_criteria_test.dart` and `test/integration/group_muted_notification_criteria_test.dart` are host-all-only and get direct `flutter test <path>` commands.

## Acceptance Gates  (literal — copy/paste)

```bash
# Dirty-tree snapshot. Plan 388's files WILL be dirty; this plan's must not be.
git status --short
git status --short -- integration_test/scripts/ test/integration/group_reaction_ \
  test/integration/group_muted_     # expect: EMPTY before starting

# --- Causal REDs (before any capture edit) — each must FAIL for its documented reason ---
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'a warm-up-group card alongside the graded card validates'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'an app card outside the graded and warm-up groups is rejected'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'unread semantics are graded per group'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'the graded reaction may not ride the first post-kill wake'

# --- Focused GREEN (after the widenings) — exit 0, zero failures ---
flutter test test/integration/group_reaction_notification_device_criteria_test.dart

# --- Preservation sentinels — exit 0 ---
flutter test test/integration/group_muted_notification_criteria_test.dart
flutter test test/core/debug/group_reaction_e2e_probe_test.dart
git diff --name-only -- lib/                      # expect: EMPTY
git status --short -- integration_test/scripts/   # expect: exactly the two campaign files

# --- Graph-affected (hint only on this surface) ---
python3 graphify-arch/tdd_context.py affected \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart --budget 600

# --- Discovery + the device contract shell (host bridge only — in-container it reds at :65) ---
./scripts/check_reliability_simulation_discovery.sh    # expect: exit 0, 0 unclassified
/claude-host-bin/host-run bash scripts/test/group_reaction_notification_device_contract_test.sh
./scripts/run_test_gates.sh sims-contracts   # expect: 43 PASS / 1 FAIL, exit 1 — G28 is pre-existing (plan 387)

# --- Device: isolate each blocked scenario, then the full lane. Serialize against plan 388. ---
flutter devices --machine ; adb devices -l    # expect: 21071FDF600CSC + emulator-5554 both 'device'
/claude-host-bin/host-run bash docker-ws/run_reaction_scenario_386.sh android_group_reaction_recipient
/claude-host-bin/host-run bash docker-ws/run_reaction_scenario_386.sh android_announcement_reaction_recipient
.claude/skills/sims/scripts/run_with_devices.sh major --only groups.reaction_notification_campaign

# --- Hygiene ---
flutter analyze            # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria

- **Expected RED:** TC-389-01 fails with `$.evidence[android_notification_records] has malformed raw card` from `criteria:2847-2850` — **not** the title/body message, which never evaluates at HEAD. TC-389-03 and TC-389-05 fail on their own new assertions; TC-389-07 fails because no wake rule exists. TC-389-02 and TC-389-04 are written to red against the *wrong widening* and must be authored before it lands.
- **GREEN sentinel:** TC-389-06, 08, 09, 10.
- **Pre-existing dirty tree / known failure:** Plan 388's modified files are expected. `sims-contracts` exits 1 at contract #26 (**G28**, plan 387).
- **Environment blocker (NOT a product blocker):** the device pair or the `android.production_fcm` APK slot held by a Plan 388 run.
- **Scope drift (BLOCKING):** any `lib/` edit; a new file under `integration_test/scripts/`; a new scenario id, measurement key or evidence kind; an unconditional widening of `:2843-2852` or `:2869-2877`; any change to `_waitForNotificationCard()` at `:2284`/`:2297`.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded — including TC-389-02's kill of the accumulated-list widening and TC-389-07's kill of the ported `>= 2` rule.
- [ ] The allow-list is closed (TC-389-03), so the widening loses no leaked-card coverage.
- [ ] `git diff --name-only -- lib/` is empty and no file was added under `integration_test/scripts/`.
- [ ] Both blocked scenarios validate on device with `>= 3` post-kill wakes and the graded pushes served by the warm-up's pid.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.

## Device/Relay Proof Profile

- **Profile:** paired-device (os-notification-device-lab).
- **Boundary being proven:** that a post-kill warm-up leaves a resident background isolate which serves the graded reaction wake inside the 2 s `display_eligibility` budget. Unreachable at host tier — the budget is consumed by real cold-isolate first-touch, `libgojni` dlopen and SQLCipher keying.
- **Live availability check:** `adb devices -l` on 2026-08-19 → `21071FDF600CSC` (Pixel 6) and `emulator-5554`, both `device`.
- **Pinned targets:** recipient = physical `21071FDF600CSC`; sender = `emulator-5554` (`run_group_reaction_notification_sims.dart:236-240` passes `--sender <emulator> --recipient <physical>`). No iOS leg — GAP-N12.
- **Automation:** fully harness-driven; no user taps. The Pixel's secure keyguard must be unlocked for the uiautomator legs.
- **Closure role:** **required closure evidence.**
- **Residency margin:** the binding gap is warm-up → replacement card, roughly **40–55 s**. The pinned Pixel has held a resident background isolate across **57–114 s** in four muted-REACTION captures (pids 22904 / 26742 / 9897 / 3244). The margin is real but not large; if a run fails on the *second* graded push only, suspect isolate teardown, not the fix.
- **`FLUTTER_DEVICE_ID`:** host selector only.
- **Registration:** both scenarios are already registered end to end. This plan adds nothing.
- **Discovery command:** `.claude/skills/sims/scripts/run_with_devices.sh major --list`.
- **Closure command:** `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.reaction_notification_campaign` → 5 of 5 validate.
- **Deferred device work:** the 18-site suffix refactor; a 1:1 warm-up helper; iOS legs.

## Handoff

- **First causal RED command:** `flutter test test/integration/group_reaction_notification_device_criteria_test.dart --plain-name 'a warm-up-group card alongside the graded card validates'`
- **Preservation command:** `flutter test test/integration/group_muted_notification_criteria_test.dart`
- **Manual registration:** none. `test/integration/*_test.dart` is auto-classified at `run_test_gates.sh:1526-1529`.
- **Migration:** none.
- **Boundary closure:** `/claude-host-bin/host-run bash docker-ws/run_reaction_scenario_386.sh <id>` per scenario, then the full campaign.
- **Unresolved evidence:** whether the warm-up card survives into the next catalog scenario's `_requireCleanNotificationSlate()` (Test Notes); and whether the resident isolate holds the full 40–55 s to the replacement card in *this* lane — 57–114 s is proven for muted reactions, not for these two ids.

## Reviewer Findings (wf_5876555f-52c — 3 workers + lead source verification, 2026-08-19)

Verdict **plan-fixes-required**; core bet **CONFIRMED** and better supported than the draft argued. All deltas are applied above.

**Blockers closed (7):**
1. **The primary HEAD failure was misidentified.** `criteria:2851` `continue`s before `cards.add`, so `:2878-2888` never evaluates at HEAD and the draft's "unavoidable one" framing — and TC-389-01's documented RED reason — named a failure the fixture cannot produce. The real string is `has malformed raw card`.
2. **The draft's widening shape accepted artifacts HEAD rejects.** "At least one graded card across the accumulated list" leaves `cards.length == 1`, so `:2863`'s replacement-identity guard never fires. Changed to exactly one graded card **per block**, with TC-389-02 as its kill.
3. **The widenings are not all in the `!messageScenario` arm.** Only `:2878` is; `:2843-2852` and `:2869-2877` are shared, so the draft's own step-2 stop-if would have fired immediately. Now widened under an explicit selector, with TC-389-06 as the guard.
4. **The second group cannot be created after the kill.** The creator is the **recipient** for both ids and `_createAndAcceptGroup` calls `_launchAndroid(creator.deviceId)` plus a 3-minute accept round trip. Moved to `group_fixture_setup`, with the `_groupName` restore named.
5. **New rules cannot add a measurement key or an evidence kind.** `criteria:1377-1390` exact-keys the measurements; `:1277-1296` rejects undeclared kinds. TC-389-07 now derives from `recipient_app`.
6. **The ported wake rule was vacuous.** The lane already emits two post-kill wakes with no warm-up, so a `>= 2` rule passes at HEAD. Changed to `>= 3`.
7. **The device row had no discriminator.** No validator anywhere asserts on `PUSH_BACKGROUND_STORAGE_DEFERRED`, and the trip is intermittent, so "the deferral returns" is not a sound mutation. Replaced with the wake-count rule plus a same-pid assertion.

**Plan-fixes applied:** a new closed **allow-list** row (TC-389-03) recovers the leaked-card coverage the widening would otherwise lose; TC-389-05's fixture must be single-block because the two Orbit labels share one `<hierarchy>` on device; TC-389-06's original mutation was impossible (`_mutedAttributableCards` is a private capture-driver method the muted host test never imports) and is replaced, with the absence of host-tier cover stated honestly; the `_mutedAttributableCards` census is **15** call sites, not 6, and `_waitForNotificationCard()` has **4**, two of them the message lane; the #1-bet citation was the wrong capture (pid 24955 / 44 s is a TEXT→TEXT lane with no negative arm) and is replaced by four muted-REACTION captures with measured 57–114 s residency; the binding gap is **40–55 s**, measured, not hand-waved; TC-389-07 cannot be identity-bound because the reaction push's flow event carries no `messageId`; 388 and 389 also share the mtime-selected APK cache slot; and the `_requireCleanNotificationSlate` cross-scenario hazard is recorded as unresolved-verify.

**Confirmed sound and kept:** the four assertion sites and their line numbers; the 18-site suffix census; the "dead strings" correction (`EvidenceRequirement.markers` really has one consumer, `group_reaction_notification_device_criteria_test.dart:1207`); the muted precedent; the reaction-only relay counter; the group-scoped SQLCipher probe; and the 388/389 file-set disjointness.

## Deviations From The Plan As Written

Each is a deliberate departure with its reason. None widens scope; two were forced by real gates.

1. **The four widenings are three code sites.** Step 2 lists `:2869-2877` (the "New Message copy" scan) as its own widening. It needed no edit: for a reaction the loop now collects ONLY the graded card, so a warm-up TEXT card legitimately carrying that copy is never scanned. Scoping it by construction is stronger than a second `messageScenario` selector — there is no second place for the two forms to drift apart.
2. **The title disjunct at `:2878` was dropped, not kept.** After the widening `cards` holds only `title == groupName` cards, so `card.title != groupName` is unreachable. An unreachable disjunct in a proof gate reads as coverage it does not provide. The closed allow-list (TC-389-03) is what rejects a wrongly-titled card now; the body equality (TC-389-04) is what pins the graded copy.
3. **The warm-up group's name is a DIGEST, not a decoration of the graded name.** The plan fixed the constraint (no new measurement key) but not the shape. A prefix or suffix would make the warm-up group's Orbit row — `Open group <warm-up>, 1 unread message` — satisfy `contains('Open group <graded>')`, both in this file's raw UI checks and in `findSemanticNodeCenter`, whose fallback arm matches on containment (`reaction_notification_proof_support.dart:6062-6063`). `Warmup<sha256(graded)[0:12]>` has no substring relation in either direction, and stays unique per run because the graded name carries `microsecondsSinceEpoch`.
4. **The lane clears the recipient's log at the kill.** TC-389-07 says "post-kill wakes", but the artifact carries no cursor. Rather than rest the rule on an argument ("this lane takes no pre-kill push"), the capture clears at the kill exactly as the muted (`:3600`) and killed-text (`:3839`) lanes do. `_adb` intercepts a `logcat -c` and moves both the live-stream byte floor and the flow accumulator (`:6073-6079`), so `recipient_app` holds only post-kill lines by construction. **This forced an unplanned repin** — `group_reaction_notification_device_contract_test.sh:169` pins the clear-site count, 8 → 9, repinned with the reason and never weakened.
5. **The warm-up card is dismissed at the end of the lane, unconditionally and best-effort.** The plan left this as unresolved-verify. It is a real hazard, not a maybe: `AndroidAppStateGuard.prepareFreshInstall` runs `pm install -r` plus a `run-as rm -rf` of the private entries (`android_app_state_guard.dart:549-597`), and neither cancels a posted notification — while both blocked ids sit in the MIDDLE of the campaign catalog. Dismissal costs two adb calls. It is best-effort because every graded observation is already captured by then: failing a good run over housekeeping would cost more than the blocked slate it prevents.
6. **An eighth host row was added — the background-connected lane's exemption from the wake floor.** TC-389-07 names only the killed lanes, so nothing in the contract would have caught a floor wrongly applied to `android_group_reaction_recipient_background_connected` until the device campaign reached it. The row asserts both that its artifact validates and that its `recipient_app` carries no `PUSH_BACKGROUND_MESSAGE_RECEIVED` at all, so it cannot pass by accident.
7. **TC-389-06's extra card is the WARM-UP-titled one.** The plan's cell says "graded + foreign card", but a foreign-titled card is rejected by the reaction form too — that fixture cannot kill the mutation the row exists for. The test runs both sub-cases; mutation m5 confirms the warm-up-titled one is the kill.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
| 2026-08-19 | snapshot | - | `git status --short -- integration_test/scripts/ test/integration/group_reaction_ test/integration/group_muted_` → EMPTY | plan 388's Waves 1-2 committed first as `dbb46336e`, so the stop-if surface was clean | proceed | implement |
| 2026-08-19 | criteria + capture | `group_reaction_notification_device_criteria.dart`, `capture_group_reaction_notification_device.dart` | `flutter analyze` on both → no issues | one shared derivation `groupReactionNotificationWarmupGroupName`, the closed allow-list, the group-qualified unread regex, the `>= 3` wake floor, the warm-up group + post-kill send + group-scoped card waits | — | host tests |
| 2026-08-19 | focused GREEN | `group_reaction_notification_device_criteria_test.dart` | `flutter test test/integration/group_reaction_notification_device_criteria_test.dart` → **55/55** | 8 new rows (TC-389-01…07 plus the background-connected exemption) | — | causal RED |
| 2026-08-19 | **causal RED at HEAD** | — | `git worktree add build/plan389-head HEAD`, new test file + the pure derivation ONLY, then `flutter test` → **6 failures** | TC-389-01 `has malformed raw card` ×2 (exactly the documented reason); TC-389-02 rejected for the wrong reason; TC-389-03/05 on their own new assertions; **TC-389-04 proves the reviewer's finding #1** — `reaction title/body mismatch` never evaluates at HEAD; TC-389-07 with **0** wakes VALIDATES. TC-389-06 and the exemption row PASS at HEAD, as sentinels should | worktree, never a mutation-revert in the live checkout | mutations |
| 2026-08-19 | mutation matrix | — | 7 mutations applied in the same worktree, each re-red by exactly one row | m1 accumulated-list→01-02, m2 open allow-list→03, m3 relaxed body equality→04, m4 two independent scans→05, m5 drop the `messageScenario` selector→06, m6 ported `>= 2`→07, m7 no wake rule→07. **7/7** | m5 kills TC-389-06 only, NOT the TC-389-08 sentinels — their fixtures hold one graded card per block, which both forms accept. Recorded rather than claimed | gates |
| 2026-08-19 | sentinels | — | `flutter test` muted criteria + both probe suites → **85/85**; `git diff --name-only -- lib/` EMPTY; `git status --short -- integration_test/scripts/` = exactly the two campaign files | TC-389-08, 09 green | — | — |
| 2026-08-19 | graph-affected | — | `affected` named 3 host test files; the third (`group_reaction_notification_fixture_test.dart`) → 14/14 | no import-level dependent broke | — | — |
| 2026-08-19 | discovery + contract shell | `scripts/test/group_reaction_notification_device_contract_test.sh` | discovery exit 0; contract shell FAILED then PASSED | **unplanned repin:** the shell pins the capture driver's `logcat -c` sites at 8 and the post-kill clear makes 9. Repinned 8→9 with the reason, never weakened | TC-389-10 green | device |
| 2026-08-19 | hygiene | — | `flutter analyze` whole repo → no issues; `git diff --check` clean | — | — | — |
| 2026-08-19 | `sims-contracts` | — | `/claude-host-bin/host-run bash scripts/run_test_gates.sh sims-contracts --continue-on-failure` → **43 PASS / 1 FAIL, exit 1** | the single failure is #26 `run_claude_docker_update_contract_test.sh` = G28, plan 387's recorded baseline. **In-container this gate is not usable** — it reds 10 contracts on host-bridge path artifacts | matches the documented baseline | device |
| 2026-08-19 | device run 1 — **FAILED** | — | `run_reaction_scenario_386.sh android_group_reaction_recipient` → `CAPTURE_FAILED … orbit_surface_not_reached_on_emulator-5554` | both groups created (`TC257Group1787159432688379`, `Warmupc02c68a4a057`), target text sent, then the FIRST `_openGroup(senderId)` died — **before the kill and before the warm-up sent anything** | **structural find the plan did not predict:** accepting a group invite lands Orbit on the all-chats `Intros` filter, which EXCLUDES active group nodes (`capture:100-107`). With one group the lane never noticed; the second accept leaves the device there and `_ensureOrbit`'s `Open group <name>` probe finds nothing | route through the Inner Circle |
| 2026-08-19 | navigation fix | `capture_group_reaction_notification_device.dart` | `_ensureGradedGroupOrbitRow` + `_openGradedGroup`; five call sites routed; contract shell + 69 host tests still green | the muted and Plan-330 lanes already navigate this way — this is adopting their proven helper, not new machinery. Routed ONLY when a warm-up group exists, so the background-connected scenario keeps its single-group path | — | re-run |
| 2026-08-19 | **device run 2 — `android_group_reaction_recipient` VALID** | — | `VALID [TC-15/android_group_reaction_recipient]: authoritative artifact contract accepted` | **3** post-kill wakes; all three served by the **same pid 11332** (warm-up 19:22:50, graded ADD 19:23:26, re-ADD 19:23:51); a card SHOWN 3.1–5.6 s after each receipt; **zero** `PUSH_BACKGROUND_STORAGE_DEFERRED` in the window | blocked since plan 386 — now closed | announcement |
| 2026-08-19 | device run 3 — **FAILED** | — | `run_reaction_scenario_386.sh android_announcement_reaction_recipient` → `CAPTURE_FAILED … group_compose_marker_editorUnavailable_on_emulator-5554` | user-supplied screenshot: the emulator sat in `Warmup3d0cbd8e1760` carrying the **Announce** badge, with "Only admins can send messages in this group". Alice IS a member — the join row renders — so this is correct product behaviour, not a membership defect | **second structural find:** `_createAndAcceptGroup` inherited `scenario.groupType`, so the warm-up group was an ANNOUNCEMENT group whose admin is the creator — the recipient, the device this lane kills. The only device left to send the warm-up had no composer | make it a chat group |
| 2026-08-19 | warm-up group type | `capture_group_reaction_notification_device.dart` | `_createAndAcceptGroup({String? name, String? groupType})`, warm-up pinned to `'chat'`; contract shell + 69 host tests still green | the warm-up group's type proves nothing — it exists only to fork the recipient's background isolate | — | re-run |
| 2026-08-19 | **device run 4 — `android_announcement_reaction_recipient` VALID** | — | `VALID [TC-15/android_announcement_reaction_recipient]: authoritative artifact contract accepted` | **3** post-kill wakes; all three on the **same pid 17297** (19:38:52 / 19:39:49 / 19:40:13); **zero** storage deferrals. Warm-up → replacement gap **81.2 s**, vs **61.1 s** on the group run — both ABOVE the plan's 40–55 s estimate and inside the muted lane's measured 57–114 s residency band | **TC-389-11 closed for both blocked ids** | full campaign |
