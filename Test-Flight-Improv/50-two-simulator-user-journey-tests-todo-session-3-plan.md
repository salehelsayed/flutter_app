# Session 3 Plan: 1:1 media viewer and large-upload journey coverage

## Real scope

- Close the Session 3 coverage gaps for `3.2`, `3.3`, `3.4`, and `3.5` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Keep the work on 1:1 media send/view behavior only: received image/video
  opening, multi-attachment visual selection, and honest large-upload progress
  plus eventual delivery/playability proof.
- Do not widen into text-thread ordering, lifecycle recovery, group media, or
  posts media surfaces.

## Closure bar

Session 3 is good enough when the repo has direct automated evidence that:

- a received image can be opened from the real conversation presentation seam,
- a received video can be opened through the real conversation/viewer seam and
  reaches the video-viewer branch with a playable local file path,
- multi-attachment messages keep per-item open behavior honest instead of
  collapsing every tap to the same viewer target, and
- large media uploads have truthful progress/delivery proof without inventing a
  flaky device-only harness when deterministic current seams are enough.

The session may finish as test-only if the current production code already
behaves correctly and only stronger direct proof is missing.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with current repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The current repo already has meaningful media coverage, but the remaining
Session 3 story is still fragmented:

- `test/features/conversation/integration/media_attachment_flow_test.dart`
  covers send/receive metadata persistence, mixed-media transport, and
  multi-attachment persistence, but it does not directly prove the received
  conversation/viewer opening path.
- `test/shared/widgets/media/full_screen_image_viewer_test.dart` covers the
  image branch and the injected video page builder branch, but not that the
  conversation surface opens the right visual item into that viewer.
- `test/shared/widgets/media/media_grid_test.dart` covers layout and downloaded
  video thumbnail affordance, but not per-item open mapping from a real
  conversation row with multiple visual attachments.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already covers relay upload progress, cancel flow, multi-video processing,
  and upload failure recovery. That is strong current evidence for the
  progress/honest-upload side of `3.5`, so the missing direct proof is more
  likely the end-to-end received/opened side than generic progress UI.

The goal is to add only the minimum direct proofs still missing after this
current-repo refresh.

## Files and repos to inspect next

Production files:

- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/shared/widgets/media/full_screen_image_viewer.dart`
- `lib/shared/widgets/media/media_grid.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`

Primary direct tests:

- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `test/shared/widgets/media/media_grid_test.dart`

Conditional device-backed proof only if still needed:

- `integration_test/media_stable_id_smoke_test.dart`

## Existing tests covering this area

- `test/features/conversation/integration/media_attachment_flow_test.dart`
  already proves image/video/audio attachment metadata survives send/receive
  and that multiple attachments persist on both sides.
- `test/features/conversation/integration/media_retry_smoke_test.dart`
  already proves resumed photo/voice retry flows keep uploaded media attached.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  already proves upload-progress banners, cancel behavior, multi-video batch
  processing, and optimistic attachment persistence.
- `test/shared/widgets/media/media_grid_test.dart` already proves downloaded
  video thumbnails render with play affordance.
- `test/shared/widgets/media/full_screen_image_viewer_test.dart` already proves
  the viewer chooses the image branch for images and the injected video branch
  for video paths.

## Regression/tests to add first

- Add the smallest conversation-surface proof in
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  that tapping a received image or video row pushes the viewer with the correct
  `localPath`, `allPaths`, and visual-item index.
- Extend that same seam, or `test/shared/widgets/media/media_grid_test.dart` if
  cleaner, with a multi-visual-attachment tap proof so item `N` opens item `N`
  instead of always falling back to the first attachment.
- Only add integration-level media send proof in
  `test/features/conversation/integration/media_attachment_flow_test.dart` if
  the viewer/open tests still leave `3.5` short; prefer a narrow "large video
  metadata + delivered receive path stays honest" proof over a flaky transport
  harness.
- Reuse the existing `conversation_wired_test.dart` upload-progress coverage
  rather than duplicating that UI proof unless execution reveals a real gap.

## Step-by-step implementation plan

1. Re-read Session 3 rows in the coverage audit and the current worktree
   versions of the six direct test files above.
2. Reclassify which parts of `3.5` are already closed by current repo evidence
   in `conversation_wired_test.dart` before adding anything new.
3. Prefer widget/screen-seam proof first: open behavior from
   `ConversationScreen` into `FullScreenImageViewer`.
4. Add a multi-attachment tap mapping proof for multiple visual attachments.
5. Add the smallest extra integration proof only if the screen/widget coverage
   still leaves the "large upload eventually delivered/playable" claim short.
6. Run the exact direct Session 3 suites.
7. Run `./scripts/run_test_gates.sh 1to1`.
8. Run `./scripts/run_test_gates.sh transport` only if execution truly widens
   into device-backed media transport or integration-test code.
9. Run `./scripts/run_test_gates.sh baseline` only if execution touches shared
   startup, notification, or app-root routing.

## Risks and edge cases

- Viewer tests can become shallow if they only assert that a navigator push
  happened without checking the selected path/index.
- Multi-attachment tests can accidentally exercise only layout, not per-item
  open behavior.
- Large-upload proof can become flaky if it depends on real media processing or
  device codecs instead of deterministic fake paths and metadata.
- The dirty worktree already includes unrelated media/conversation changes;
  execution must work with them rather than overwriting them.

## Exact tests and gates to run

Direct suites required for Session 3:

```bash
flutter test test/features/conversation/integration/media_attachment_flow_test.dart
flutter test test/features/conversation/integration/media_retry_smoke_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/shared/widgets/media/media_grid_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh 1to1
```

Conditional named gates:

```bash
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh baseline
```

Run `transport` only if accepted changes rely on real device/integration media
proof. Run `baseline` only if execution touches shared startup, notification,
or app-root behavior.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 3 direct suites or the required `1to1` gate fails.
- MissingPluginException noise from avatar/download helpers is not a Session 3
  blocker unless it directly breaks one of the required assertions.

## Done criteria

- Session 3 has direct proof or honest current-repo reclassification for `3.2`,
  `3.3`, `3.4`, and `3.5`.
- The exact direct suites are green.
- `./scripts/run_test_gates.sh 1to1` is green.
- No text-thread, lifecycle, posts, or group-media scope was pulled in.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No text-only conversation/thread work.
- No transport failover or reconnect work unless a direct media proof
  explicitly requires it.
- No group or posts media surfaces.
- No gate-definition edits unless a new permanent direct suite truly needs
  classification.

## Accepted differences / intentionally out of scope

- Session 3 does not need a brand-new simulator orchestrator or real codec lab
  harness if deterministic direct suites already prove the media/viewer
  contract honestly.
- Session 3 does not need to redesign the viewer/player architecture; it only
  needs direct proof around the existing conversation and viewer seams.

## Dependency impact

- Session 3 has no prerequisite session dependency.
- Its outcome informs only the final Session 10 matrix refresh and later
  1:1/media closure wording; it should not reopen Sessions 1 or 2 unless
  execution reveals a shared bug outside the stated scope.
