# 255 - Voice Duration Visible Before Audio Load

Status: accepted
Type: Bug
Spec: free-text intent plus the sender-bubble screenshot supplied on 2026-07-11
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-11 21:48 CEST | Evidence Collector | Graphify snapshot; `record_audio_recorder_service.dart`; `conversation_wired.dart`; `audio_player_widget.dart`; `media_attachment.dart` | The recording and optimistic attachment already contain duration; only the audio widget's asynchronous load gate suppresses the label. | Refute persistence, upload, and listener explanations. |
| 2026-07-11 21:58 CEST | Independent Evidence Collector | send/upload paths; DB/wire mappings; shared audio consumers; existing voice/widget tests | Missing metadata, schema loss, and listener delay are refuted. The shared widget boundary and unavailable-state guard define the narrow fix. | Derive host-only causal and preservation rows. |
| 2026-07-11 22:04 CEST | Planner | `audio_player_widget_test.dart`; `fake_just_audio.dart`; focused voice/source/group sentinels; gate scripts; `00-INDEX.md` | The plan is execution-ready with no migration, native codec, simulator, relay, or device obligation. Shared tests remain directly run and AUTO-discovered; no gate-array edit is needed. | Hand off for independent review or execution. |

## Problem And Evidence

- Behavior to improve: immediately after a sender stops and sends a valid voice
  message, its bubble shows the waveform and play affordance but no useful
  duration until the local audio source finishes loading. The delay can make the
  send look broken and invite a duplicate resend.
- Impact: duration is already trustworthy at record-stop time, so hiding it
  creates avoidable uncertainty on the most trust-sensitive first frame.
- Confirmed root cause: `RecordAudioRecorderService.stop()` returns
  `AudioRecording.durationMs` before send begins at
  `lib/core/media/record_audio_recorder_service.dart:144-164`.
  `_sendVoiceRecording()` copies that value into an optimistic audio attachment
  with a local path and `downloadStatus: 'done'`, inserts the message, and only
  then awaits persistence or transport at
  `lib/features/conversation/presentation/screens/conversation_wired.dart:3799-3839`.
  `AudioPlayerWidget` starts with `_isLoaded == false`, awaits
  `_player.setFilePath()` at
  `lib/shared/widgets/media/audio_player_widget.dart:92-112`, and already
  computes `totalMs` from `attachment.durationMs` at `:215-218`; nevertheless,
  `durationText` requires `_isAvailable && _isLoaded` at `:220-224`, so the
  first frame renders `--:--` until decoder/file probing completes.
- Existing coverage: `send_voice_message_use_case_test.dart::creates
  MediaAttachment with audio mediaType and correct durationMs` proves the
  uploaded voice descriptor retains `5500`; `conversation_audio_source_regression_test.dart::rapid
  outgoing audio insertions load distinct local sources` proves source identity;
  both focused commands were GREEN on current HEAD. The existing
  `audio_player_widget_test.dart::duration label is always present` also passes,
  but its comment explicitly accepts formatted duration or `--:--` and it only
  asserts that some `Text` exists, so it cannot catch this defect.
- Missing coverage: no test holds the platform `load()` future open and asserts
  the exact duration label before readiness, after a source replacement, or
  after player-reported duration becomes authoritative.
- Refuted findings: recorder/send metadata omission is refuted by
  `conversation_wired.dart:3811-3823` and
  `send_voice_message_use_case.dart:115-123`; DB/schema loss is refuted by
  `media_attachment.dart:149-199,214-257`; optimistic persistence preserves the
  field through `copyWith` at `conversation_wired.dart:4663-4683`. A database
  migration, SQLCipher fixture, upload rewrite, or listener reload is therefore
  not part of the fix.
- Unresolved findings: the exact wall-clock decoder latency varies by file and
  device, and the screenshot cannot prove whether a very faint `--:--` is
  present. This is non-blocking because the contract removes decoder readiness
  from known-duration label visibility rather than setting a latency threshold.
