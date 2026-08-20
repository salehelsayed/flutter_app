# 391 - Killed-Path 1:1 Reaction Device Proof (G22a)

Status: EXECUTED at host tier 2026-08-20 (commits `c07c3f588`, `ed1ca15c5`) — **device leg TC-391-09 BLOCKED**, see Execution Findings
Type: Bug
Spec: free-text intent (no formal spec) — `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md` §4.11 row **G22**
Classification: implementation-ready
Closure tier: device

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-19 | Evidence Collector | `background_message_handler.dart`, `notification_android_payload_campaign.dart`, `android_notification_payload_e2e_protocol.dart`, `intro_e2e_runner.dart` | The payload campaign cannot send a reaction and knows no group concept; assumed a new leg + a `lib/` capability were needed | verify→refute (wf_d5adb934-1af, 7 agents) |
| 2026-08-19 | Refute pass | `capture_1to1_reaction_head_provenance.dart`, `run_1to1_reaction_notification_device.dart`, `device_criteria.dart`, `critical_features.json` | **The assumed vehicle is refuted.** A lane that already kills the recipient and drives a real 1:1 reaction exists and is unreachable + unevidenced | re-verify every linchpin in source |
| 2026-08-19 | Planner | all of the above, re-read directly | Scope to G22(a); zero `lib/` change; defer (b), refute (c) | emit contract |
| 2026-08-19 | Independent review | `run_1to1_reaction_notification_device.dart`, `one_to_one_reaction_notification_proof_test.dart`, `tool/sims/{executor,verdict,artifact_evidence,device_binding}.dart` | **Two de-scopes and one missing surface.** `device_criteria` is never invoked on this lane; a sims capability needs a whole adapter; the runner's own validator step has no test to run | rewrite (this version) |

## Problem And Evidence

- **Behavior to improve:** a reaction to your 1:1 message arriving while your app is killed. Nothing on any device proves the card is posted, and nothing prevents that proof from silently rotting.
- **Impact:** the reaction alert is the only signal a killed app can give for this event. The 1:1 reaction arm of the background durable-effect resolver has never executed on a real device.

- **Confirmed current gap (three defects, all in the harness layer):**

  1. **The card-asserting variant is unreachable through the registered runner.**
     `capture_1to1_reaction_head_provenance.dart` derives its scenario id from flags, not from `--scenario`
     (`:278-294`; a census of `--scenario` over the whole file returns **zero** hits): default →
     `head_provenance` (TC-00), `--live-typed-smoke` → `android_typed_reaction_smoke` (TC-13-core-smoke).
     `run_1to1_reaction_notification_device.dart:135-157` forwards exactly six options plus
     `--verbose`/`--keep-build-artifacts`; `--live-typed-smoke` is not among them, and the 5-entry catalog at
     `:28-63` has no `android_typed_reaction_smoke`. The reachable default **tolerates zero cards** —
     `:422-428` throws only when `providerMatchedEvent && cards.length != 1`, and `:429-435` only when
     `!providerMatchedEvent && cards.isNotEmpty`, so zero cards with no matched send falls through both. A TC-00
     pass is therefore not evidence that any card was posted. `--live-typed-smoke` is the variant that hard-asserts:
     `:436-441` requires a matched send, which forces `:422-428` to require exactly one card, and `:442-451`
     validates typed copy on `cards.single`.

  2. **The artifact cannot prove the killed-path property.** `_terminateRecipient()` (`:357`) is on the common
     path — it sits at the top level of `run()`, after `_requireCleanNotificationSlate()` (`:356`) and before the
     first variant branch at `:359`, with no conditional — and ends in `_waitForProcessAndActivityAbsent`
     (`:1387`). So the recipient genuinely is dead when the reaction is driven at `:382-383`. But the artifact's
     `observation` map (`:1921-1933`) records `cardPresent`/`producer`/`lifecycle`/`tapRoute`/`title`/`body`/
     `typedCopyRequired` and **no recipient process state**. The killed-path claim is unfalsifiable from the
     evidence the lane writes.

  3. **The runner's own validator step has no test to run for a sixth scenario.** After every successful capture
     `_validateArtifacts` (`run_…:169`, body `:206-231`) shells
     `flutter test -d flutter-tester integration_test/one_to_one_reaction_notification_proof_test.dart --plain-name <scenario.id>`
     and propagates a non-zero exit (`:225-228`). That file declares **five** tests, one per catalog id
     (`:18` `head_provenance`, `:87` `android_background_crypto_preflight`, `:150` `android_physical_recipient`,
     `:154` `ios_physical_recipient`, `:158` `android_message_unread_lifecycle`) — a strict 1:1 convention. Adding
     a sixth catalog id without a sixth test makes `--plain-name` match nothing; **measured 2026-08-19:
     `flutter test` prints `No tests ran.` and exits 79**, so the runner aborts *after* a fully successful device
     capture.

  A fourth, mechanical blocker sits behind (1): `_artifactFor` (`run_…:233-242`) resolves `<dir>/<scenario>.json`
  then `<dir>/<scenario>/<scenario>.json`, the runner passes `--artifact-dir` through unchanged (`:143-144`), and
  the driver writes **flat** to `${artifactDir.path}/$_artifactStem.json` (`:1944-1945`). Stem
  `live_typed_reaction_smoke` (`:281`) versus id `android_typed_reaction_smoke` (`:287`) means neither branch
  hits, and `_validateArtifacts` exits 66 with `Missing artifact:`. `head_provenance` works only because its stem
  equals its id.

- **Why the kind matters (the reason a 1:1 *text* leg does not already cover this).**
  `requiresDurableEffect` (`background_message_handler.dart:1073-1079`) is kind-agnostic, but everything it guards
  is not. `_resolveBackgroundSqlEffectAuthority` branches on `metadata.kind` five times inside the `conversation`
  case alone:
  | `file:line` | message arm | reaction arm |
  |---|---|---|
  | `:2124` | `eventKind = 'message'` | `eventKind = 'reaction'` — a different SQL lookup key |
  | `:2125-2128` | `rawEventIdentity` verbatim | `boundedReactionEventIdentity(rawEventIdentity)` — `'reaction:' + sha256[0:48]` (`deterministic_notification_id.dart:27-34`) |
  | `:2141-2144` | compares `directEntry.messageId` | compares `directEntry.reactionId` — a **different column** |
  | `:2147-2154` | `directMessage` producers | `directReaction` producers, feeding a different correlation value space |
  | `:2158-2163` | envelope `{'messageId': …}` | envelope `{'reactionId': …}` |
  Divergence also exists above the gate — the tone key at `:996-1001`, which decides audible vs silent, and the
  reaction-only early return `if (isReaction && reactionEventId == null) return;` at `:864` — and after it, at
  `:2275-2277` (`direct.eventKind == …message ? direct.messageId : direct.eventId`).
  `payload_fast_path_cold_kill`'s `coldWakeDeferralScan: "clean"` evidence proves the `directMessage` arm and
  **zero** of the `directReaction` arm.

