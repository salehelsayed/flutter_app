• Scope

Implement Option 2 for the "I'm new here" path only. The tap should leave the chooser immediately and enter a dedicated full-screen progress route, while keeping the existing async sequence unchanged: generate identity, generate ML-KEM keys, save identity, then open first-time setup.

Screen Spec

Use a new full-screen route, visually aligned with startup_loading_gate.dart, not the current overlay in identity_choice_wired.dart:145.

Layout:

- Opaque dark gradient background, no ambient animation.
- Centered panel, max width 360, padding 28h x 32v, radius 24.
- Top circular progress affordance: 64x64 halo with 30x30 spinner.
- Title and subtitle centered.
- Two-step vertical progress list under the subtitle.
- No back button, no close affordance, no decorative background motion.

Exact copy:

Stage generating_keys

- Title: Creating your secure identity
- Subtitle: Generating encryption keys on this device. This only happens once.
- Step 1: Generate keys
- Step 2: Save to device
- Footer note: Please keep the app open.

Stage saving

- Title: Securing your identity
- Subtitle: Saving your identity to secure storage.
- Step 1: Generate keys
- Step 2: Save to device
- Footer note: Almost there.

Step states:

- generating_keys: step 1 active, step 2 pending
- saving: step 1 complete, step 2 active

Timing

- Keep the existing card press scale interaction in choice_card.dart:32.
- On tap-up, start route push immediately in the same turn; no added delay before navigation.
- Route transition: reuse the opaque fade from startup_route_transition.dart:7.
    - Push fade: 160ms
    - Reverse fade: 120ms
    - No slide
- Stage text / step-state transition inside the progress route:
    - AnimatedSwitcher or equivalent cross-fade: 180-200ms
- Success handoff:
    - begin immediately when GenerateIdentityResult.success returns from generate_identity_use_case.dart:151
    - replace into first-time setup with the same 160ms opaque fade
    - no extra success screen
- Failure:
    - reverse-fade back to onboarding
    - then show the existing snackbar error on the onboarding route

Widget Responsibilities

identity_choice_wired.dart

- Own the generate tap.
- Push the dedicated progress route immediately.
- Own a ValueNotifier<String> or equivalent stage source for generating_keys / saving.
- Call generateNewIdentity(...) and pipe onProgress into the notifier.
- On success, call a context-aware navigation callback using the progress-route context.
- On failure, dismiss the progress route and show the current snackbar behavior.

New screen: /Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/screens/identity_progress_screen.dart

- Pure presentation for the full-screen progress UI.
- Accept current stage via ValueListenable<String> or a plain stage prop if rebuilt externally.
- Map stage to exact copy and step-state visuals.
- Block back navigation while work is in progress.

startup_router.dart

- Provide a navigation callback that can replace from the progress-route context into FirstTimeExperienceWired.
- Keep deferred P2P startup behavior unchanged after route push.

generate_identity_use_case.dart

- No behavioral change.
- Keep onProgress('generating_keys') and onProgress('saving') as the source of truth.

Smallest File-Level Change Plan

1. Add /Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/identity/presentation/screens/identity_progress_screen.dart
    - new full-screen progress route UI
    - visually based on startup_loading_gate.dart
2. Update identity_choice_wired.dart
    - remove the Stack + inline IdentityLoadingCard generate-path behavior
    - push IdentityProgressScreen instead
    - drive stage updates via notifier
    - keep existing error copy
3. Update startup_router.dart
    - change the IdentityChoiceWired success callback from a zero-arg callback to a context-aware navigation callback
    - use the progress-route context to pushAndRemoveUntil or equivalent into FirstTimeExperienceWired
    - keep _startP2PInBackground() where it is logically today: after route push
4. Reuse startup_route_transition.dart
    - no new transition helper unless naming cleanup is desired later
5. Leave identity_loading_card.dart untouched for now
    - it can remain for restore or be cleaned up in a follow-up
    - not required for the smallest generate-path change

Recommended Tests

- Add /Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/screens/identity_progress_screen_test.dart
    - renders full-screen progress surface
    - shows exact copy for generating_keys
    - shows exact copy for saving
    - blocks back dismissal while busy
- Add or update /Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/identity/presentation/screens/identity_choice_wired_test.dart
    - tapping "I'm new here" pushes the progress route immediately
    - progress route updates from generating_keys to saving
    - success navigates to first-time setup without returning to onboarding
    - failure returns to onboarding and shows snackbar