- Affected production, test, and gate files:
  `lib/shared/widgets/media/audio_player_widget.dart`,
  `test/shared/widgets/media/audio_player_widget_test.dart`,
  `test/shared/fakes/fake_just_audio.dart`,
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`;
  existing preservation tests in
  `test/features/conversation/presentation/screens/conversation_audio_source_regression_test.dart`
  and `test/features/groups/presentation/group_conversation_screen_test.dart`;
  no gate-script edit.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `4b707ee9eed1e46d`; `stale:lib/features/conversation/presentation/screens/conversation_wired.dart`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "SendVoiceMessageUseCase AudioRecording send_voice_message_use_case.dart audio_recording.dart audio duration metadata immediate sender bubble ConversationWired tests gate registration" --profile tdd --budget 700`.
- Anchors: `AudioRecording` ->
  `lib/features/conversation/domain/models/audio_recording.dart:2`;
  `send_voice_message_use_case.dart` -> the voice upload/send seam;
  `ConversationWired` ->
  `lib/features/conversation/presentation/screens/conversation_wired.dart:209`.
- Surfaced proof/gate files:
  `send_voice_message_use_case.dart`, `audio_recording.dart`,
  `conversation_wired.dart`, `conversation_screen.dart`,
  `media_attachment.dart`, `send_voice_message_use_case_test.dart`, and
  `conversation_wired_bg_task_test.dart`.
- Graph gaps requiring source search: the compact graph did not surface
  `AudioPlayerWidget`, its shared fake/test, the exact duration-label branch, or
  its direct-suite gate classification. Targeted current-source search supplied
  those anchors; graph staleness is recorded rather than upgraded to proof.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- In `AudioPlayerWidget`, display a positive known `totalMs` for an available
  local audio attachment without waiting for `_isLoaded`.
- Keep player-reported positive duration authoritative after load, including
  after a source/path replacement resets player state.
- Add a completer-gated `JustAudioPlatform` test fixture, exact first-frame and
  reload assertions, and strengthen the optimistic direct-voice metadata
  sentinel.
- Because `AudioPlayerWidget` is shared, the same rule intentionally applies to
  available known-duration audio in direct chat, groups, Feed, and Posts; do not
  add a lane-specific flag.

Must preserve:

- Pending/not-local audio retains `--:--` because `_isAvailable` remains part of
  the label condition ->
  `group_conversation_screen_test.dart::renders text plus video, voice, and failed media rows visibly`.
- Null/non-positive duration retains `--:--` until the player reports a positive
  duration ->
  `audio_player_widget_test.dart::unknown available audio keeps placeholder until player reports duration`.
- Play and seek remain disabled until the source really loads; source identity,
  runtime-duration precedence, waveform rendering, retry, quarantine,
  unavailable, and evicted states remain unchanged -> TC-255-01 through
  TC-255-04 and the existing whole-file sentinels.
- The outgoing optimistic attachment still carries recorder duration before any
  LAN/relay work -> TC-255-05.

Hard `Do not`:

- Do not set `_isLoaded` early, seed mutable `_duration` from descriptor
  metadata, or enable play/seek before `setFilePath()` succeeds.
- Do not change recorder timing, upload/send behavior, message/listener merge,
  DB schema/migrations, media serialization, relay/crypto, or native audio code.
- Do not remove `_isAvailable`, turn unknown duration into `0:00`, or rewrite the
  existing pending group expectation to `0:04`.

Deferred / accepted difference:

- Exact device-specific decoder latency measurement -> optional owner: a future
  UI-performance investigation only if loading itself remains visibly slow;
  it is not closure evidence for this deterministic label bug.
- Available shared audio cards gain immediate known-duration parity; pending,
  not-local, integrity-failed, unavailable, and evicted cards deliberately keep
  their existing states.

Dependencies:

- Existing `MediaAttachment.durationMs` and current recorder/voice-pipeline
  propagation are the metadata authority. No new durable state or dependency is
  introduced.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-255-01 | An available outgoing-like attachment with a positive recorded duration shows its exact length while the first local-source load is still unresolved; tapping during that interval does not start playback. | `test/shared/widgets/media/audio_player_widget_test.dart::known attachment duration renders before delayed local source load completes` | widget host / configurable `FakeJustAudioPlatform`, observed load-start plus unresolved completer, `done` attachment with local path and `durationMs: 5500` | HEAD causal RED: `_isAvailable == true` but `_isLoaded == false`, so `--:--` appears -> GREEN shows `0:05`, no `--:--`, while the fake records zero play calls | restore `&& _isLoaded` in the duration-label condition -> TC-255-01 red | `flutter test test/shared/widgets/media/audio_player_widget_test.dart --plain-name 'known attachment duration renders before delayed local source load completes'`; AUTO in later `host-all` glob and `classify_path` = `shared widget direct suite`; direct per-plan, no array edit |