- **Existing coverage.** Host: `background_message_handler_test.dart` carries direct-reaction rows at `:915-917`
  ('authenticated durable-authority deferral presents the non-durable fallback card (direct reaction)'), `:2641`,
  `:2698` and `:4611`. That tier is real but **stubs the resolver the device runs** — the file calls
  `debugSetBackgroundPushNotificationDisplayEligibilityResolver` **28** times. Device: nothing. Every captured
  reaction artifact on disk is a group scenario, and every `message_reaction` / `direct_reaction` string under
  `docker-ws/` and `build/sims/proofs` is a DB-migration event name or a relay token-capability entry, never a
  delivered push.

- **Missing coverage.** No device proof that a killed 1:1 recipient is alerted for a reaction.

- **Refuted findings (do NOT re-introduce):**
  - **"Build a new cold-kill leg in `notifications.android_payload_campaign`."** Refuted. The campaign cannot send
    a reaction: `_sendText` (`:2156-2192`) passes only `targetPeerId` + `text`, the e2e protocol's `_actions` set
    holds **eight** verbs (`android_notification_payload_e2e_protocol.dart:25-37`) and none is a reaction, and a
    census of `reaction` over the 3265-line campaign returns one hit — an import at `:13`. Making it send one
    would need a new `lib/core/debug/intro_e2e_runner.dart` handler *and* a `ReactionRepository` threaded through
    the composition root (`send_reaction_use_case.dart:130` requires it; the runner has zero occurrences of the
    symbol). A working vehicle already exists; building a second one is strictly worse.
    *Corrected at review:* the plan previously also argued that `_coldWakeWindowScannedClean` (`:215`, set at
    `:850`, read at `:1401`) structurally denies a second leg its typed diagnosis. That is **overstated** — it is
    a plain mutable field a second leg could reset in one line, and `_runColdPayloadLegClassified` (`:1387`) wraps
    `_runColdPayloadLeg` at exactly one call site (`:261`). It is a one-line obstacle, not an architectural one.
    The refutation rests on the missing reaction capability alone, which is sufficient.
  - **"G22(c), the announcement variant, is a device gap."** Refuted, but **not** for the reason first written.
    The only announcement-specific branch below the push entry point is
    `background_message_handler.dart:3125-3130`: `groupType == 'announcement' ? role == admin : (admin || writer)`.
    *Corrected at review:* the earlier reasoning — "a writer posting into an announcement group is unreachable
    through the product" — is **unsound**. The branch does not read the sender's real authority; it reads the
    RECIPIENT's locally cached member row (`_resolveUniqueGroupMessageSenderForTransport(memberRows: …)` at
    `:3120-3124`), so a promotion that has not yet reached this recipient, a demotion after sending, or a replayed
    push all land on the announcement arm with a cached `writer` role. The guard does real work on a reachable
    path. The conclusion survives on a different fact: **for an admin-role sender row both arms evaluate
    identically**, so a device announcement leg would exercise exactly the same code as a chat leg. The stale-row
    race is a pure-function case a device lane cannot reliably create, and it is already host-covered at
    `background_message_handler_test.dart:4421-4433`. The only other `groupType` consumers (`:3907`, `:3925`) feed
    `group_notification_display_policy.dart:104`, which treats `chat` and `announcement` the same, and
    `_resolveBackgroundSqlEffectAuthority` never reads `groupType`.
  - **"`groupType` might be lost before the gate."** Refuted: `dbLoadGroup`
    (`lib/core/database/helpers/groups_db_helpers.dart:89-102`) issues `db.query('groups', where: 'id = ?')` with
    no column list, so `type` is always present and `background_message_handler.dart:3095` reads it.
  - **"A host row can go causal-RED for the seam itself."** Refuted. The seam is host-covered for all three kinds;
    only the device boundary is missing. This plan's host rows are causal against the **harness**, which is a
    different and real gap.
  - **"`isGroupReactionE2EProbeAction` could drive a 1:1 reaction."** Refuted: it exposes two actions
    (`group_reaction_sqlcipher_observe`, `group_reaction_exact_add_redrive`), is an **observer** not a sender, its
    scenario allow-list is group/announcement only, and its reader keys every row on `groupId`
    (`lib/core/debug/group_reaction_e2e_probe.dart:15-44`, `:98-105`, `:177-241`).
  - **"Register the scenario in `tool/sims/device_criteria.dart`."** Refuted at review — see the de-scope below.
  - **"Add a `critical_features.json` sims capability."** Refuted at review as disproportionate — see the de-scope
    below.

- **Unresolved findings:** whether the graded first wake trips G21. It sits in the G21 slot by construction and
  the trip is intermittent. Owned by the stop-if in Implementation Step 5. Note the lane is in the **better** G21
  position than Plan 383's samples: `_installApk(recipientId, …)` (`:346`) is followed by `_launch(recipientId)`
  (`:351`) before the kill at `:357`, so the graded wake is the **second** process start on that install and
  ProfileInstaller has already run — the confound both of Plan 383's deferring samples carried is absent here.

- **Affected files.** Production-equivalent (harness/driver, **zero `lib/`**):
  `integration_test/scripts/capture_1to1_reaction_head_provenance.dart`,
  `integration_test/scripts/run_1to1_reaction_notification_device.dart`.
  Tests: `test/integration/reaction_notification_proof_support_test.dart`,
  `integration_test/one_to_one_reaction_notification_proof_test.dart` (**edited**, not merely preserved).

## De-scoped at review (with the source proof)

Both were in the first draft. Both are removed, not deferred silently.

