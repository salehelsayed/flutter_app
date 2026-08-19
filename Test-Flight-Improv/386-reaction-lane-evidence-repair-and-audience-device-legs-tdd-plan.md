# 386 - Reaction-Lane Evidence Repair (G16 + G20) And The Provable Half Of The Audience Rule (G18)

Status: execution-ready
Type: Bug
Spec: free-text intent (no formal spec) — gaps G16/G20/G18 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md` §4.6
Classification: implementation-ready
Closure tier: device
Closes: G16, G20. **G18 closes only partially** — its headline non-author-bystander leg is not
provable on any existing lane and is deferred with a costed owner (see Scope Contract And Guard).

**G19 is not planned here — it is CLOSED.** Plan 384 landed at `cbf71cde9`
("null-guard the group parity sender clause (G19, device-closed)").

**Gate hygiene moved out.** The three stale sims-contract pins that were W0 of this plan are now
[387](387-sims-contract-stale-pin-hygiene-tdd-plan.md) — they share zero files, zero symbols and zero
tier with this work and need no device. Land 387 first so registration checks here can run.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-19 | Evidence Collector | map §4.6 rows G16/G18/G20, `group_reaction_notification_device_criteria.dart`, `capture_group_reaction_notification_device.dart`, `notification_android_payload_campaign.dart`, `go-relay-server/{inbox,wake_outcome,metrics,main}.go`, `group_message_listener*.dart`, PRD §6.5/AC-13 | Three mechanisms confirmed; 6 map claims corrected | 4-agent verify → 2-agent refute (wf_1e00049c-e09) |
| 2026-08-19 | Planner | `run_test_gates.sh`, the five sh contracts, `runtime_roots.json` | Capture-file blast radius enumerated | Emit plan |
| 2026-08-19 | Reviewer (wf_77341dcf-8b1, 4 workers) | the whole contract + all cited sources | **not-ready/replan on the evidence design** — the journal-substring oracle refuted 3 ways; 9 distinct blockers | Rebuild grading on relay counter deltas; all deltas applied below |

## Problem And Evidence

- **Behavior to improve:** two harness defects in the reaction catalog lane, plus the provable part of
  an untested PRD rule. None is a product bug; no `lib/` file changes.
  1. **G16 — the lane cannot run at all.** Every fresh capture dies on a 2-minute wait for relay log
     lines that v1.8.0 no longer emits.
  2. **G20 — its device evidence can silently under-report.** Single `adb logcat -d` reads, graded
     with exact counts and a positional index over a rotating ring.
  3. **G18 — PRD §6.5's audience rule has no device evidence,** and one of its two production gates is
     unpinned at every tier.
- **Impact:** G16 blocks five Android device scenarios outright; G20 means a green artifact is not
  currently trustworthy; G18's protected/replay twin can be deleted today without reddening anything.

### Confirmed root causes (each survived a refute pass and a 4-worker audit)

**G16 — dead relay grammar, client-side only.** Relay commit `8d86501e4` deleted every attributed
`[PUSH]` line; a census of `go-relay-server/` for the three v1.7 literals returns **zero hits**, and
the vocabulary is frozen by `push_permanent_error_closure_test.go:237-300` (an exact 35-site literal
map), so re-adding them relay-side is the known-wrong fix. Four client sites still grep the dead
grammar: `group_reaction_notification_device_criteria.dart:2160-2176` (Android `providerMarker`),
`:2447-2461` (iOS), `capture_group_reaction_notification_device.dart:5408-5411`
(`_providerSuccessMarker`, additionally bound to `recipient.peerPrefix` at `:4519-4523`, so it is
doubly dead), and `criteria:2141-2158` (the background-connected scenario also requires
`remote_type=group_reaction` on a `[GROUP_REACTION_WAKE]` line; v1.8.0's wake lines are bare
`outcome=<word>`).

**Why the exact provider-send count is broken — corrected by review.** The count reads 0 today for a
mundane reason: `_countProviderSends` greps a deleted marker bound to the recipient prefix. It is
*not* broken because wake-outcome admission makes the count variable — **that path cannot execute on
the build under test.** `kWakeOutcomeCoordinatorAdmissionEnabled` defaults false
(`lib/core/bridge/p2p_bridge_client.dart:844-847`), the opaque-wake and wake-outcome capabilities are
appended only when it is true (`:879-882`), and no build script anywhere sets
`MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR`. Relay admission requires **both** capabilities
(`wake_outcome.go:190-191`), so `dispatch.hasAdmission` is never true and `suppressImmediateWake`
never fires on the campaign APK. The debounce/zero-send behaviour is real code but unreachable here.
**Consequence: keep an exact count — just move it onto a surface that works.**

**G20 — unsound capture substrate.** `_readAndroidLogcat` (`capture:5788-5806`) is a one-shot
`adb logcat -d -v threadtime` with no `-T` and no cursor, whose retry predicate is `exitCode == 0`
only (`:5796`) — a rotated, empty-but-successful window is accepted and never retried.
`_collectBoundedLogs` (`:2811-2832`) takes exactly **one** such read per device after a fixed 10 s
delay; those two values become `sender_app`, `recipient_app` **and** `android_logcat` (`:5050-5091` —
`android_logcat` is literally the same `_recipientLogcat` sample, so two evidence kinds are one
observation). Graded on top of that single sample: positional selection
`observations[baselineOutcomeCount]` (`:4048-4057`), absolute-count waits in
`_waitForSenderEventCount` (`:4494-4509`), and exact upper bounds in the validator
(`criteria:2190-2201`, `:2375-2411`). The repo already bans this pattern in writing —
`test/integration/reaction_notification_proof_support_test.dart:151-155`: *"count > baseline is
therefore unsound as an arrival predicate and must not be reintroduced."* G20 is that rule being
violated where the rule's own test cannot reach.

**G18 — the audience rule, and what is actually provable.** Four production gates confirmed: 1:1
`_targetWasAuthoredByLocalRecipient`
(`lib/features/conversation/application/handle_incoming_reaction_use_case.dart:472-482`), group
custody `group_message_listener.dart:1241-1249`, protected adapter `:3636-3675` (self clause `:3648`,
author-only `:3651`), and the direct SHOW lane
`group_message_listener_reaction_ingress_processor.dart:414-526`. Host coverage of the *live* twin is
complete. Two things are not covered:
- **The protected/replay twin has no negative row at any tier.** Its only exercise seeds an
  author-owned target (`group_notification_visibility_staging_test.dart:616-620`, wired at `:803`), so
  deleting the author-only clause at `:3651` reds nothing today.
- **A non-author bystander showing zero cards has no device evidence,** and cannot get any on an
  existing lane (see Deferred).

**What IS device-provable: the self-reaction narrowing, at nomination.** For a group self-reaction
`notificationRecipients` is populated only when `reactorPeerId != targetAuthorPeerId`
(`send_group_reaction_use_case.dart:1314`), so an empty list is published; the relay replaces the wake
audience with it wholesale, returns on zero admissions, and logs
`[GROUP_REACTION_WAKE] outcome=no_wake_recipients` while incrementing
`relay_group_reaction_wake_total{outcome="no_wake_recipients"}`.

- **Existing coverage:** host audience pins `group_message_listener_test.dart:17159-17258`,
  `:16983`, `:17074`, `:17033`; `handle_incoming_reaction_use_case_test.dart:669` and `:547-598`;
  `send_group_reaction_use_case_test.dart:2220`. Plan 380 W0's repaired v1.8.0 predicate
  `relayJournalContainsAndroidProviderSend`
  (`integration_test/support/android_notification_payload_campaign.dart:136-158`) with three host pins
  (`test/integration/android_notification_payload_campaign_support_test.dart:383-441`, whose rejection
  list at `:401-417` is genuinely strong). The Plan-379 recipient-side accumulator (`capture:3288-3318`).
- **Missing coverage:** no client test asserts the v1.8.0 grammar for this lane; no graded selection
  is identity-bound; the protected twin has no negative row.
- **Refuted findings (do NOT re-introduce):**
  - *"A zero-card assertion on the reactor's device proves the non-author rule"* (the map's suggested
    "cheap partial proxy") — **refuted.** `send_group_reaction_use_case.dart:1307` excludes the
    reactor's own device from `replayRecipients`, so no event reaches it and no client gate runs. The
    assertion has **no re-redding mutation**. A second, independent kill also applies:
    `maySuppressAppVisibilityNotification` (`app_visibility_snapshot.dart:212-231`) suppresses on
    foreground state alone within `appVisibilityFreshnessWindowMs = 90000` (`:8`).
  - *"A device zero-card assertion proves the group self-reaction rule"* — **refuted.** No push is
    sent to anyone, so the zero card is entailed. The observable is the nomination decision.
  - *"Zero cards is the whole compliance oracle"* — **refuted.** Silent data delivery to non-authors
    is mandatory (PRD `:226`, `:229`, `:232`; AC-13 `:412`), so a bare zero-card assertion also passes
    for a member that never received the reaction.
  - *"The exact provider count is structurally unprovable"* (this plan's own first draft) —
    **refuted**, see above: the variable-count path is unreachable on the campaign build.
  - *"`[GROUP_REACTION_WAKE] outcome=dispatched` is emitted per attempted recipient before any
    admission decision"* (first draft) — **refuted.** It precedes the *suppress* decision, which is
    the substance, but three earlier per-recipient declines skip it entirely
    (`self_or_empty_skipped`, `route_error`, `incapable_skipped`), two of them emitting no journal
    line at all. An "at least one" rule cannot detect a silently declined recipient.
  - *"`group_multi_party_device_criteria.dart` contains zero notification-card assertions"* (first
    draft) — **refuted.** It carries charlie-scoped zero-notification-count assertions at
    `:10593-10597` and `:17285-17289`. The real reason that lane cannot carry the bystander proof is
    its topology (below), not its assertions.
  - *"`lib/features/chat/…` holds the 1:1 reaction gate"* (map G18 paths) — **refuted.** The
    directory does not exist; the file is `lib/features/conversation/…` at the same lines.
  - *"Only the 1:1 observer-of-a-self-reaction leg lacks a host pin"* (map G18) — **refuted.**
    `handle_incoming_reaction_use_case_test.dart:547-598` pins exactly that leg.
  - *"The G20 positional index grades only the emulator"* (map G20) — **refuted.** `_sendGroupText` is
    called on the **physical** device at `:2593`, `:3496` and `:3498`.
  - *"The reaction lane's registration wait is dead on v1.8.0"* — **refuted.** The Android path uses
    the recipient-boundary predicate (`capture:763` → `:4451-4459`). Only the iOS leg is dead
    (GAP-N12).
- **Unresolved findings:** emulator-5554's ring size in its **sender** role. The 2 MiB / ~1.6 MB-per-
  minute figures are prose measured on the same device in a *receiver* role
  (`notification_android_payload_campaign.dart:2381-2382`); no committed `logcat -g` output exists for
  either device. Step 6 measures and records both; no contract row depends on the number.
- **Affected files:** no `lib/` change, no `go-relay-server/` change.
  Harness: `capture_group_reaction_notification_device.dart`,
  `group_reaction_notification_device_criteria.dart`, `reaction_notification_proof_support.dart`,
  `group_muted_notification_android_criteria.dart`.
  Tests: `test/integration/group_reaction_notification_device_criteria_test.dart`,
  `test/integration/reaction_notification_proof_support_test.dart`,
  `test/integration/group_muted_notification_criteria_test.dart`,
  `test/features/groups/integration/group_notification_visibility_staging_test.dart`.
  Gates: `scripts/test/group_reaction_notification_device_contract_test.sh`,
  `scripts/test/group_muted_notification_device_contract_test.sh`, `scripts/run_test_gates.sh`.
  New: `docker-ws/run_reaction_campaign_386.sh`, `docker-ws/run_muted_campaign_386.sh`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `9159ad66b3b286d0`, `freshness=current`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "group_reaction_notification_device_criteria capture_group_reaction_notification_device provider evidence relayJournalContainsAndroidProviderSend" --profile tdd --budget 700` (confidence=anchored).