| TC-255-02 | Replacing the local source for the same attachment does not blank a known descriptor duration while the replacement load is pending, and the replacement URI is still loaded distinctly. | `test/shared/widgets/media/audio_player_widget_test.dart::known duration stays visible while replacement audio source loads`; GREEN sentinel `test/features/conversation/presentation/screens/conversation_audio_source_regression_test.dart::rapid outgoing audio insertions load distinct local sources` | widget host / two queued fake load barriers and recorded URIs | New test is a HEAD causal RED after `didUpdateWidget` resets `_duration` and `_isLoaded`: label returns to `--:--` -> GREEN keeps the metadata duration while the fake observes the replacement URI; existing distinct-source sentinel remains GREEN | reintroduce the `_isLoaded` label gate during `_reloadAudioForNewAttachment` -> new TC-255-02 assertion red | `flutter test test/shared/widgets/media/audio_player_widget_test.dart --plain-name 'known duration stays visible while replacement audio source loads'`; `flutter test test/features/conversation/presentation/screens/conversation_audio_source_regression_test.dart --plain-name 'rapid outgoing audio insertions load distinct local sources'`; shared AUTO direct suite, source AUTO (`feature-host-all`/later `host-all`) |
| TC-255-03 | Once loading reports a positive duration, the player duration supersedes optimistic descriptor metadata. | `test/shared/widgets/media/audio_player_widget_test.dart::player duration supersedes attachment duration after delayed load completes` | `GREEN sentinel` widget host / descriptor `5500`, gated player result `6000` | GREEN on HEAD after readiness -> remains GREEN: `0:05` before completion becomes `0:06` after completion | prefer `attachment.durationMs` over positive `_duration.inMilliseconds` -> TC-255-03 red | `flutter test test/shared/widgets/media/audio_player_widget_test.dart --plain-name 'player duration supersedes attachment duration after delayed load completes'`; AUTO shared widget direct suite |
| TC-255-04 | Unknown/non-positive available audio stays honest: placeholder before readiness, then a real player duration only when reported. | `test/shared/widgets/media/audio_player_widget_test.dart::unknown available audio keeps placeholder until player reports duration` | `GREEN sentinel` widget host / null and zero metadata controls with gated `6000` player result | GREEN on HEAD -> remains GREEN: `--:--` and no `0:00` before readiness, then `0:06` | remove the `totalMs > 0` guard or call `formatDurationMs(0)` for unknown metadata -> TC-255-04 red | `flutter test test/shared/widgets/media/audio_player_widget_test.dart --plain-name 'unknown available audio keeps placeholder until player reports duration'`; AUTO shared widget direct suite |
| TC-255-05 | The direct optimistic voice row contains recorder duration before local transfer/relay work, so the first-frame widget has authoritative metadata. | Strengthen `test/features/conversation/presentation/screens/conversation_wired_test.dart::voice send persists upload_pending attachment before local transfer` with `savedAttachment.durationMs == recorder.fakeDurationMs` | `GREEN sentinel` widget host / `FakeAudioRecorderService`, recording repository, ordered local-media spy | GREEN on HEAD -> remains GREEN with `1200` persisted before `sendLocalMedia` | omit `durationMs` from the optimistic attachment or clear it in optimistic persistence -> TC-255-05 red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'voice send persists upload_pending attachment before local transfer'`; AUTO (`feature-host-all`) plus existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` ownership |
| TC-255-06 | A pending/not-local group audio descriptor may contain duration metadata but retains `--:--` rather than appearing ready. | `test/features/groups/presentation/group_conversation_screen_test.dart::renders text plus video, voice, and failed media rows visibly` | `GREEN sentinel` widget host / pending audio with `durationMs: 4200` and no local path | GREEN on HEAD -> remains GREEN with pending `--:--` | drop `_isAvailable` from the label condition -> TC-255-06 red by rendering `0:04` | `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders text plus video, voice, and failed media rows visibly'`; AUTO plus existing `GROUP_TESTS` ownership |
| TC-255-07 | Integrity-failed, terminal-unavailable, and transient-retryable audio keep their dedicated unavailable/retry states instead of rendering the normal player row. | `test/shared/widgets/media/audio_player_widget_test.dart::quarantined (integrity_failed) audio shows the couldn't-verify terminal label and NO retry (INV-DL-3)`; `test/shared/widgets/media/audio_player_widget_test.dart::transient failed audio under the ceiling still exposes a retry affordance`; `test/shared/widgets/media/audio_player_widget_test.dart::terminal download_failed audio shows the unavailable label and NO retry` | `GREEN sentinel` widget host / existing integrity and retry-budget fixtures | GREEN on HEAD -> remains GREEN with dedicated copy/actions and no normal duration row | bypass `_showsUnavailableMedia` before the normal-player branch -> TC-255-07 red | `flutter test test/shared/widgets/media/audio_player_widget_test.dart`; AUTO in later `host-all` and `classify_path` = `shared widget direct suite` |
| TC-255-08 | Evicted audio keeps its removed-copy state and explicit retry instead of rendering the normal player row. | `test/shared/widgets/media/audio_player_widget_test.dart::229: evicted audio shows removed state and explicit retry` | `GREEN sentinel` widget host / existing evicted fixture and retry spy | GREEN on HEAD -> remains GREEN with removed-copy copy/action and no normal duration row | bypass `_isEvicted` before the normal-player branch -> TC-255-08 red | `flutter test test/shared/widgets/media/audio_player_widget_test.dart --plain-name '229: evicted audio shows removed state and explicit retry'`; AUTO in later `host-all` and `classify_path` = `shared widget direct suite` |

