# GON-003 Plan: New-Member Reactions And Quoted Missing-Parent Context

## real scope

- Extend host-side group onboarding coverage for two post-join side/context paths:
  - a newly-added member receives another current member's reaction to a post-join message
  - a newly-added member receives a post-join quoted reply to a pre-join parent without backfilling the parent, and the UI renders the established missing-parent fallback
- Do not change reaction semantics, quote rendering, simulator coverage, real crypto, or race contracts unless the new tests expose a direct bug.

## closure bar

- `TC-22` and `TC-23` have direct automated evidence.
- Reaction fan-out reaches Bob exactly once for a post-join message and does not create pre-join reaction state.
- Quoted reply evidence is one onboarding scenario: Bob receives the reply, keeps the `quotedMessageId`, does not receive the parent, and the conversation UI renders `Message unavailable`.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-003`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-22 and TC-23.
- Existing coverage: `group_reaction_roundtrip_test.dart`, `group_messaging_smoke_test.dart`, and `group_conversation_screen_test.dart`.

## session classification

`implementation-ready`

## exact problem statement

The repo already proves group reactions and quoted replies in isolation, and it proves late-joiner no-backfill text. It does not combine those behaviors at the onboarding boundary where Bob was not present for the parent message but must receive post-join context safely.

## files and repos to inspect next

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`

## existing tests covering this area

- `group_reaction_roundtrip_test.dart` proves reaction publish/listener roundtrip between existing members.
- `group_messaging_smoke_test.dart` proves quoted replies propagate to existing members and late joiners receive only future text.
- `group_conversation_screen_test.dart` proves missing quoted parents render `Message unavailable`.

## regression/tests to add first

- Extend `group_new_member_onboarding_test.dart` with:
  - a reaction fan-out test using Alice, existing Charlie, and late-joined Bob
  - a quoted-reply onboarding widget test that renders Bob's post-join reply with no parent row

## step-by-step implementation plan

1. Add reaction repositories to the relevant `GroupTestUser` instances.
2. Build a group where Charlie is an existing member and Bob joins after a pre-join message.
3. Send a post-join message, have Charlie react, and assert Bob persists exactly one reaction on that post-join message.
4. Add a quote scenario where Alice sends a pre-join parent, adds Bob, then sends a post-join reply quoting that parent.
5. Assert Bob has the reply and quoted id, not the parent.
6. Render `GroupConversationScreen` with Bob's messages and assert `Message unavailable`.
7. Run the direct onboarding suite.
8. Update source docs, closure docs, and this ledger when the suite passes.

## risks and edge cases

- Reaction delivery uses a separate fake pubsub stream; users need `reactionRepo` wired before listener start.
- Quote UI assertions need localization delegates via a MaterialApp wrapper.
- The session should not turn into broader quote UI redesign or reaction inspection work.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` only if production group reaction/message behavior changes; direct suite is enough for test/doc-only work.

## known-failure interpretation

- A failure in the updated onboarding suite is a session blocker.
- Existing unrelated completeness-check failure for `integration_test/settings_background_choice_smoke_test.dart` remains outside this session.

## done criteria

- Direct onboarding suite passes.
- TC-22 and TC-23 are recorded as covered in the source doc and discussion closure reference.
- Breakdown ledger marks `GON-003` accepted with exact evidence.

## scope guard

- Do not add simulator, real-network, real-crypto, race, foreground-push, or announcement work in this session.
- Do not alter the established missing-parent fallback copy.

## accepted differences / intentionally out of scope

- This is fake-network/widget evidence. Real-network simulator reaction/quote journeys remain later-session work if needed.

## dependency impact

- Later notification, simulator, and race sessions may cite this as host-side onboarding context evidence, but they must still own their separate device or race contracts.