1. **`tool/sims/device_criteria.dart` registration — REMOVED.** `validateNotificationArtifact` is **never invoked
   on this lane's artifact**. Its three runtime call sites are `run_notification_tap_device_real.dart:397`,
   `notification_ios_payload_campaign.dart:210` and `notification_android_payload_campaign.dart:2965` — zero in
   either 1:1 file. And the artifact could not pass it anyway: the validator requires top-level `platform`
   (`device_criteria.dart:580`), `devices` with ≥2 entries (`:585`), a `checks` map (`:596`) and reads measured
   evidence from `artifact['evidence']` (`:723`), while `_writePassedArtifact` (`capture:1891-1945`) emits none of
   those four and nests everything under `observation`/`sourceAttribution`. Registering it would have required
   reshaping the artifact — a large change buying a validator this lane never calls.
   **The real oracle is `one_to_one_reaction_notification_proof_test.dart`**, which already speaks this artifact's
   schema and which the runner already executes on every run. That is where the evidence contract now lives
   (TC-391-10).

2. **`tool/sims/critical_features.json` capability — REMOVED, deferred with an owner.** It is not a registration
   edit; it is a sims adapter this runner does not have. Measured: `run_1to1_reaction_notification_device.dart`
   has **0** occurrences of `SIMS_RESULT_JSON`, **0** `Platform.environment` reads and **0** `artifact_evidence`
   imports, against **1**, **11** and an emitted evidence block in `run_notification_tap_device_real.dart`. A
   capability would need the runner to (a) fall back to `SIMS_ANDROID_PHYSICAL_DEVICE_ID` /
   `SIMS_ANDROID_EMULATOR_DEVICE_ID` / `SIMS_PROOF_DIRECTORY` (`tool/sims/device_binding.dart` maps the resource
   locks to those names), (b) print one `SIMS_RESULT_JSON={…}` sentinel or the executor's `_fallbackVerdict`
   fails an `artifactRequired` row even on exit 0, and (c) write an `artifactEvidence` block whose ordered
   `validatorIds` match the manifest (`tool/sims/verdict.dart:185-188`, `executor.dart:603`,
   `artifact_evidence.dart:141-151`). That is a separate plan.
   → **owner: a "1:1 reaction lane sims adoption" plan.** Recorded honestly as the cost: until it lands, this
   lane's coverage is a runner-validated manual command, not a lane-enforced one.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `824c063d72634284`, `freshness=current`; `graphify-arch/.needs_incremental_refresh` absent, so no rebuild was run.