### Test Notes

- TC-255-01 through TC-255-04 must install and restore the original
  `JustAudioPlatform.instance`. The fake exposes queued load-start observations,
  caller-controlled completion gates, reported durations, loaded URIs, and play
  calls; tests use explicit pumps and never
  `pumpAndSettle` while a gate is unresolved. Every gate is completed before
  teardown.
- The fake's default constructor behavior remains unchanged for existing users.
  Configurable load delay/duration/play-call recording is opt-in, so this test
  harness change does not rewrite unrelated playback fixtures.
- TC-255-06 is the discriminator for the scope guard: keeping `_isAvailable`
  leaves its current `--:--` expectation GREEN. If implementation instead shows
  metadata on not-local rows, execution must stop and replan rather than update
  that expectation silently.

## Implementation Steps

1. Snapshot `git status --short` and record the substantial pre-existing,
   unrelated worktree changes. Extend the shared fake and replace the vacuous
   `duration label is always present` case with TC-255-01 through TC-255-04
   before production edits. Run TC-255-01 to obtain the causal RED; verify
   TC-255-03/04 and the existing sentinels remain GREEN.
2. Strengthen TC-255-05 without changing production and verify it is GREEN on
   HEAD. Run TC-255-06 before production to pin the pending/not-local boundary.
3. In `AudioPlayerWidget.build`, retain `_isAvailable` and positive-duration
   checks, but remove `_isLoaded` only from idle duration-label visibility.
   Continue choosing positive player `_duration` before
   `attachment.durationMs`; leave play/seek/load state untouched. Stop-if the
   optimistic row lacks a positive duration on current source or the fix would
   require recorder, DB, transport, native, or per-lane changes.
4. Make no gate-array or `classify_path` edit. Verify direct-suite
   classification, later `host-all` discovery, exact focused GREEN, and the
   existing direct/group/source sentinels.
5. Run the proportional `1to1` caller lane, hygiene, representative mutation
   re-reds, restore every mutation, and record semantic outcomes.

## Risks And Blind Spots

- A naive metadata-only label could ignore a more accurate decoded duration ->
  TC-255-03 preserves player precedence.
- A naive condition could expose `0:00` or make pending media look ready ->
  TC-255-04/06 preserve honest placeholders and availability.