- Anchors: `relayJournalContainsAndroidProviderSend` → `integration_test/support/android_notification_payload_campaign.dart:157`.
- **Relay citations are HEAD-relative as of `37dd2eb20`** ("G26: wake the recipient for strict-authority
  group content"), which landed a new `[GROUP_CONTENT_WAKE]` vocabulary and moved every line in
  `inbox.go` past ~2134 by roughly +55 during planning. Treat every `inbox.go:NNNN` in this plan as a
  **symbol anchor plus an approximate line**, and re-verify by literal at execution time.
- Graph gaps that required raw source search: all of `go-relay-server/`, every `scripts/test/*.sh`,
  `runtime_roots.json`, and the path-string census sites — none has an import edge, so
  `tdd_context.py affected` cannot name them.
- Reuse rule: anchors are starting points; every conclusion is source- or command-backed.

## Scope Contract And Guard

In scope:
- **W1 (G16):** reuse Plan 380 W0's v1.8.0 predicate; replace the dead-marker provider count with a
  **relay counter delta**; split the nomination rule by lane; repair the background-connected
  discrimination; rename rather than delete the measurement key across all seven sites.
- **W2 (G20):** port the live-stream + byte-offset-cursor substrate; make graded selection
  identity-bound; extend the accumulator to the sender path and `_collectBoundedLogs`.
- **W3 (G18, partial):** a negative row for the protected/replay twin at host tier, and the group
  self-reaction narrowing proven on device as a **counter delta**.

Must preserve:
- Plan 380 W0's payload predicate and its three host pins, byte-unchanged → `TC-386-04`.
- `_collectBoundedLogs`'s provider gate stays **bypassed** for the muted/killed stages
  (`capture:2934-2946`) → `TC-386-07`. It is called only at `:2306` and `:2690`, both reaction lanes.
- **`reaction_notification_proof_support_test.dart:920`** asserts the `_sendGroupText` slice
  `contains('baselineOutcomeCount')`. Removing the positional selector **reds this existing pin**; it
  must be re-pinned to the new selector's literal **in the same commit** → `TC-386-06`.
- **`reaction_notification_proof_support_test.dart:993-997`** requires `Future<void> _collectBoundedLogs()`
  to keep its exact signature and ordering → `TC-386-07`.
- **`test/core/debug/group_reaction_notification_fixture_test.dart`** imports the capture file as a
  library and pins `retryBoundedFixtureRead` — the exact helper `_readAndroidLogcat` wraps and W2
  replaces → `TC-386-05`.
- The DTR-13 structural slice over the capture file (`dtr13_…_test.sh:316-339`: Python `.index()` on
  four exact function signatures plus exact-whitespace `"'build',\n      'ios'"` fragments) and
  `android_app_state_guard_test.dart:1644-1653` (no `'clear',` literal) → `TC-386-05`.
- The recipient-side fail-closed crypto-marker check (`capture:5068-5078`, mirrored
  `criteria:2202-2209`) keeps failing closed.
- `[GROUP_INBOX] Stored message for group` stays required — it is the **window-liveness oracle** that
  separates "nothing happened" from "the collector returned an empty window".

Hard `Do not`:
- Do not change any `lib/` file. If a production change looks necessary — including adding a
  `messageId` to a FLOW event — **stop and replan**; that is a different plan, and `TC-386-06` is
  scoped so it is not necessary.
- Do not touch `go-relay-server/`. The vocabulary is frozen by
  `push_permanent_error_closure_test.go:237-300`.
- Do not repair the 1:1 head-provenance lane's dead grammar or the iOS legs (see Deferred).
- Do not use the unattributed `[PUSH] outcome=success` line as a **count** (see TC-386-02).

Deferred / accepted difference:
- **The G18 headline bystander leg.** It needs a third group member, and no lane can host it today.
  The reaction/muted capture has exactly two device slots (`capture:320-321`; the only topology check
  is `senderId != recipientId` at `:1057`). The three-role lane **does** carry charlie-scoped
  zero-notification-count assertions (`group_multi_party_device_criteria.dart:10593-10597`,
  `:17285-17289`) — but its capability `groups.multi_party_release` runs on **four iOS simulator
  slots** (`tool/sims/critical_features.json:822`), which cannot receive real FCM or APNs pushes, so
  it cannot carry an Android real-push proof. Cost to close: a third `--bystander` slot through the
  capture driver, runner and criteria; a three-member group fixture; and a third exclusive Android
  resource in `critical_features.json`. Template: `run_intro_accept_notification_android.dart`
  (`_Party a/b/c` `:312-319`, three-target CLI `:239-267`, per-party seeding `:466-660`). Owner: the
  G22 1:1/multi-device evidence wave.
- **The 1:1 observer-of-a-self-reaction device leg** — genuinely provable on two devices (the relay
  applies no author narrowing to 1:1 reactions, `reaction_push.go:81-117`, so B receives a real push
  and `handle_incoming_reaction_use_case.dart:472-481` must suppress it). Deferred for plan size; it
  belongs to the 1:1 head-provenance lane, whose grammar is deferred with it. Owner: the G22 wave.
- **Dead v1.7 grammar at deferred sites:** `reaction_notification_proof_support.dart:5087`
  (`classifyRelayCapture`) and `capture_1to1_reaction_head_provenance.dart:1128`, `:1139`, `:1638`
  (1:1 lane, false-negative direction); `criteria:2447-2461` and `capture:1349`/`:4467-4479` (iOS,
  GAP-N12). Inventory recorded here rather than in a contract row — a census row that passes by
  annotating every site has no teeth (review finding). The single real obligation, that no second
  v1.8.0 grammar definition appears, is kept in `TC-386-04`.
- **Accepted difference:** renaming the measurement key changes the artifact shape, so artifacts
  written before this plan will not re-validate. Guarded by `TC-386-02` and recorded in Rollback.

Dependencies:
- **Plan 387 first** — `sims-contracts` aborts at its 4th contract today, and this plan's registration
  and harness-contract checks run through it.
- Plan 384: **satisfied** (landed `cbf71cde9`).
- A concurrent relay change landed at `37dd2eb20` during planning; W1's fixtures must be re-derived
  against relay source at execution time (see Graph Grounding Snapshot).

## Test Contract
Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-386-01 | The lane accepts the v1.8.0 provider grammar and rejects every journal without a real acceptance | `test/integration/group_reaction_notification_device_criteria_test.dart::'reaction provider evidence accepts the v1.8.0 outcome journal'` + `::'…rejects a journal with no accepted send'` | integration host / fixtures derived byte-for-byte from the relay's own format strings, **negatives reused verbatim from `android_notification_payload_campaign_support_test.dart:401-417` plus `[PUSH] outcome=registered`** | causal RED (a `provider_fcm` fixture holding only `[PUSH] outcome=success attempt=1 total_attempts=3` fails today: filtered lines 0) → accept row passes, every negative rejected | replace the predicate with `contains('[PUSH]')` → the `outcome=registered` negative passes → reject row reds (this is why that negative is named, not left to the executor) | `flutter test test/integration/group_reaction_notification_device_criteria_test.dart`; already in `GROUP_TESTS` (`run_test_gates.sh:650`) — grep-verify count 1 |
| TC-386-02 | Provider and nomination evidence is an **exact relay counter delta**, per lane, not a substring over a shared journal | `…group_reaction_notification_device_criteria_test.dart::'provider evidence is graded by counter delta, per lane'` (+ negatives: `::'a declined recipient reds'`, `::'an empty window reds'`) | integration host / synthetic `/metrics` scrape pairs (before/after) | causal RED (no counter-delta path exists; the fixture cannot be graded today) → reaction scenarios require `delta relay_group_reaction_wake_total{outcome="attempted"} == expectedRecipients × addTransitions` **and** `{outcome="route_error"} == 0` **and** `{outcome="incapable_skipped"} == 0`; message scenarios require `[GROUP_INBOX] Stored message for group` (no wake counter exists for them) plus `delta relay_push_sent_total` ≥ 1 | drop the `route_error == 0` conjunct → the "one recipient silently declined" negative fixture passes → red | same command + registration as TC-386-01 |
| TC-386-03 | The background-connected scenario discriminates push origin with grammar v1.8.0 actually emits | `…group_reaction_notification_device_criteria_test.dart::'background-connected push origin is proven by the v1.8.0 wake line'` | integration host / synthetic journal + recipient logcat fixture | causal RED (the fixture's real v1.8.0 wake line lacks `remote_type=`, so `criteria:2141-2158` rejects it today) → accepted, with the recipient-side push-origin marker still required | revert the predicate to require `remote_type=` → red | same command + registration as TC-386-01 |
| TC-386-04 | Exactly one v1.8.0 grammar definition exists, and this lane uses it | `…group_reaction_notification_device_criteria_test.dart::'the reaction lane calls the shared v1.8.0 predicate'` | integration host / repo source assertions | causal RED (the criteria file does not reference the shared predicate today) → the criteria file contains `relayJournalContainsAndroidProviderSend(`, and the acceptance-regex literal occurs in exactly **one** file (`android_notification_payload_campaign.dart`) | copy the regex into the criteria file instead of importing → the "exactly one file" assertion reds (without this, a local copy passes every other row) | same command + registration as TC-386-01. Preservation: `flutter test test/integration/android_notification_payload_campaign_support_test.dart` |
| TC-386-05 | Every **graded** capture read comes from a live stream with byte-offset cursors | new **scoped** seam in `scripts/test/group_reaction_notification_device_contract_test.sh` | sh contract / host source assertions | causal RED by construction (the seam requires `_startDeviceLogStream` + `_deviceLogcatCursor`, and asserts the exact 4-element list `'logcat', '-d', '-v', 'threadtime'` is absent; the un-ported file fails both) → exit 0 | re-introduce one `logcat -d` read on a graded path → red | `/claude-host-bin/host-run bash scripts/test/group_reaction_notification_device_contract_test.sh`; AUTO (glob). **Preservation:** `dtr13_…_test.sh:316-339`, `android_app_state_guard_test.dart:1644-1653`, `test/core/debug/group_reaction_notification_fixture_test.dart` |
| TC-386-06 | The graded send outcome is selected by a send-scoped identity the harness minted, never by position or count delta | `test/integration/reaction_notification_proof_support_test.dart::'the graded send outcome is selected by its own marker, never by position'` + `::'the capture file contains no positional or count-delta selector'` | integration host / rotated-window fixture (the baseline-length prefix aged out) + a source census over the capture file | causal RED (fed a rotated window, today's positional rule returns the WRONG observation and the count-delta rule never fires) → the marker-bound selector returns the right observation or fails closed; the census finds zero `observations[baselineOutcomeCount]` and zero count-delta predicates | restore `observations[baselineOutcomeCount]` → the census row reds (the fixture row alone cannot see the capture file — that is why the census row exists) | `flutter test test/integration/reaction_notification_proof_support_test.dart`; **manual registration** — add path to `GROUP_TESTS` (grep-verify count 1) |
| TC-386-07 | Sender-side evidence is accumulated monotonically and keeps id-distinct events | `…reaction_notification_proof_support_test.dart::'the accumulator keeps id-distinct events that render identically'` | integration host / accumulator fixture | causal RED (the accumulator dedupes on exact trimmed line text, `capture:3307`, so id-distinct events collapse today) → id-distinct events survive; the sender path and `_collectBoundedLogs` both fold through the accumulator | remove the id from the dedupe key → red; drop the sender read from the accumulator → the sender-rotation fixture reds | same command + registration as TC-386-06. **Preservation:** `_collectBoundedLogs` keeps its signature/order (`proof_support_test:993-997`) and its provider-gate bypass for muted/killed stages |
| TC-386-08 | The muted and killed-app lanes still validate after the artifact grammar gains the self-reaction evidence | `scripts/test/group_muted_notification_device_contract_test.sh` | sh contract / four round-tripped fixtures | causal RED once W3 adds evidence keys (the muted artifact grammar is an **exact-key** contract; a new key fails the round-trip until the allow-lists are re-pinned) → exit 0 with the 3-id ordered census unchanged | reword the failure literal at `group_muted_notification_android_criteria.dart:846` → the `:67` grep assertion in the sh contract reds | `/claude-host-bin/host-run bash scripts/test/group_muted_notification_device_contract_test.sh`; AUTO (glob) |
| TC-386-09 | Both twins of the group audience gate enforce author-only and self-silence | `test/features/groups/integration/group_notification_visibility_staging_test.dart::'protected reaction row is null for a non-author target'` + `::'…is null for a self-reaction'` | integration host / the file's existing `_ProtectedKind.reaction` seeding (`:612-624`), which already builds a listener with both `notificationDisplayOutbox` and `notificationService` non-null | causal RED (**verified**: the only twin coverage seeds an author-owned target — `senderPeerId: _localPeerId`, `isIncoming: false` at `:616-620` — so deleting the author-only clause reds nothing today) → the twin returns null for a non-author target and for a self-reaction | delete the author-only clause at `group_message_listener.dart:3651` → these rows red while the live-path pins at `group_message_listener_test.dart:17159-17258` stay green | `flutter test test/features/groups/integration/group_notification_visibility_staging_test.dart`; AUTO (glob) |
| TC-386-10 | On device, a group self-reaction narrows the wake audience to nobody — proven where it happens | one extra graded step inside the existing `android_group_muted_reaction_background_suppression` scenario (no new scenario id) | device proof / pinned pair: physical `21071FDF600CSC` + emulator `emulator-5554`, real relay v1.8.0 | manual/device-only proof → across the self-reaction transition, `delta relay_group_reaction_wake_total{outcome="no_wake_recipients"} == 1` **and** `{outcome="dispatched"} == 0`; no new card on either device | remove the nomination guard (`send_group_reaction_use_case.dart:1314`) in a scratch build → both deltas flip → leg reds deterministically (a substring assertion would NOT re-red: another user's self-reaction keeps `outcome=no_wake_recipients` present in the window) | `/claude-host-bin/host-run bash docker-ws/run_muted_campaign_386.sh`; **no new scenario id** — reuses the existing id, validator kind, runner dispatch and capability |
| TC-386-11 | The reaction catalog lane runs end to end on v1.8.0 with sound evidence | `groups.reaction_notification_campaign`, all five Android scenarios | device proof / pinned pair as above, real relay v1.8.0 | manual/device-only proof → every scenario reaches artifact write and validates; no provider wait times out; every graded selection is identity-bound | revert the predicate reuse → the first provider wait times out at 2 min | `/claude-host-bin/host-run bash docker-ws/run_reaction_campaign_386.sh`; existing capability (`tool/sims/critical_features.json:747-766`) |

### Test Notes
- **TC-386-02 — why counters, not the journal.** `[PUSH] outcome=success` carries no attribution and
  is emitted by the single shared provider path for every push type and every user on a **production**
  box; the window is `--since` with no `--until`; and `_waitForProviderSendCount` returns on the first
  true probe, so the campaign can advance past its own send before FCM has accepted it. That is a
  false pass plus a race. The relay already exports `relay_group_reaction_wake_total` and
  `relay_push_sent_total` (`go-relay-server/metrics.go:338`, `:348`) on `:2112/metrics`
  (`main.go:261-266`), and **five `docker-ws/` scripts already scrape it over ssh** — e.g.
  `deploy_relay_v173.sh` greps `relay_group_reaction_wake` by name. Counter deltas are existing repo
  practice, are reaction-scoped so other users' message traffic cannot move them, and make the
  mutation deterministic. Also add `--until @<quiescenceEpoch>` to the journal window and stop
  treating first-match as arrival: wait on a device-side receipt, then read once.
- **TC-386-02 — the lane split is a relay fact, not a harness gap.** Two of the five Android scenarios
  are group **message** scenarios. `fanOutPush` — the message lane — contains **zero** `log.Printf` of
  any kind; per recipient it only increments Prometheus counters, calls
  `recordGroupMissingPushRoute()` (a failure line), or dispatches. There is no message-lane equivalent
  of `outcome=dispatched`. Key the split on the predicate the file already has,
  `requirement.id.endsWith('_message_unread_lifecycle')` (`criteria:2140`).
- **TC-386-02 — no "legitimate zero" clause.** The first draft accepted zero provider sends when
  recipient-side crypto markers proved delivery. That guard is **already unconditionally true** (the
  markers persist from an earlier warm-up push), so it degraded the count to no requirement at all —
  revoke the relay's FCM credentials and the lane would still pass. Counter deltas replace it.
- **TC-386-02 — rename, do not delete, and touch all seven sites.** `expectedProviderSendCount` is
  pinned by an **exact-key** schema check, so deleting it from measurements fails every artifact at
  `$.measurements` before any provider logic runs, and leaving it makes the iOS validator compare
  against `-1` unconditionally. The seven: `criteria:1329` (exact-key set), `:1346-1352` (value
  assert), `:2110-2111` (Android read), `:2424` + `:2451` (iOS read/compare), `capture:5147`,
  `capture:5296`, and the shared host fixture builder
  `group_reaction_notification_device_criteria_test.dart:1006`. The iOS validator is **not** untouched
  by this change — say what it does after the rename rather than implying the lane is deferred.
- **TC-386-05 — scope the seam, do not port it file-wide.** The tap-campaign template
  (`notification_tap_campaign_adapter_contract_test.sh:239-252`) bans `['logcat','-c']` outright and
  tests `'logcat',` × `'-d',` co-occurrence across the whole file. The reaction capture file has
  **eight** `['logcat','-c']` clears (`:761`, `:767`, `:768`, `:1358`, `:2374`, `:3521`, `:3687`,
  `:4305`) that stay, and `'-d',` also appears at non-logcat sites. Ported verbatim the seam is
  **unsatisfiable** — a permanent red, not a causal one.
- **TC-386-05/06 — the real read census.** There are **seven** `logcat -d`-family reads, not the three
  helpers the first draft named: `:2203`, `:2238`, `:2723`, `:4107`, `:4330`, `:4500`, `:5791`. Four
  are standalone inline invocations the plan previously missed. Recompute this census at execution
  time (step 6) rather than trusting the list.
- **TC-386-06 — why marker-bound, not messageId-bound.** `GroupSendTimingObservation`
  (`reaction_notification_proof_support.dart:5125-5136`) has exactly four fields — `outcome`,
  `expectedRecipientCount`, `inboxStored`, `inboxPending` — and **no identity**. Binding it to a
  message id would require adding `messageId` to the `GROUP_SEND_MSG_TIMING` FLOW details in
  `lib/features/groups/application/send_group_message_use_case.dart`, which this plan's hard `Do not`
  forbids. The available send-scoped identity is the unique `marker` `_sendGroupText` already types
  and already waits on (`capture:3996`, `:4032-4036`); `latestGroupSendMessageId`
  (`proof_support:6353-6363`) and `groupMessageStoredWithId` (`:6380-6396`) remain the recipient-side
  id-bound predicates.
- **TC-386-10 — choreography constraints.** In this scenario the **recipient** authors both reaction
  targets (`capture:3494-3498`) and the **sender** reacts (`capture:3556-3562`), so a self-reaction
  needs a sender-authored target: pin it to the sender's warm-up marker in the **control** group
  (`capture:3546`). Evidence binding is order-sensitive — `resolveMutedBackgroundPushBinding` takes
  `suppressed.first` / `shown.last` — so **no additional text may be sent into either group after the
  recipient is terminated at `capture:3519`**. The reactor-side storage probe is deliberately **not**
  asserted: `_runInstalledGroupReactionProbe` builds its request from shared mutable capture fields
  and every muted-lane probe targets `recipientId` only (`capture:3350-3366`); adding a sender probe
  risks corrupting the existing muted claims for no additional audience evidence.
- **TC-386-10 — dumpsys before the probe.** `_runInstalledGroupReactionProbe` foregrounds the app
  (`capture:4756`) and a foreground open can clear delivered cards, so card observations must be taken
  first. Use the existing retry wrapper (`capture:3347`), never the raw probe — run 13 (2026-08-18)
  saw `reactionRows: 0` while every other claim held.
- **Do not key any audience assertion on `group_reaction_local_state_ineligible`** — it is a single
  catch-all (`background_message_handler.dart:2600-2610`) covering mute, non-author, self-reactor and
  missing-target alike, and it already appears in the muted lane's artifacts.
- **Device keyguard precondition.** `21071FDF600CSC` is PIN/fingerprint locked and its UI is driven by
  this lane. Check `dumpsys window policy | grep secure` in preflight and stop with a named
  environment blocker rather than a false red.

## Implementation Steps
1. Snapshot `git status --short`. **Stop-if: it is not clean for `go-relay-server/`,
   `integration_test/scripts/`, and `test/integration/`.** A concurrent session landed relay work at
   `37dd2eb20` during planning; never mutate the tree during a lane run. Confirm plan 387 has landed.
2. Re-derive every relay literal against current `go-relay-server/` source (the format strings, not
   the line numbers) before writing any W1 fixture.
3. **W1.** Add TC-386-01..04 rows first (INV-RED-FIRST), then: reuse the 380 predicate, add the
   counter-delta scrape over the capture's existing ssh channel, split the nomination rule by lane,
   repair the background-connected discrimination, and rename the measurement key across all seven
   sites in one coherent edit.
4. **W2.** Add TC-386-05..07 rows, then port the stream/cursor substrate from
   `notification_android_payload_campaign.dart:2400-2501` (live
   `/bin/sh -c 'exec adb -s "$1" logcat -T 1 -v brief >"$2"'`, cursor = file length, window read from
   cursor, fail-closed lifecycle with a 30 s non-empty startup gate), make the graded selection
   marker-bound, and fold the sender path and `_collectBoundedLogs` into the accumulator.
   **Stop-if:** the DTR-13 structural slice stops matching — restore the four function signatures and
   the exact-whitespace build fragments rather than editing that contract.
5. Re-pin `reaction_notification_proof_support_test.dart:920` to the new selector's literal **in the
   same commit** as the TC-386-06 fix, or the suite reds with no plan attribution.
6. **Census, computed not fixed.** Recompute `_sendGroupText` (15 calls, three on the physical device:
   `:2593`, `:3496`, `:3498`), `_waitForSenderEventCount` (6), `_readAndroidLogcat` (8),
   `_countProviderSends`, `_waitForProviderSendCount`, `_providerSuccessMarker` readers, and the seven
   `logcat -d` reads. Every site must move or be justified in the execution log. Also record
   `adb -s <id> logcat -g` for both devices into the artifact — the sender ring is unmeasured.
7. **W3.** Add TC-386-09's two rows to the staging test beside the existing `_ProtectedKind.reaction`
   seeding. Then add the self-reaction step to the muted scenario and re-pin the muted artifact
   allow-lists (`group_muted_notification_android_criteria.dart` top-level and section key sets) plus
   the host round-trip in `group_muted_notification_criteria_test.dart`.
8. Author `docker-ws/run_reaction_campaign_386.sh` and `docker-ws/run_muted_campaign_386.sh` from
   `docker-ws/run_muted_campaign_383.sh`, setting relay addresses and FCM credentials **inside** the
   script — the host bridge uses the server's environment and drops container env vars.
9. Add the two test paths to `GROUP_TESTS` and grep-verify.
10. Run focused GREEN → preservation sentinels → graph-affected → curated lane → the two device runs.

## Risks And Blind Spots
- **Editing the capture file reds content pins the graph cannot see** → guarded by TC-386-05's named
  preservation set. Note the correction: `check_reliability_simulation_discovery.sh:236-241`,
  `run_test_gates.sh classify_path:1377-1385` and `runtime_roots.json:284-295` match on **path only**
  and carry no content assertion — they are add/remove/rename guards and no wave here triggers them.
  The real content pin the first draft missed is
  `scripts/test/group_reaction_notification_sims_adapter_contract_test.sh:112-129`.
- **Host fixtures could keep the lane green while device stays red** → TC-386-01's negatives are named
  verbatim rather than left to the executor, and fixtures are byte-derived from the relay's own format
  strings (re-derived in step 2).
- Lifecycle / derived-state durability: N/A — no runtime state or derived UI changes; the device leg
  asserts only relay counters and OS card counts.
- Sibling-surface consistency: the same dead grammar lives in the 1:1 lane and the iOS legs; both are
  deferred with named owners in the Scope Contract, and TC-386-04 prevents a second grammar definition.
- Destructive-action side effects: the eight `logcat -c` clears stay; TC-386-05's startup gate fails
  closed on an empty stream, and the `'clear',` literal ban stays green.
- Invariant re-verification under new transitions: TC-386-10 adds a self-reaction transition inside an
  already-graded scenario and re-verifies that scenario's existing muted claims in the same run —
  which is exactly why the ordering constraints in Test Notes are load-bearing.
- Construction / call-site census: computed at execution time (step 6), never a fixed list.
- Build-artifact provenance: N/A — the campaigns run a prebuilt stamped APK whose provenance guard is
  already enforced by the deploy scripts this plan does not change.
- Permission / ACL verb symmetry: N/A — no permission or ACL check is touched.
- Fake side-effect fidelity: the counter-delta fixtures are synthetic `/metrics` scrape pairs; the
  production writer is the relay's own counter increment, cited per outcome.
- Composite-node / relationship assertions: TC-386-10 binds both counter deltas and the card counts to
  the **same** self-reaction transition, not three independent finds.

## Gate Cadence
- Per-plan closure: the focused host tests named above, the two harness sh contracts, `sims-contracts`
  (after 387), the `groups` curated lane, `completeness-check`, and the two device campaign runs.
- Graph-affected first: after the harness edits and BEFORE the curated lane, run
  `python3 graphify-arch/tdd_context.py affected <changed files> --budget 600` and run what it names.
  **Blind spot for this plan:** every `scripts/test/*.sh` contract and every path-string gate has no
  import edge and will not appear — they are listed explicitly in Acceptance Gates.
- Full `host-all` is not a per-plan gate; it belongs to the notification wave that covers 383/384/385
  and to final rollout.
- Shared tests outside the feature/core globs: `test/integration/**` — direct `flutter test <path>`
  gates are given for all four files. After step 9 two of them also ride `groups`;
  `android_notification_payload_campaign_support_test.dart` stays host-all-only by design (it belongs
  to the payload lane) and gets a direct gate here, so TC-386-04's preservation has a home.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree + dependency check (387 landed; relay/harness trees clean)
git status --short
git log --oneline -3

# W1/W2 causal REDs (before the harness edits)
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'reaction provider evidence accepts the v1.8.0 outcome journal'
flutter test test/integration/reaction_notification_proof_support_test.dart \
  --plain-name 'the graded send outcome is selected by its own marker, never by position'

# W3 causal RED
flutter test test/features/groups/integration/group_notification_visibility_staging_test.dart \
  --plain-name 'protected reaction row is null for a non-author target'

# Focused GREEN — exit 0, zero failures
flutter test test/integration/group_reaction_notification_device_criteria_test.dart
flutter test test/integration/reaction_notification_proof_support_test.dart
flutter test test/integration/group_muted_notification_criteria_test.dart
flutter test test/features/groups/integration/group_notification_visibility_staging_test.dart

# Preservation (TC-386-04, and the three capture-file content pins)
flutter test test/integration/android_notification_payload_campaign_support_test.dart
flutter test test/core/debug/group_reaction_notification_fixture_test.dart
flutter test test/integration/android_app_state_guard_test.dart

# Graph-affected dependents BEFORE the curated lane
python3 graphify-arch/tdd_context.py affected \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/reaction_notification_proof_support.dart \
  integration_test/scripts/group_muted_notification_android_criteria.dart --budget 600
# then: flutter test <every test file it names>

# Harness contracts (content pins over the edited files) + the aborting-gate check
/claude-host-bin/host-run bash scripts/test/group_reaction_notification_device_contract_test.sh
/claude-host-bin/host-run bash scripts/test/group_reaction_notification_sims_adapter_contract_test.sh
/claude-host-bin/host-run bash scripts/test/group_muted_notification_device_contract_test.sh
/claude-host-bin/host-run bash scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh
/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts

# Registration is grep-verified, never run-verified (family gates swallow --list)
grep -c 'test/integration/reaction_notification_proof_support_test.dart' scripts/run_test_gates.sh  # expect: 1
grep -c 'test/integration/group_muted_notification_criteria_test.dart' scripts/run_test_gates.sh    # expect: 1
/claude-host-bin/host-run ./scripts/run_test_gates.sh completeness-check
/claude-host-bin/host-run ./scripts/run_test_gates.sh groups

# Device discovery, then the two closure runs
flutter devices --machine
adb devices
/claude-host-bin/host-run bash docker-ws/run_reaction_campaign_386.sh   # closes G16 + G20
/claude-host-bin/host-run bash docker-ws/run_muted_campaign_386.sh      # closes the G18 self-reaction leg

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

Semantic outcomes: every `flutter test` exits 0 with zero failures; every sh contract exits 0 with no
`FAIL:` line; `completeness-check` reports zero unmatched paths; both campaign runs reach artifact
write and validator acceptance for every scenario they own. The only pinned numeric counts are the two
`grep -c` values, which the registration contract itself fixes.

## Device/Relay Proof Profile
- Profile: paired-device, real relay, real FCM.
- Boundary being proven: G16/G20 — that the lane runs and grades sound evidence against the live
  v1.8.0 relay, which no host fixture can prove because the grammar and the counters live in a
  deployed binary. G18 (partial) — that the relay really narrows a self-reaction's wake audience to
  nobody, a live-relay decision no host fixture can produce.
- Live availability check: `flutter devices --machine`, `adb devices` → pin the observed ids.
- Pinned targets: physical Android `21071FDF600CSC` + Android emulator `emulator-5554` (the pair both
  lanes already use; `run_group_muted_notification_android.dart:304-307` passes
  `--sender <emulator> --recipient <physical>`).
- Automation: every setup, permission, navigation, action and assertion is harness-driven. The one
  human precondition is unlocking `21071FDF600CSC` (secure keyguard).
- Closure role: required closure evidence for G16, G20, and the G18 self-reaction leg.
- `FLUTTER_DEVICE_ID`: host selector only — both ids stay pinned on the campaign command line.
- Registration: existing capabilities; no new scenario id, so no `classify_path` or census change.
- Discovery command: `.claude/skills/sims/scripts/run_with_devices.sh major --list` → both listed.
- Closure command: the two `docker-ws/run_*_campaign_386.sh` wrappers **authored in step 8** — they do
  not exist yet. They must be repo-resident with env set inside; `host-run bash -c` is refused and the
  bridge drops container env vars.
- Deferred device work: the non-author bystander leg and the 1:1 self-reaction leg → G22 wave; iOS
  legs → GAP-N12.

## Rollback
- Reversible by: `git revert <this plan's commit>` — harness, test and gate source only; no `lib/`
  file, no relay change, no schema, no migration.
- What a PRIOR shipped build does with post-change data: unaffected — no client or relay behaviour
  changes. **Artifacts are affected:** renaming the provider measurement key means a pre-change
  artifact will not re-validate against the new validator and vice versa, and the muted artifact
  grammar gains keys (TC-386-08). Artifacts are run evidence, not user data, so a revert costs a
  re-run.
- NOT recoverable once landed: nothing.
- Staging: land W1+W2 together with one reaction-campaign run, then W3 with one muted run. If the
  campaign shows the counter-delta expectation is wrong for this topology, only TC-386-02's expected
  values change — W2 and W3 stand.

## Execution Interpretation And Done Criteria
- Expected RED: TC-386-01..07 and TC-386-09 fail on HEAD for the documented reasons; TC-386-08 reds by
  construction once W3 adds evidence keys.
- GREEN sentinel: none as a standalone row — every preservation obligation is named inside a causal
  row's Preservation cell, with its own command in Acceptance Gates.
- Pre-existing dirty tree / known failure: `test/integration` holds pre-existing reds unrelated to this
  plan; compare against the recorded baseline before attributing any failure here.
- Environment blocker (NOT a product blocker): `21071FDF600CSC` locked, a device absent from
  `flutter devices --machine`, or missing FCM/relay credentials in the wrapper environment.
- Scope drift (BLOCKING): any `lib/` change, any `go-relay-server/` change, or any repair of the
  deferred 1:1 / iOS grammar sites.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] `reaction_notification_proof_support_test.dart:920` was re-pinned in the same commit as TC-386-06.
- [ ] All seven `expectedProviderSendCount` sites were changed in one coherent edit.
- [ ] Harness registration is implemented AND verified (two `grep -c` values, `completeness-check`).
- [ ] Both device campaign runs pass for every scenario they own.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected.

## Handoff
- First causal RED command:
  `flutter test test/integration/group_reaction_notification_device_criteria_test.dart --plain-name 'reaction provider evidence accepts the v1.8.0 outcome journal'`.
- Preservation command:
  `flutter test test/integration/android_notification_payload_campaign_support_test.dart` and
  `flutter test test/core/debug/group_reaction_notification_fixture_test.dart`.
- Manual registration: two `GROUP_TESTS` array entries (step 9). No scenario-registration surfaces —
  W3 deliberately adds no scenario id.
- Migration: none.
- Boundary closure: two device campaign runs, via wrappers authored in step 8.
- Unresolved evidence: emulator-5554's ring size in its sender role (measured and recorded in step 6,
  no contract row depends on it); and the live counter-delta values for this topology, which the first
  reaction-campaign run establishes.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-19 | W1 (G16) | criteria + capture + proof support | relay literals re-derived against `go-relay-server/` at `7bca5966b` | counter labels confirmed: `attempted`, `route_error`, `incapable_skipped`, `no_wake_recipients`, `self_or_empty_skipped`, `duplicate_suppressed`, `invalid_or_disabled`, `push_unavailable` | **Plan correction:** TC-386-10 named counter label `dispatched`, which does NOT exist — `dispatched` is the JOURNAL word (`inbox.go:2797`), the counter label is `attempted` (`inbox.go:2796`). A `{outcome="dispatched"} == 0` conjunct would have been vacuously true. Implemented as `attempted` | grading rewrite |
| 2026-08-19 | W1 (G16) | 10 rename sites | `expectedProviderSendCount` → `expectedRelayWakeAttempts` | grep census: 0 old, 12 new occurrences | **Plan correction:** the plan named "seven" sites and listed eight; the real count is **ten**. Missed: `criteria:2167` (Android compare) and `criteria:2495` (iOS `PUSH_NSE_DECRYPT_OK` count). Both changed | evidence kind |
| 2026-08-19 | W1 (G16) | criteria scenarios | new `relay_metrics` evidence kind on all 5 Android scenarios; iOS untouched | `rg -c "kind: 'relay_metrics'"` = 5 | grading is a re-derived counter delta over a raw baseline/final scrape pair, per lane | W2 |
| 2026-08-19 | W2 (G20) | capture | live `adb logcat -T 1` stream per device + byte-offset cursors; `logcat -c` intercepted in `_adb` as a stream FLOOR | 7 inline `logcat -d` reads → 2 remain, both `--pid=`-scoped SETUP polls (justified: a whole-device stream cannot express "this pid"); all 8 `logcat -c` sites unchanged | `_readAndroidLogcat` keeps its signature so all 8 callers are unchanged; `retryBoundedFixtureRead` kept (pinned by `group_reaction_notification_fixture_test.dart`) and reused for the stream startup gate + metrics scrape | selection |
| 2026-08-19 | W2 (G20) | capture + proof support | positional selector replaced by a harness-MINTED breadcrumb (`adb shell log -t MKNOON386 send_marker=<marker>`) + `selectGroupSendObservationForMarker` | census: 0 `baselineOutcomeCount` (incl. prose), 0 count-delta selectors | `:920` re-pinned to `_mintGroupSendBreadcrumb(deviceId, marker)` + `selectGroupSendObservationForMarker(` in the same commit (step 5) | accumulator |
| 2026-08-19 | W2 (G20) | proof support | `DeviceFlowAccumulator` = multiset fold (occurrence ordinal in the key), per device, extended to the sender path and `_collectBoundedLogs` | id-distinct identical-rendering events survive; re-absorbing an overlapping window is idempotent | the old `Set<String>` fold silently deflated every count taken over the accumulator | W3 |
| 2026-08-19 | W3 (G18) | staging test | 3 rows on `buildProtectedReactionDisplayReadyRow` | positive control + non-author + self-reaction | **Plan correction:** the plan's single non-author row is ALSO caught by `target.isIncoming`, so deleting the author-only clause left it green (verified by mutation). Added a fourth row — foreign author, NOT flagged incoming — which isolates the clause | device leg |
| 2026-08-19 | W3 (G18) | muted criteria + capture | `selfReactionAudience` artifact section; deltas RE-DERIVED from the raw scrape pair, card counts compared as deltas on BOTH devices | 6 host negatives incl. the exact mutation shape (`no_wake_recipients` 0 / `attempted` +1) | placed AFTER the muted binding (order-sensitive `suppressed.first`/`shown.last`); target = the SENDER's warm-up marker; no reactor-side probe | gates |
| 2026-08-19 | Causal RED | worktree at HEAD | HEAD rejects a real v1.8.0 provider journal → `$.evidence[provider_fcm] must contain exactly the final raw provider send count after quiescence`; HEAD rejects a bare v1.8.0 wake line → `background-connected reaction lacks relay/provider/logcat push-origin discrimination` | behavioural, not compile-only | HEAD + author-clause deleted: staging suite (1 test) AND `group_message_listener_test.dart` (227 tests) both fully GREEN — the protected twin's author guard had zero coverage | mutations |
| 2026-08-19 | Mutation re-red | worktree | 8/8 re-red, baseline restored green after each | M1 author-only clause · M2 self clause · M3 drop `route_error == 0` · M4 copy the regex into criteria · M5 re-add a graded `logcat -d` · M6 restore the positional selector · M7 accumulator set semantics · M8 `contains('[PUSH]')` · M9 restore `remote_type=` | all four sh contracts PASS; completeness-check 1468/1468 | device runs |
| 2026-08-19 | Device (live relay) | wrappers + capture | **Implementation defect found by running it.** Both graded counter families are labelled `CounterVec`s, which Prometheus does not export AT ALL until a label combination is incremented. After the v1.9.0 restart the endpoint served a healthy 53 KB exposition with ZERO `relay_group_reaction_wake_total` and ZERO `relay_push_sent_total` lines | liveness re-keyed on `relay_group_inbox_retrieves_total` (a PLAIN counter, `metrics.go:384`), which is also monotonic within a process ⇒ a process-continuity oracle; a relay that restarted mid-capture is now rejected even when the graded deltas look perfect | fixed in `9c6874e25`; 2 new negatives | rerun |
| 2026-08-19 | Step 6 (ring sizes) | measured | `emulator-5554` main ring = **2 MiB**; `21071FDF600CSC` main ring = **256 KiB** | observed emission during this campaign: ~800 KB/min per device (the live stream files grew 1.5→2.3 MB in 60 s) | **The plan's prose was optimistic by 8x for the PHYSICAL device.** At 256 KiB / ~800 KB per minute, every `logcat -d` read on the graded recipient was a **~19-second** window. G20 was more severe than assessed | recorded |
| 2026-08-19 | TC-386-11 (device) | `run_reaction_campaign_386.sh` | **2/5 PASSED — G16 repair proven end to end.** `android_group_message_unread_lifecycle` and `android_announcement_message_unread_lifecycle` both reach artifact write and validate. Live evidence: `relay_push_sent_total{result="success"}` 1 → 3 (delta 2), sentinel 2485 → 2570, and `provider_fcm.log` carries real `[PUSH] outcome=success attempt=1 total_attempts=3` lines where the dead-marker filter used to write it EMPTY | both devices streamed logs to disk for the whole run (no rotation) | `android_group_reaction_recipient` FAILED — see next row | blocker |
| 2026-08-19 | **TC-386-10 CLOSED (device)** | `run_muted_campaign_386.sh` | **PASS, exit 0, assertions=6; all 3 muted scenarios passed.** Raw scrape pair across the self-reaction transition: `no_wake_recipients` **absent in baseline → 1 in final (delta 1)**; `attempted` **4 → 4 (delta 0)**; `relay_push_sent_total{result="success"}` **25 → 25 (delta 0 — no push existed at all)**; sentinel `relay_group_inbox_retrieves_total` 6343 → 6365 (same process). Cards: recipient 1 → 1, sender 0 → 0. Target = `Plan379Warm3cf32e4124`, the SENDER's own warm-up message | `android_group_muted_reaction_background_suppression.json` `$.selfReactionAudience` + its `_self_reaction_relay_metrics.txt` | **G18's self-reaction leg is device-proven.** Note the baseline carried NO `no_wake_recipients` line — the exact labelled-CounterVec behaviour that forced the `9c6874e25` sentinel fix; without it this run would have blocked at preflight | G18 partial closure recorded |
| 2026-08-19 | TC-386-11 blocker | NOT owned by this plan | `android_group_reaction_recipient` fails at `_waitForNotificationCard`, **one step AFTER** the repaired wake wait passed. Recipient log shows exactly ONE `PUSH_BACKGROUND_MESSAGE_RECEIVED` (12:15:24.952) followed by `PUSH_BACKGROUND_STORAGE_DEFERRED` at 12:15:27.340 — `phase=display_eligibility`, `elapsedBucket=2s_to_8s`, `kind=group_reaction` | this is verbatim the G17 / Plan-383 cold-start deferral: the FIRST wake after a kill opens SQLCipher cold and blows the 2 s `display_eligibility` budget, exiting UPSTREAM of the presenter | **Latent, not introduced.** The lane never reached this step before — it died 2 minutes earlier at `_waitForProviderSendCount`. Plan 383 solved it for the MUTED lane with a throwaway warm-up push; the reaction catalog lane has none, and it has only ONE group, so a warm-up text would move `unread=0,0,0`, the exactly-2 card assertions, the UI unread timeline AND `expectedRelayWakeAttempts`. That is a redesign of the scenario's evidence contract, which this plan's own rule says to **stop and replan** rather than improvise | **REPLAN needed for the three killed-recipient reaction scenarios** |

## Reviewer Findings (wf_77341dcf-8b1, 2026-08-19 — 4 workers, all deltas applied same session)

Verdict on the first draft: **not-ready / replan** on the evidence design; core bet **refuted**.
Every delta below is applied above. Recorded so the refuted approaches are not re-planned.

**Blockers closed**
1. *The disposition rule did not apply to the message lane.* `fanOutPush` emits no journal line at
   all, so two of five scenarios would have been permanently red → rule split by lane (TC-386-02).
2. *The "legitimate zero" clause was vacuous.* The crypto-marker guard is already unconditionally true
   (markers persist from an earlier warm-up push), so provider evidence degraded to no requirement →
   clause deleted, replaced by counter deltas.
3. *The journal substring oracle is unsound on a production box* — no attribution, unbounded-forward
   window, first-match-as-arrival → counter deltas plus `--until` and a device-side receipt wait.
4. *The "structurally unprovable" rationale was wrong.* Wake-outcome admission cannot execute on the
   campaign build (`p2p_bridge_client.dart:844-847`, `:879-882`; `wake_outcome.go:190-191`; the flag
   is set nowhere) → rationale corrected, exact count kept on a working surface.
5. *The measurement change named 2 of 7 surfaces,* and `_expectExactKeys` would have failed every
   artifact; the iOS validator also reads the key → all seven enumerated, rename not delete.
6. *TC-386-10's seam was unsatisfiable* (file-wide ban vs eight `logcat -c` sites) → scoped by slice.
7. *TC-386-11 contradicted the plan's own `Do not`* — `GroupSendTimingObservation` has no identity
   field, so messageId binding needed a `lib/` change → re-scoped to the harness-minted marker.
8. *TC-386-01 could be "fixed" by deleting a hash entry* → moved to plan 387 with a key-set assertion.
9. *The G18 deferral rested on a false claim* — the multi-party lane does carry charlie-scoped
   zero-count assertions; the real blocker is its four iOS-simulator slots
   (`critical_features.json:822`) → corrected, deferral re-costed.

**Dropped as over-engineering:** the dead-grammar census row (a wrong implementation passes by
annotating every site; its only real obligation — no second grammar definition — folded into
TC-386-04) and the registration row (a tautology whose test, gate and mutation were the same
`grep -c`; kept as step 9 plus the two Acceptance-Gate lines). The ring measurement lost its contract
row and became a recorded step, since no cell asserted on it. Rows: 17 → 11.

**Missed preservation pins added:** `reaction_notification_proof_support_test.dart:920` (asserts the
`_sendGroupText` slice contains `baselineOutcomeCount` — TC-386-06's fix reds it) and `:993-997`;
`test/core/debug/group_reaction_notification_fixture_test.dart` (imports the capture file and pins
`retryBoundedFixtureRead`, the helper W2 replaces).

**Corrected citations:** the muted mutation literals live at
`group_muted_notification_android_criteria.dart:846` and in the `.sh` contract at `:67` — the first
draft cited `.sh` line numbers as criteria lines. Seven `logcat -d` reads exist, not three helpers.
`_sendGroupText` has 15 call sites, three on the physical device. All relay line numbers are
HEAD-relative as of `37dd2eb20` and moved ~+55 during planning.