- Query / profile: `python3 graphify-arch/tdd_context.py query "payload_fast_path_cold_kill killed-app cold wake leg _runColdPayloadLeg notification_android_payload_campaign scenario catalog" --profile tdd --budget 700` (`confidence=anchored`), plus one `--profile general --budget 600` refinement for the 1:1 reaction send path.
- Anchors: `_runColdPayloadLeg` → `integration_test/scripts/notification_android_payload_campaign.dart:796`; `message_reaction.dart` → `lib/features/conversation/domain/models/message_reaction.dart`.
- Graph gaps that required raw source search: the whole 1:1 reaction **device** lane. The graph's anchors pointed at the payload campaign and the domain model; `capture_1to1_reaction_head_provenance.dart` and `run_1to1_reaction_notification_device.dart` — the files this plan actually edits — were surfaced only by the refute pass. Scenario-id strings, sims manifest entries and `.sh` pins are outside the graph by construction.
- Reuse rule: anchors are search starting points, not proof. Every `file:line` here was re-read in current source, and the divergence-table cites were **re-pinned at review** (the first draft's were shifted ~6 lines and one range pointed at non-branching code).

## Scope Contract And Guard

**In scope**
- Make `android_typed_reaction_smoke` (TC-13-core-smoke) reachable through the registered runner: catalog row,
  capture-driver switch case, `--live-typed-smoke` forwarding for that scenario only, and an artifact stem that
  matches the scenario id.
- Make the artifact prove its own killed-path premise: a **measured** bool for the recipient's process/activity
  absence, observed immediately before the reaction is driven.
- Give the runner's own validator step a test to run, and put the evidence contract in it.
- One device run on the pinned pair.

**Must preserve**
- `head_provenance` / TC-00 keeps its exact contract, including its deliberate zero-card tolerance, and gains **no
  new failure mode** → `TC-391-06`. (The new absence measurement is non-throwing, so it is safe on the shared
  `!directTextOnly` path; see Test Notes.)
- The typed-smoke ordering freeze at `reaction_notification_proof_support_test.dart:826-845` → `TC-391-07`.
- The four existing proof-test scenarios keep passing → `TC-391-06` covers `head_provenance`; the other three are
  closure-contract delegates untouched by this plan.
- `--direct-text-only` keeps its scenario id `android_direct_text_public_relay`; **its stem is brought into line
  with that id** as part of TC-391-02. Nothing outside the driver consumes either stem — verified by repo grep —
  so this is a rename, not a contract change.

**Hard `Do not`**
- Do **not** add a leg, scenario, action or check to `notifications.android_payload_campaign`.
- Do **not** touch `lib/`.
- Do **not** touch `capture_group_reaction_notification_device.dart`,
  `group_reaction_notification_device_criteria.dart` or `test/integration/group_reaction_*` — Plan 389's surfaces.
- Do **not** re-run or re-own Plan 388's Wave 3 (TC-388-13).
- Do **not** edit `tool/sims/device_criteria.dart` or `tool/sims/critical_features.json` — both de-scoped above
  with source proof. Adding either back is scope drift, not thoroughness.
- Do **not** add a warm-up push, a deferral scan, or a flow-record classifier to this lane. See the stop-if.

**Deferred / accepted difference**
- **Sims-lane adoption for this runner** → owner: a "1:1 reaction lane sims adoption" plan. See the de-scope. The
  accepted difference: this plan's coverage recurs only when someone runs the runner, and TC-391-10 is what makes
  that run self-validating.
- **G22(b) group/announcement MEDIA on the killed path** → owner: a group-media device wave. It needs an
  emulator-role media send that does not exist (`lib/debug/group_notification_projection_e2e_action.dart:80-82`
  rejects every role but `physical_author`, and the physical is the device that lane kills), a `_sendGroupMedia`
  driver that does not exist, and new members in the lifecycle-stage and validator-kind enums in Plan 389's
  `group_reaction_notification_device_criteria.dart`. Its payoff is also contingent:
  `go-relay-server/inbox.go:882-896` degrades an oversized group-media envelope to routing-only
  `preview_unavailable: "1"`, so any media leg must additionally assert which relay branch it took.
- **G22(c) announcement** → **refuted, not deferred.** The map row should be closed as "no distinct device
  obligation".
- **A G21 deferral scan for this lane** → owner: the G21 measurement series. This lane reads recipient logcat only
  via `adb logcat -d` (`capture:963`, `:1779`); a sound scan needs the byte-offset live stream Plan 388 built for
  the payload campaign.

**Dependencies**
- None on Plans 388, 389 or 390. This plan edits four files none of them own, and its curated lane (`groups`) is
  shared with Plan 389, which has landed.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| **TC-391-01** | The registered runner can reach the card-asserting variant — all three links, not just the catalog | `test/integration/reaction_notification_proof_support_test.dart::'the 1to1 reaction runner reaches the typed smoke scenario'` | host / source-slice over `run_1to1_reaction_notification_device.dart` | **causal RED** — the `_scenarios` catalog (`:28-63`) holds five ids and none is `android_typed_reaction_smoke`; the driver `switch` (`:105-113`) has no case for it; the forwarded-option list (`:135-157`) has no `--live-typed-smoke` → **all three** present: the catalog entry with `requiresSender: true` and `testCase: 'TC-13-core-smoke'`, the `'android_typed_reaction_smoke' => _headProvenanceCaptureDriver` case, and a `--live-typed-smoke` append conditioned on `scenario.id == 'android_typed_reaction_smoke'` | delete ANY ONE of the three → TC-391-01 red. The switch case is the one a catalog-only edit leaves out, and its runtime symptom is `exit 78 ENVIRONMENT BLOCKED` at `:114-124` | `flutter test test/integration/reaction_notification_proof_support_test.dart`; already in `GROUP_TESTS` (`run_test_gates.sh:655`) — grep-verify count stays 1 |
| **TC-391-02** | Every capture branch's artifact stem equals its scenario id, so the runner can resolve the result it just captured | `test/integration/reaction_notification_proof_support_test.dart::'each capture branch stem matches its scenario id'` | host / source-slice over `capture_1to1_reaction_head_provenance.dart:278-294` | **causal RED** — typed-smoke pairs stem `live_typed_reaction_smoke` with id `android_typed_reaction_smoke`, and direct-text pairs `direct_text_public_relay` with `android_direct_text_public_relay`, so `_artifactFor` (`run_…:233-242`) resolves neither form and `_validateArtifacts` exits 66 `Missing artifact:` → all three branches have stem == id | revert either stem → TC-391-02 red | as TC-391-01 |
| **TC-391-03** | The artifact records a **measured** bool for the recipient being dead when the reaction was driven | `test/integration/reaction_notification_proof_support_test.dart::'typed smoke measures recipient absence immediately before the reaction drive'` | host / source-slice over the **explicit window** `source.substring(source.indexOf("_stage = 'reaction_capture'"), source.indexOf('_longPressText('))` | **causal RED** — that window (`:379-382`) contains no absence call today, and the `observation` map (`:1921-1933`) has no process-state key → the window contains an assignment from `_recipientProcessAndActivityAbsentWithin(` (`:1390`, returns `Future<bool>`), and `observation` carries `recipientProcessAbsentBeforeReaction` bound to **that identifier**, not a `true` literal | replace the captured variable with the literal `true` → TC-391-03 red. **The window is load-bearing:** a whole-file `contains` would be non-causal because `_requireProcessAndActivityAbsent(recipientId)` already exists verbatim at `:1396` | as TC-391-01 |
| **TC-391-10** | The runner's own post-capture validator has a test for this scenario, and that test is the evidence oracle | `integration_test/one_to_one_reaction_notification_proof_test.dart::'android_typed_reaction_smoke'` | host / the real captured artifact via `--dart-define=MKNOON_256_PROOF_ARTIFACT` | **causal RED** — no such test exists; the file declares five (`:18`, `:87`, `:150`, `:154`, `:158`) and `_validateArtifacts` (`run_…:216-228`) runs `--plain-name android_typed_reaction_smoke`, which matches nothing and exits **79** (measured 2026-08-19), aborting the runner after a successful capture → the test exists and asserts `testCase == 'TC-13-core-smoke'`, `scenario == 'android_typed_reaction_smoke'`, `status == 'passed'`, `app.workingTreeCandidate == true`, `observation.cardPresent == true`, `observation.recipientProcessAbsentBeforeReaction == true`, `observation.typedCopyRequired == true`, `sourceAttribution.providerMatchedEvent == true` | drop the `recipientProcessAbsentBeforeReaction` assertion → an artifact that never observed the kill validates → TC-391-10 red against a fixture with that key false | `flutter test integration_test/one_to_one_reaction_notification_proof_test.dart --plain-name android_typed_reaction_smoke --dart-define=MKNOON_256_PROOF_ARTIFACT=<path>`; existing file, no new registration (the runner invokes it by name) |
| **TC-391-06** | `head_provenance` / TC-00 keeps its exact contract, including deliberate zero-card tolerance, and gains no new failure mode | `integration_test/one_to_one_reaction_notification_proof_test.dart::'head_provenance'` | host / the existing TC-00 artifact validator | **GREEN sentinel** (passes today) → still passes, still asserting `testCase == 'TC-00'`, `scenario == 'head_provenance'`, `cleanCurrentBuild == true`, and its `cardPresent` branch at `:74-83` | post-fix: make the TC-391-03 measurement throw instead of returning a bool (i.e. use `_requireProcessAndActivityAbsent`) → TC-00 runs the shared `!directTextOnly` path and gains a new `_CampaignFailure` → TC-391-06 red | `flutter test integration_test/one_to_one_reaction_notification_proof_test.dart --plain-name head_provenance --dart-define=MKNOON_256_PROOF_ARTIFACT=<path>` — **the `--plain-name` scoping is required**, or the four other scenarios run and fail on missing artifacts |
| **TC-391-07** | The typed-smoke stage order is preserved | `test/integration/reaction_notification_proof_support_test.dart::'Plan 256 live smoke validates typed copy before notification tap'` | host / existing `indexOf` ordering freeze (`:826-845`) | **GREEN sentinel** (passes today) → still passes: `--live-typed-smoke` < `_buildWorkingTreeApks()` < `validateDirectReactionNotificationCard(` < `_tapAndClassifyRoute(cards.single)` < `_captureUnreadLifecycle()` | post-fix: move the TC-391-03 measurement out of the `reaction_capture` window to after `validateDirectReactionNotificationCard(` → this freeze stays green (first-occurrence order is unchanged) but **TC-391-03's explicit window no longer contains it** → TC-391-03 red. The pair is what makes the position guarded from both sides | as TC-391-01 |
| **TC-391-08** | Scope tripwire: the payload campaign is untouched | `test/integration/android_notification_payload_campaign_support_test.dart` (22 rows) + `scripts/test/notification_tap_campaign_adapter_contract_test.sh` | host / source-slice freezes + the ordered `cmp -s` nine-id list (`:21-33`) | **GREEN sentinel** (passes today, and cannot fail for anything this plan does — it is a scope tripwire, not a preservation obligation) → still passes; the nine-id list is unchanged | add any scenario id to `_androidPayloadCampaignScenarios` (`notification_android_payload_campaign.dart:119-129`) → the `cmp -s` at `:32` reds. That file is outside this plan's Affected list, which is the point | `flutter test test/integration/android_notification_payload_campaign_support_test.dart` — **direct command only** (`grep -c` in `run_test_gates.sh` = 0, so no curated lane reaches it); `/claude-host-bin/host-run bash scripts/test/notification_tap_campaign_adapter_contract_test.sh` |
| **TC-391-09** | **PROD-CRITICAL.** A killed 1:1 recipient is alerted for an incoming reaction, on real FCM through the real relay, with the reaction driven by real UI on a second device | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_typed_reaction_smoke --sender 21071FDF600CSC --recipient emulator-5554 --artifact-dir <dir> …` → `<dir>/android_typed_reaction_smoke.json` | **device proof** / pinned physical Android + Android emulator, real relay, real FCM, real SQLCipher | **manual/device-only proof** — the scenario cannot be selected today (TC-391-01) → the runner exits 0, which means the capture passed **and** TC-391-10 validated the artifact it wrote | run it against a build with the TC-391-03 measurement forced to observe a LIVE recipient (relaunch the app between the kill and the drive): the measured bool goes false, TC-391-10 fails, the runner exits non-zero — the leg can no longer claim a killed path it did not observe | the literal command above; no sims registration (de-scoped, see above), so the runner's own `_validateArtifacts` is the enforcement |

**Removed at review:** TC-391-04 (`device_criteria.dart` fixtures) and TC-391-05 (sims capability). Both rested on
surfaces this lane never touches; see *De-scoped at review*. Their evidence obligation moved to TC-391-10.

### Test Notes
- **TC-391-01/02/03/07 are source-slice rows by repo precedent, not by preference.**
  `reaction_notification_proof_support_test.dart` already pins this driver's stage order the same way
  (`:826-845`). These scripts have no importable seam; a behavioral row would need a device. Note honestly that
  `--list-scenarios` (`run_…:70-75`) is **not** a backing gate for TC-391-01: it returns at `:74`, before the
  switch at `:105` and before the arg builder at `:135`, so it proves catalog membership only. The end-to-end
  discriminator for the other two links is TC-391-09 itself.
- **TC-391-03's measurement must not throw.** The `reaction_capture` stage is guarded by `if (!directTextOnly)`
  (`:378`), **not** by `liveTypedSmoke`, so anything inserted there also runs for TC-00.
  `_requireProcessAndActivityAbsent` (`:2596`) returns `Future<void>` and throws `_CampaignFailure`; using it
  would add a new failure mode to a variant this plan promises to preserve. Use the non-throwing
  `_recipientProcessAndActivityAbsentWithin` (`:1390`, `Future<bool>`), record the bool for every variant, and
  assert it only in the typed-smoke proof test. That also makes the artifact honest for TC-00 at no cost.
- **TC-391-03 asserts the relationship, not two facts.** The value must be the measured identifier inside the
  `reaction_capture` window — absence *at the moment the push is sent*. Absence at kill time is already
  established by `_terminateRecipient`'s own `_waitForProcessAndActivityAbsent` (`:1387`) and asserting that again
  would be vacuous.
- **TC-391-09's `--live-typed-smoke` builds from the working tree** (`capture:1899` `workingTreeCandidate: true`),
  unlike TC-00's clean-HEAD build. Both devices receive that build. This is the lane's designed behavior.

### Blind-spot sweep
- **Lifecycle / derived-state durability** — N/A. No new in-memory derived state; the new artifact field is a
  recorded measurement.
- **Sibling-surface consistency** — covered by **TC-391-02**, which asserts stem == id for *all three* capture
  branches. The sibling that does not inherit automatically is `--direct-text-only`, whose stem is renamed with it.
- **Destructive-action side effects** — covered in Rollback. The lane installs a working-tree APK on both devices
  and kills the recipient app; nothing is deleted that a redeploy does not restore.
- **Invariant re-verification under new transitions** — covered by the **TC-391-03 / TC-391-07 pair**: the new
  measurement sits inside a frozen stage order, pinned from both sides.
- **Construction / call-site census** — `GRAPH_OK=1 grep -c 'liveTypedSmoke' integration_test/scripts/capture_1to1_reaction_head_provenance.dart`
  → **17** matching lines (`:95`, `:232`, `:250`, `:280`, `:286`, `:292`, `:308`, `:311`, `:436`, `:442`, `:457`,
  `:803`, `:1898`, `:1899`, `:1930`, `:1931`, `:2817`). Implementation Step 3 re-derives this and confirms the
  stem is consumed only at `:281` plus the `${stem}_failure.json` sites.
- **Build-artifact provenance** — covered by **TC-391-10**, which asserts `app.workingTreeCandidate == true` and
  `app.revision`, and by TC-391-09's requirement of a matched relay/provider send. The proof is defined against
  artifact contents, never a build exit status.
- **Permission / ACL verb symmetry** — N/A. No permission or ACL check is added or changed.
- **Fake side-effect fidelity** — N/A for fixtures: **TC-391-10 validates the real captured artifact**, not a
  hand-written one. (The first draft's hand-written `device_criteria` fixtures were removed precisely because
  they could not mirror what the production writer emits.)
- **Composite-node / relationship assertions** — covered by **TC-391-03** (measurement bound inside the reaction
  window) and **TC-391-02** (stem and id asserted as a pair per branch).

## Implementation Steps

1. Snapshot `git status --short`. Add TC-391-01, -02, -03 and -10 and confirm all four are RED for their
   documented reasons **before** any driver or runner edit (INV-RED-FIRST). Confirm TC-391-06/07/08 are GREEN.
2. `run_1to1_reaction_notification_device.dart`: add the `_Scenario` catalog entry
   (`id: 'android_typed_reaction_smoke'`, `testCase: 'TC-13-core-smoke'`, `requiresSender: true`, summary); add
   `'android_typed_reaction_smoke' => _headProvenanceCaptureDriver` to the `switch` at `:105-113`; append
   `--live-typed-smoke` to `captureArgs` **only** when `scenario.id == 'android_typed_reaction_smoke'`.
3. `capture_1to1_reaction_head_provenance.dart`: change the typed-smoke `_artifactStem` (`:281`) to
   `android_typed_reaction_smoke` and the direct-text stem (`:279`) to `android_direct_text_public_relay`.
   Re-derive the 17-line `liveTypedSmoke` census first and check the `${_artifactStem}_failure.json` sites.
   Stop-if: if any gate, contract or committed artifact path depends on an old stem, teach `_artifactFor` a
   stem→id map instead — do not weaken TC-391-02 to accept a mismatch.
4. `capture_1to1_reaction_head_provenance.dart`: inside the `reaction_capture` stage, after
   `_adb(senderId, ['logcat','-c'])` (`:380`) and **before** `_longPressText(` (`:382`), assign
   `final recipientAbsentBeforeReaction = await _recipientProcessAndActivityAbsentWithin(const Duration(seconds: 5));`
   and add `'recipientProcessAbsentBeforeReaction': recipientAbsentBeforeReaction` to the `observation` map
   (`:1921-1933`). It must be the variable, never a literal, and it must not throw.
   Then add the `android_typed_reaction_smoke` test to `one_to_one_reaction_notification_proof_test.dart`,
   hand-written against this artifact's schema like `head_provenance` at `:18` (not the
   `_validateClosureArtifact` delegate, which speaks a different contract).
5. Run focused GREEN → preservation sentinels → the `groups` lane → the device leg.
   **Stop-if (G21).** If TC-391-09 fails with *"Relay reported a provider send, but 0 active app cards were
   observed"* (`capture:422-428`), that is a G21 trip on the graded first wake, not a defect in this change.
   Record it as the **1:1-reaction sample G21's row asks for**, stop, and let the G21 series own the warm-up. Do
   **not** add a warm-up push, a deferral scan or a classifier to this lane.
   Distinguish it: *"An app card appeared without a matched relay/provider send"* (`:429-435`) and *"The live
   typed smoke requires one matched relay/provider send"* (`:436-441`) are relay-side failures, **not** G21. A
   `Missing artifact:` (exit 66) or a `No tests ran.` (exit 79) is a Step 2-4 wiring miss, not a device result.

## Risks And Blind Spots
- The graded push is the first wake after a kill, so G21 can make this leg fail for an unrelated reason → owned by
  the Step 5 stop-if, with three discriminating failure strings. Mitigating fact: the graded wake is the second
  process start on that install (`:346` install → `:351` launch → `:357` kill), so the ProfileInstaller confound
  in Plan 383's deferring samples is absent.
- The lane's coverage does not recur in any lane until sims adoption lands → accepted, owner named, and TC-391-10
  makes each manual run self-validating in the meantime.
- The Pixel's secure keyguard blocks uiautomator; this lane UI-drives **both** devices → both must be unlocked.
- Lifecycle / derived-state durability: N/A. Sibling-surface consistency: TC-391-02. Destructive-action side
  effects: Rollback. Invariant re-verification: the TC-391-03/07 pair. Call-site census: 17 `liveTypedSmoke`
  lines, re-derived in Step 3. Build-artifact provenance: TC-391-10.

## Gate Cadence
- **Per-plan closure:** the four causal rows + the three sentinels + the `groups` curated lane + the one device
  leg. No `core-host-all` or `feature-host-all` sweep — this plan changes no `lib/` file, so neither scope's glob
  covers anything it touches.
- **Graph-affected first:** run `python3 graphify-arch/tdd_context.py affected` on the two changed scripts after
  the edits and before the lane. Expect a thin or empty result and treat that as information, not reassurance:
  both are `integration_test/scripts/` files outside the arch graph's app-owned corpus.
- **Full `host-all` is not a per-plan gate.** It stays owned by the notification wave that also owns Plans 383-390
  and by final rollout/release closure.
- **Curated-lane reach, verified by grep:** only `test/integration/reaction_notification_proof_support_test.dart`
  is reached by `groups` (`run_test_gates.sh:655`, inside `GROUP_TESTS`).
  `test/integration/android_notification_payload_campaign_support_test.dart` (`grep -c` = 0) and
  `integration_test/one_to_one_reaction_notification_proof_test.dart` are **direct-command only** and get literal
  commands below.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot before execution
git status --short

# --- Causal REDs (before any driver/runner edit) — each must FAIL for its documented reason
flutter test test/integration/reaction_notification_proof_support_test.dart \
  --plain-name 'the 1to1 reaction runner reaches the typed smoke scenario'
flutter test test/integration/reaction_notification_proof_support_test.dart \
  --plain-name 'each capture branch stem matches its scenario id'
flutter test test/integration/reaction_notification_proof_support_test.dart \
  --plain-name 'typed smoke measures recipient absence immediately before the reaction drive'
# TC-391-10 RED — expect "No tests ran." and exit 79 (measured 2026-08-19)
flutter test -d flutter-tester integration_test/one_to_one_reaction_notification_proof_test.dart \
  --plain-name android_typed_reaction_smoke

# --- Focused GREEN (after the edits) — expect exit 0, zero failures
flutter test test/integration/reaction_notification_proof_support_test.dart

# --- Catalog membership only (NOT a gate on the switch case or the flag forwarding)
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios

# --- Graph-affected dependents BEFORE the lane (expect thin/empty; see Gate Cadence)
python3 graphify-arch/tdd_context.py affected \
  integration_test/scripts/capture_1to1_reaction_head_provenance.dart \
  integration_test/scripts/run_1to1_reaction_notification_device.dart --budget 600

# --- Preservation sentinels — expect exit 0
flutter test -d flutter-tester integration_test/one_to_one_reaction_notification_proof_test.dart \
  --plain-name head_provenance --dart-define=MKNOON_256_PROOF_ARTIFACT=<existing tc00 artifact>
flutter test test/integration/android_notification_payload_campaign_support_test.dart
/claude-host-bin/host-run bash scripts/test/notification_tap_campaign_adapter_contract_test.sh

# --- Curated lane — expect exit 0
./scripts/run_test_gates.sh groups

# --- Registration is grep-verified, never run-verified
grep -c 'test/integration/reaction_notification_proof_support_test.dart' scripts/run_test_gates.sh   # expect: 1
./scripts/run_test_gates.sh completeness-check                                                       # expect: PASS, 0 unmatched

# --- Device closure (both devices UNLOCKED; verify before starting)
adb devices                                                  # expect: 21071FDF600CSC + emulator-5554, both "device"
adb -s 21071FDF600CSC shell dumpsys window policy | grep -i secure
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --scenario android_typed_reaction_smoke \
  --sender 21071FDF600CSC --recipient emulator-5554 \
  --artifact-dir build/reaction_notification_proof \
  --relay-target <relay> --relay-key /workspace/se.pem
```

Semantic outcomes: every `flutter test` exits 0 with zero failures except the four RED commands, which must fail
**before** the edits and pass after. `--list-scenarios` must print `android_typed_reaction_smoke` — and proves
only that. `completeness-check` must report 0 unmatched paths (it does not read the sims manifest, and this plan
adds no new test file, so it is hygiene here, not a discriminating gate). The device command must exit 0, which
means the capture passed **and** the runner's own `_validateArtifacts` ran TC-391-10 against the written artifact.

## Rollback
- **Reversible by:** `git revert` of this plan's commit. All four changed files are harness/test code.
- **What a PRIOR shipped build does with post-change data:** N/A — no `lib/` change, no wire format, no schema, no
  stored key. The one new artifact key is read only by the new proof test.
- **NOT recoverable once landed:** nothing. The device run installs a working-tree APK on both devices, replacing
  whatever build they hold; restore with the normal stamped redeploy. The recipient app is killed, which is the
  behavior under test.
- **Staging:** accept the risk. There is no one-way surface left after the sims capability was de-scoped.

## Execution Interpretation And Done Criteria
- **Expected RED:** TC-391-01 fails on the missing catalog entry / switch case / flag; TC-391-02 on the two stem
  mismatches; TC-391-03 on the empty `reaction_capture` window; TC-391-10 with `No tests ran.` and exit 79.
- **GREEN sentinel:** TC-391-06 (`head_provenance`, `--plain-name`-scoped), TC-391-07 (the stage-order freeze),
  TC-391-08 (the payload-campaign scope tripwire).
- **Pre-existing dirty tree / known failure:** `sims-contracts` does **not** exit 0 — contract #26
  (`run_claude_docker_update_contract_test.sh`) is the recorded G28 baseline red and is not this plan's.
- **Environment blocker (NOT a product blocker):** either device missing from `adb devices`, or the Pixel's
  keyguard locked. Hardware outside the live matrix is `N/A (target unavailable by project policy)`.
- **G21 trip:** the Step 5 stop-if. Recorded as a G21 datapoint, not a failure of this plan.
- **Scope drift (BLOCKING):** any failure outside the Scope Contract And Guard — in particular any red in
  `notifications.android_payload_campaign` or Plan 389's group reaction surfaces, or any edit to
  `tool/sims/device_criteria.dart` / `tool/sims/critical_features.json`.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] The device run exits 0, which includes TC-391-10 validating the captured artifact.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected — no `device_criteria.dart` or `critical_features.json` edit.

## Device/Relay Proof Profile
- **Profile:** paired-device (os-notification-device-lab).
- **Boundary being proven:** the `directReaction` arm of the background durable-effect resolver, executing in a
  real cold-started FCM background isolate against real SQLCipher, for a push the real relay produced from a real
  UI-driven reaction on a second device. No host tier reaches it —
  `background_message_handler_test.dart` stubs the eligibility resolver 28 times.
- **Live availability check:** `flutter devices --machine` + `adb devices` → pin the observed ids before running.
- **Pinned targets:** sender (reactor) = physical Android `21071FDF600CSC`; recipient (killed, graded) =
  Android emulator `emulator-5554`. The emulator is the recipient because the lane installs a working-tree APK and
  kills the app repeatedly, and because it is never keyguard-locked. The driver is fully device-id-parameterised —
  a census of `emulator`/`physical`/hard-coded ids over it returns **zero** — so neither role is constrained by
  the code. **Both** devices must be unlocked: the reaction is driven by uiautomator on the sender and the card is
  tapped on the recipient.
- **Automation:** every step — build, install, contact setup, message compose, kill, reaction drive, card grade,
  tap, unread lifecycle — is driven by the capture driver. No user taps.
- **Closure role:** required closure evidence. This is the PROD-CRITICAL leg; host coverage is explicitly **not**
  sufficient on its own.
- **`FLUTTER_DEVICE_ID`:** not applicable — the runner takes `--sender` and `--recipient` explicitly.
- **Registration:** none. `check_reliability_simulation_discovery.sh` already classifies the runner (`:414`,
  `:1190`) and the capture drivers (`:222-224`) — verify, do not assume. Sims-capability adoption is de-scoped
  with a named owner, so `run_with_devices.sh` will **not** list this lane and must not be cited as its gate.
- **Closure command:** the literal `dart run …` in Acceptance Gates → exit 0, and
  `<artifact-dir>/android_typed_reaction_smoke.json` written **flat** (`capture:1944-1945`) with
  `status: passed`, `observation.cardPresent: true`, `observation.recipientProcessAbsentBeforeReaction: true`,
  `observation.typedCopyRequired: true`, `sourceAttribution.providerMatchedEvent: true`.
- **Deferred device work:** G22(b) group/announcement media → group-media device wave. Sims-lane adoption → its
  own plan. iOS legs → GAP-N12.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-19 | RED-first | all four | `flutter test …proof_test.dart --plain-name android_typed_reaction_smoke` → `No tests ran.` **exit 79**; support file → 103 pass / **3 fail** | TC-391-10 red for its documented reason at HEAD; TC-391-01 on the missing catalog id, -02 on `['direct_text_public_relay', 'live_typed_reaction_smoke', …]` vs the ids, -03 on the empty `reaction_capture` window | INV-RED-FIRST satisfied | Steps 2-4 |
| 2026-08-19 | Steps 2-4 | runner, capture driver, both tests | `flutter test …proof_support_test.dart` → **106/106**; `dart analyze` (4 files) clean; `--list-scenarios` prints 6 ids | catalog row + switch case + conditional `--live-typed-smoke`; all three stems == their ids; measured absence bound into `observation` | focused GREEN | mutations |
| 2026-08-19 | Mutations | runner, capture driver | 4 applied, tree restored each time | switch case deleted → -01 red; stem reverted → -02 red; literal `true` → -03 red; measurement moved past `validateDirectReactionNotificationCard(` → **-03 red while -07 stays green** | 4/4 re-red; the -03/-07 pair is guarded from both sides | sentinels |
| 2026-08-19 | Sentinels + lane | — | TC-391-06 passes on a TC-00-shaped artifact with **and** without the new key; TC-391-08 22/22 + `notification_tap_campaign_adapter_contract_test.sh` PASS; `groups` **4580 Flutter + Go gates green**; `completeness-check` 1469/1469; `git diff --check` clean; graph `affected` empty | no captured TC-00 artifact exists in this checkout, so -06 ran against a synthesized artifact matching `_writePassedArtifact`'s exact TC-00 shape | host tier complete; committed `c07c3f588` | device leg |
| 2026-08-20 | Device attempt 1 | — | `dart run …run_1to1_reaction_notification_device.dart --scenario android_typed_reaction_smoke --sender 21071FDF600CSC --recipient emulator-5554` → **failed at stage `wait`**, `Timed out waiting for recipient FCM token registration` | recipient logged `relay_push_registration_success` at 07:49:06Z; the capture still failed at 07:51:12Z | **Blocker 1** — the wait greps a relay line v1.8.0 deleted | repair + TC-391-11 |
| 2026-08-20 | Repair | capture driver, support test | TC-391-11 causal RED → GREEN; mutation re-reds; support **107/107**; analyze clean | registration now attributed on the recipient device's own log, as `capture_group_reaction_notification_device.dart` already does | committed `ed1ca15c5` | re-audit before re-running |
| 2026-08-20 | Pre-flight re-audit | relay source | `grep -rn 'Notification sent to' go-relay-server/` → **zero**; `[PUSH]` census is now `outcome=…` only | `classifyRelayCapture`'s `providerMatchedEvent` can never be true | **Blocker 2 — TC-391-09 is unpassable on any build.** Needs a scope decision | STOP, per the plan's own scope-drift rule |

## Execution Findings (2026-08-20)

Two blockers, both **pre-existing** and neither scoped by this plan. Blocker 1 is fixed. Blocker 2 is not,
because fixing it is a design decision this plan has no mandate for.

**Blocker 1 (FIXED, `ed1ca15c5`).** `_waitForRelayTokenRegistration` greps
`[PUSH] Token registered for <peerPrefix> (android)`. Relay v1.8.0 (`8d86501e4`) deleted it with the rest of the
identifying `[PUSH]` vocabulary, a removal Plan 368 pins. Measured: the recipient logged
`relay_push_registration_success` at 07:49:06Z; the capture still failed at 07:51:12Z. The android arm now waits on
the recipient device's own log through the already-host-tested `androidRelayPushRegistrationAccepted`, which is the
move `capture_group_reaction_notification_device.dart:4820` already made. The `directTextOnly` arm keeps the
relay-journal wait, because its artifact claims a public-relay observation.

**Blocker 2 (OPEN — blocks TC-391-09 on any build, before or after this plan).**
`classifyRelayCapture` (`reaction_notification_proof_support.dart:5076`) derives `providerMatchedEvent` from
`[PUSH] (Group )?Notification sent to <recipientPrefix>`. A recursive census of `Notification sent to` over
`go-relay-server/` returns **zero**: the surviving `[PUSH]` vocabulary is entirely `outcome=…` and carries no peer.
So `providerMatchedEvent` is permanently false, and the typed smoke throws either way —
`'An app card appeared without a matched relay/provider send'` (`capture:429-435`) when the card IS posted, or
`'The live typed smoke requires one matched relay/provider send'` (`capture:436-441`) when it is not. This plan's
stop-if lists both strings as relay-side failures; they are in fact dead-grammar failures.

Two further consequences, recorded because they are not this plan's to fix:
- `providerConfirmedNoSend => relayMatchedEvent && !providerMatchedEvent && !providerFailureMatched`, so **every
  TC-00 capture on the current relay writes a false `providerConfirmedNoSend: true`** — the classifier can no
  longer see any send at all.
- `[INBOX] Stored message for <recipient> from <sender>` (`go-relay-server/inbox.go:2085`) **does** survive, so
  `relayMatchedEvent` and `_waitForRelayStore` still work. Only the provider half is dead.

**Why the fix is a separate plan.** Plan 386 W1 hit this exact wall on the group lane and wrote the reasoning down
(`capture_group_reaction_notification_device.dart:4880-4899`): re-adding the relay lines is the known-wrong fix
(the vocabulary is frozen by `push_permanent_error_closure_test.go:237-300`), and counting the surviving
`[PUSH] outcome=success` is **also** wrong because it carries no attribution and one shared provider path emits it
for every push type and every user on a PRODUCTION box. Its answer was an attributable **relay counter delta**,
`relay_group_reaction_wake_total`. There is no 1:1 equivalent: the counter census over `go-relay-server/` has
`relay_group_reaction_wake_total` and `relay_group_content_wake_total` and **no direct/1:1 reaction wake counter**.
So the choice — add a relay counter and deploy, move provider attribution to the recipient device's own log
(`PUSH_BACKGROUND_MESSAGE_RECEIVED` bound to the reaction event id), or accept the unattributed predicate — changes
`sourceAttribution`'s meaning, touches the shared classifier, its four existing host tests, and TC-00's contract.
That is a plan, not an execution detail.