- Lifecycle / derived-state durability: `_reloadAudioForNewAttachment()` resets
  in-memory player state; TC-255-02 proves durable attachment metadata continues
  to render through that transition while distinct source loading remains live.
- Sibling-surface consistency: the shared widget policy intentionally covers
  available direct/group/Feed/Post audio without lane forks; TC-255-06 protects
  the different pending/not-local state.
- Destructive-action side effects: N/A — this plan performs no delete, cleanup,
  persistence, or file mutation beyond existing player reads.
- Invariant re-verification under new transitions: TC-255-01/02 re-check label
  visibility while initial and replacement loads are unresolved; TC-255-03/04
  re-check authority and unknown-state rules when duration becomes available.

## Gate Cadence

- Per-plan closure: TC-255-01 causal RED; whole shared-widget GREEN; exact
  optimistic, source-reload, and group-pending sentinels; shared-test discovery
  and completeness classification; `./scripts/run_test_gates.sh 1to1`; hygiene.
  No `core-host-all`, `feature-host-all`, performance sweep, group-wide sweep,
  simulator, or device gate is justified for the single shared label decision.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the named
  **Voice-message trust batch (plan 255 plus any adjacent accepted voice-UI
  follow-ups)**, and once again at final rollout/release closure.
- Shared tests outside feature/core globs:
  `flutter test test/shared/widgets/media/audio_player_widget_test.dart` runs
  directly during this plan and remains AUTO-discovered by later `host-all`.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated worktree changes.
git status --short

# Causal RED before production edits: expect non-zero because HEAD renders
# --:-- instead of 0:05 while the controlled load is unresolved.
flutter test test/shared/widgets/media/audio_player_widget_test.dart \
  --plain-name 'known attachment duration renders before delayed local source load completes'

# Preservation before/after production: expect exit 0 and zero failed tests.
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'voice send persists upload_pending attachment before local transfer'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart \
  --plain-name 'renders text plus video, voice, and failed media rows visibly'
flutter test test/features/conversation/presentation/screens/conversation_audio_source_regression_test.dart \
  --plain-name 'rapid outgoing audio insertions load distinct local sources'

# Focused GREEN: expect exit 0; all causal and existing unavailable-state tests pass.
flutter test test/shared/widgets/media/audio_player_widget_test.dart

# Upstream metadata preservation: expect exit 0 and durationMs 5500 assertion green.
flutter test test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'creates MediaAttachment with audio mediaType and correct durationMs'

# Registration/discovery: expect the shared file to be selected and every host
# test path to have a non-unmatched classification; do not pin inventory counts.
./scripts/run_host_test_gates.sh host-all --dry-run \
  --only test/shared/widgets/media/audio_player_widget_test.dart
./scripts/run_test_gates.sh completeness-check

# Affected direct-message caller lane: expect exit 0 and zero failed commands.
./scripts/run_test_gates.sh 1to1

# Formatting/hygiene: expect no formatting drift, no new analyzer issues, and no
# whitespace errors. Compare analyzer output with the recorded pre-edit baseline
# if unrelated worktree diagnostics already exist.
dart format --output=none --set-exit-if-changed \
  lib/shared/widgets/media/audio_player_widget.dart \
  test/shared/widgets/media/audio_player_widget_test.dart \
  test/shared/fakes/fake_just_audio.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-255-01 fails on exact `0:05` visibility while the fake load
  remains unresolved; plugin exceptions, missing fixtures, or timeouts are not
  an accepted RED.
- Green sentinels: TC-255-03 through TC-255-08 plus the distinct-source and
  upstream metadata tests remain GREEN.
- Pre-existing dirty tree / known failure: many unrelated private-media,
  database, native, and test files were already modified/untracked during
  planning. Execution must snapshot them, touch only plan-owned paths, and
  classify unrelated failures against the pre-edit baseline.
- Environment blocker: none expected; all closure is host-side with a fake
  platform. A real audio plugin/device is not required.
- Scope drift: any need to change recorder/send/DB/native code, remove
  `_isAvailable`, or alter pending group behavior blocks completion and requires
  replanning.