• TDD Order

  1. Add the new widget contract tests for the progress route.
  2. Add the wired flow tests for immediate route push, stage updates, success, and failure.
  3. Tighten the use-case contract with an exact progress-stage order test.
  4. Implement the new progress screen.
  5. Refactor the generate path in identity_choice_wired.dart.
  6. Adjust the success handoff wiring in startup_router.dart.
  7. Run the focused identity regression suite.

  New Test File
  test/features/identity/presentation/screens/identity_progress_screen_test.dart

  - renders generating progress surface with exact copy and spinner
    Acceptance: finds one CircularProgressIndicator, title Creating your secure identity, subtitle Generating encryption keys on this device. This only happens once., step labels Generate keys and Save to device, footer Please keep the app open., and no onboarding action text.
  - renders saving progress surface with exact copy and step state
    Acceptance: title Securing your identity, subtitle Saving your identity to secure storage., footer Almost there., step 1 rendered as complete, step 2 rendered as active.
  - updates copy when stage changes from generating_keys to saving
    Acceptance: after changing the supplied stage source and pumping, generating copy is gone and saving copy is visible.
  - prevents back navigation while progress is active
    Acceptance: back action returns false or leaves the route mounted; the screen cannot be dismissed while work is running.
  - does not render onboarding choice actions on the progress route
    Acceptance: no "I'm new here" text, no Load my key text, no ChoiceCard widgets.

  Green target: add identity_progress_screen.dart as a pure presentation route driven by stage.

  New Test File
  test/features/identity/presentation/screens/identity_choice_wired_test.dart

  - tap on "I'm new here" pushes progress route before generation completes
    Acceptance: use a Completer-backed generate future; after tap and one pump, the progress route is visible even though the future is still unresolved.
  - progress route advances from generating_keys to saving
    Acceptance: fake callGenerate and callMlKemKeygen so the test can observe generating_keys first, then saving, on the visible progress route.
  - successful generation hands off to main from the progress route context
    Acceptance: onNavigateToMain is invoked after success, the progress route is no longer visible, and onboarding is not visible again before the main handoff.
  - core lib failure dismisses progress route and shows failed to generate identity snackbar
    Acceptance: when generateNewIdentity resolves to coreLibError, the route pops, snackbar text is Failed to generate identity, and onboarding becomes visible again.
  - db save failure dismisses progress route and shows failed to save identity snackbar
    Acceptance: when generateNewIdentity resolves to dbError, the route pops, snackbar text is Failed to save identity, and onboarding becomes visible again.
  - repeated taps while generation is in flight do not push a second progress route
    Acceptance: multiple taps during an unresolved request still leave exactly one progress route / one progress surface mounted.

  Green target: update identity_choice_wired.dart to push the new progress route immediately and drive it from a notifier instead of using the inline Stack overlay.

  Changed Test File
  test/features/identity/application/generate_identity_use_case_test.dart

  - success emits progress stages in generating_then_saving order
    Acceptance: progressStages equals exactly ['generating_keys', 'saving'].

  Green target: no production change expected unless the current stage emission order is not already deterministic in generate_identity_use_case.dart.

  Production Files To Turn Green

  - identity_progress_screen.dart
    Acceptance: implements the full-screen static progress route, exact copy, step-state visuals, and back blocking.
  - identity_choice_wired.dart
    Acceptance: immediate progress-route push on tap, notifier-driven stage updates, correct success and failure handling, duplicate tap suppression.
  - startup_router.dart
    Acceptance: the onboarding success callback can replace from the progress-route context into FirstTimeExperienceWired without briefly resurfacing onboarding.

  No New Tests Required

  - identity_loading_card_test.dart
    Reason: leave the existing overlay widget untouched for now.
  - startup_route_transition_test.dart
    Reason: reuse the existing startup fade helper unchanged.
  - identity_choice_screen_test.dart
    Reason: the chooser screen contract stays the same before the tap.

  Focused Regression Command

  flutter test \
    test/features/identity/presentation/screens/identity_progress_screen_test.dart \
    test/features/identity/presentation/screens/identity_choice_wired_test.dart \
    test/features/identity/application/generate_identity_use_case_test.dart \
    test/features/identity/presentation/screens/identity_choice_screen_test.dart \
    test/features/identity/presentation/navigation/startup_route_transition_test.dart