- [x] Every behavior row has the named host proof and semantic result.
- [x] TC-255-01 causal RED, focused GREEN, and representative mutation re-reds
      are recorded; all mutations are restored.
- [x] Availability, unknown-duration, runtime-authority, source-reload, and
      optimistic-metadata sentinels pass.
- [x] Direct-suite classification, later host discovery, and the curated `1to1`
      gate pass.
- [x] No schema, migration, simulator/device, relay, or manual proof is added.
- [x] `flutter analyze` has no new issues; session-owned formatting and
      `git diff --check` are clean, with unrelated pre-existing drift classified.
- [x] Scope Contract And Guard is respected without clobbering unrelated work.

## Handoff

- First causal RED command:
  `flutter test test/shared/widgets/media/audio_player_widget_test.dart --plain-name 'known attachment duration renders before delayed local source load completes'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'voice send persists upload_pending attachment before local transfer'`.
- Manual registration: none. The shared file is directly run, AUTO-discovered by
  later `host-all`, and already classified as `shared widget direct suite`;
  existing direct/group sentinel files retain their current arrays.
- Migration: none.
- Boundary closure: host-only deterministic widget/application proof; no real
  codec, simulator, relay, or mobile device.
- Unresolved evidence: exact device-specific load duration is non-blocking and
  intentionally not a closure threshold.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-11 22:43 CEST | complete | shared audio widget/fake/tests; one conversation assertion | independent QA PASS | RED/GREEN, mutation, preservation, discovery, completeness, and `1to1` evidence complete | accepted; no blocker | wave/release `host-all` only at its normal cadence |

## Execution Result

- Final verdict: **accepted**.
- Execution mode: `tdd-exec (local)`. Assurance mode:
  `independent_qa_only`; independent QA returned PASS with no blocking findings.
- Production change: the duration label now uses available metadata before load,
  while runtime duration remains authoritative and playback/seek remain load-gated.
- Test support: `FakeJustAudioPlatform` gained controllable delayed loads and
  call/source observations. Four causal widget cases cover pre-load metadata,
  source replacement, runtime authority, and unknown duration.
- Preservation proof: the optimistic voice-send test now asserts the saved
  attachment retains the recorder's `durationMs`.

### Evidence

- Causal RED: the exact TC-255-01 command failed on the missing `0:05` label
  (`Expected <1>, Actual <0>`), then passed after the production edit.
- Focused GREEN: `flutter test test/shared/widgets/media/audio_player_widget_test.dart`
  passed all 11 tests.
- Preservation sentinels passed: the named optimistic voice-send, pending group
  bubble, rapid distinct-source, and upstream 5500-ms metadata tests.
- Registration and lanes passed:
  `./scripts/run_host_test_gates.sh host-all --dry-run --only test/shared/widgets/media/audio_player_widget_test.dart`,
  `./scripts/run_test_gates.sh completeness-check` (1174/1174 classified), and
  `./scripts/run_test_gates.sh 1to1` (1962 tests).
- Mutation proof reintroduced the load gate, reversed duration authority, and
  removed availability gating. Each relevant causal/sentinel test re-red; all
  mutations were restored. Logs are under `/tmp/tdd-exec-255/`.
- `git diff --check` passed. Scoped formatting for the three dedicated files
  passed. The exact four-file format command remains nonzero solely because the
  already-dirty conversation test has unrelated pre-existing formatting drift;
  the new assertion itself is formatted and that file was not bulk-rewritten.
- Final `flutter analyze`: 1626 diagnostics and 9 errors, exactly matching the
  pre-edit baseline; all errors are unrelated `SendChatMessageFn` mismatches and
  none target the four scoped files.
- Graphify compact/affected queries informed scope, then
  `./graphify-arch/refresh_arch_graph.sh --incremental` completed successfully.
- Full `host-all` was intentionally deferred to wave/release closure per project
  cadence. No schema, migration, native, relay, device, or simulator work arose.

### QA Disposition

- QA correction N1 applied: analyzer evidence records all 9 pre-existing errors,
  not the initially truncated count of 3.
- QA correction N2 applied: the exact four-file format command is classified as
  pre-existing/non-widening rather than reported as passing.
- Blocking issues: none. Optional implementation follow-up: none.
