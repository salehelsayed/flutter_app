# 93 - Group System Push Preview Sanitization Plan

Status: execution-ready

## Planning Progress

- 2026-05-09 12:03:00 CEST - Evidence Collector started. Files inspected since last update: `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/test-gates-reference.md`, `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`, notification and group-message report evidence from the current session. Decision/blocker: create a narrow TDD plan for raw `{"__sys":...}` group system payloads leaking into notification previews; no blocker. Next action: collect exact current code and direct test seams.
- 2026-05-09 12:11:00 CEST - Evidence Collector completed. Files inspected since last update: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/push/application/push_decrypt_preview.dart`, `test/features/push/application/push_decrypt_preview_test.dart`, `ios/NotificationService/NotificationPreviewResolver.swift`, `ios/RunnerTests/NotificationPreviewResolverTests.swift`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`. Decision/blocker: root cause is confirmed in notification-preview rendering paths; no structural blocker. Next action: draft test-first implementation plan.
- 2026-05-09 12:17:00 CEST - Planner completed. Files inspected since last update: no new files; planner used evidence already captured above. Decision/blocker: plan is a two-platform preview sanitizer with parity tests before implementation; no blocker. Next action: reviewer pass for test sufficiency and scope containment.
- 2026-05-09 12:22:00 CEST - Reviewer completed. Files inspected since last update: plan draft only. Decision/blocker: plan is sufficient if the implementation keeps system bodies unprefixed and never falls back to peer IDs; no blocker. Next action: arbiter decision.
- 2026-05-09 12:25:00 CEST - Arbiter completed. Files inspected since last update: reviewed plan only. Decision/blocker: accepted as execution-ready; no reopen or replan needed. Next action: implement later from this plan using the RED/GREEN sequence.

## Evidence Collector Findings

- Accepting a pending group invite builds the durable system payload at `lib/features/groups/application/accept_pending_group_invite_use_case.dart:525` with `__sys: member_joined`, then stores it for group offline replay at `lib/features/groups/application/accept_pending_group_invite_use_case.dart:573`.
- Normal in-app group replay already recognizes system payloads: `lib/features/groups/application/group_message_listener.dart:307` detects `{"__sys":...}`, and the listener has `member_joined` handling paths at `lib/features/groups/application/group_message_listener.dart:520` and `lib/features/groups/application/group_message_listener.dart:828`.
- Android/background push preview decodes the decrypted group plaintext, reads `payload['text']`, and passes it directly through `pushPreviewBody` before prefixing `senderUsername` in `lib/features/push/application/push_decrypt_preview.dart:131` through `lib/features/push/application/push_decrypt_preview.dart:136`. `pushPreviewBody` returns any non-empty trimmed text as the visible preview at `lib/features/push/application/push_decrypt_preview.dart:158`.
- The iOS Notification Service Extension follows the same shape: `ios/NotificationService/NotificationPreviewResolver.swift:255` decodes the decrypted group plaintext, `ios/NotificationService/NotificationPreviewResolver.swift:265` passes `payload["text"]` to `pushPreviewBody`, and `ios/NotificationService/NotificationPreviewResolver.swift:273` prefixes the sender name for the final notification body.
- Existing tests prove ordinary group plaintext preview but not system payload sanitization: `test/features/push/application/push_decrypt_preview_test.dart:128` expects `Alice: Hello group`, and `ios/RunnerTests/NotificationPreviewResolverTests.swift:38` expects `Alice: Hello secret`.
- Existing gate docs identify `./scripts/run_test_gates.sh groups` as the group messaging gate in `Test-Flight-Improv/test-gate-definitions.md:153`, and `Test-Flight-Improv/test-gates-reference.md:153` records the current unrelated Baseline Gate failure in `integration_test/loading_states_smoke_test.dart`.

## real scope

This is a narrow TDD bug fix for group notification preview rendering after a group invite acceptance creates a `member_joined` system message.

In scope:

- Add test coverage that proves decrypted group system payloads never surface raw `{"__sys":...}` JSON in notification bodies.
- Add Dart background-push preview sanitization in `lib/features/push/application/push_decrypt_preview.dart`.
- Add iOS Notification Service Extension preview sanitization in `ios/NotificationService/NotificationPreviewResolver.swift`.
- Preserve ordinary decrypted group message previews, existing route payloads, thread identifiers, decrypt telemetry shape, and fallback behavior.

Out of direct implementation scope:

- No group membership state changes.
- No relay/APNS payload schema changes.
- No database migration.
- No redesign of in-app system message rendering.

## closure bar

Close this plan only when:

- A failing Dart regression exists first for a decrypted group plaintext whose `text` is a `member_joined` system JSON payload.
- A failing iOS NSE regression exists first for the same condition.
- Both platforms convert the `member_joined` system payload into safe human-readable copy, without visible braces, `__sys`, peer IDs, or raw JSON fragments.
- Unknown `__sys` group payloads also degrade to safe generic group-update copy instead of raw JSON.
- Existing normal group text preview behavior remains unchanged as `senderUsername: preview`.
- Focused Dart and iOS preview tests pass after the implementation.

## source of truth

- Primary bug evidence: the lock-screen screenshot and current-session code investigation showing `member_joined` JSON rendered as notification text.
- Current code paths are authoritative over stale planning claims:
  - `lib/features/groups/application/accept_pending_group_invite_use_case.dart:525`
  - `lib/features/groups/application/accept_pending_group_invite_use_case.dart:573`
  - `lib/features/push/application/push_decrypt_preview.dart:131`
  - `lib/features/push/application/push_decrypt_preview.dart:135`
  - `ios/NotificationService/NotificationPreviewResolver.swift:255`
  - `ios/NotificationService/NotificationPreviewResolver.swift:265`
- Related privacy direction: `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`, with the caveat that its old `pushTitle`/`pushBody` current-state notes no longer match the current code.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md` and `Test-Flight-Improv/test-gates-reference.md`.

## session classification

Implementation-ready, single-session, TDD-first bug fix.

Risk level is medium because the behavior is user-visible on lock screens and duplicated across Dart and Swift, but the implementation surface is narrow and should not require cross-module architecture changes.

## exact problem statement

When a user accepts a pending group invitation, the accept flow emits an internal group system message whose `text` field is JSON like:

```json
{"__sys":"member_joined","member":{"peerId":"12D3...","username":"Rasha"}}
```

That system payload is correct for durable group replay and in-app timeline handling, but the notification preview paths treat every non-empty decrypted group `text` value as user-authored message text. As a result, the group admin can receive a lock-screen notification body containing raw system JSON and peer IDs after the invitee joins.

The intended behavior is that notification preview code recognizes internal group system payloads and renders safe copy, or a generic safe fallback for unknown system event types, without changing group state or relay delivery semantics.

## files and repos to inspect next

Inspect these files before implementation:

- `lib/features/push/application/push_decrypt_preview.dart`
- `test/features/push/application/push_decrypt_preview_test.dart`
- `ios/NotificationService/NotificationPreviewResolver.swift`
- `ios/RunnerTests/NotificationPreviewResolverTests.swift`

Inspect only if a regression fails in an unexpected way:

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `go-relay-server/inbox.go`

## existing tests covering this area

- `test/features/push/application/push_decrypt_preview_test.dart` covers normal 1:1 decrypt preview, leak-safe decrypt telemetry, normal group decrypt preview, fallback behavior, and `pushPreviewBody`.
- `ios/RunnerTests/NotificationPreviewResolverTests.swift` covers iOS NSE normal 1:1 decrypt preview, normal group decrypt preview, fallback behavior, telemetry, and `pushPreviewBody`.
- `test/features/groups/application/group_message_listener_test.dart` covers in-app/durable handling of `member_joined` system messages and proves the system payload itself is expected.
- `test/features/push/application/background_push_notification_fallback_test.dart` covers protected fallback behavior for background push notifications.
- `test/core/notifications/notification_route_contract_matrix_test.dart` covers notification route contract expectations.

The missing test is not group membership correctness. The missing test is preview sanitization for decrypted group system payloads.

## regression/tests to add first

Add these failing tests before production code changes:

1. Dart `member_joined` regression in `test/features/push/application/push_decrypt_preview_test.dart`.
   - Build a `RemoteMessage` with `type: group_message`, valid `groupId`, `message_id`, `keyEpoch`, `ciphertext`, and `nonce`.
   - Make `decryptGroup` return a plaintext JSON object with:
     - `messageId: msg-group-join`
     - `senderUsername: Rasha`
     - `text: jsonEncode({'__sys':'member_joined','member':{'peerId':'12D3...','username':'Rasha'}})`
   - Assert:
     - `resolved.title == backgroundPushDefaultTitle`
     - `resolved.body == 'Rasha joined the group'`
     - `resolved.payload == 'group:group-team|message:msg-group-join'`
     - `resolved.body` does not contain `{`, `}`, `__sys`, `peerId`, or `12D3`.

2. Dart unknown-system regression in the same file.
   - Use a decrypted group plaintext whose `text` is JSON with `__sys: member_role_changed` and a `member.peerId`.
   - Assert `resolved.body == 'Group update'`.
   - Assert no raw JSON or peer ID appears.

3. Swift/iOS `member_joined` regression in `ios/RunnerTests/NotificationPreviewResolverTests.swift`.
   - Reuse the group route fixture style from `testDecryptsGroupFixturePreview`.
   - Build the decrypted plaintext with `JSONSerialization` or a small dictionary helper to avoid fragile nested escaping.
   - Assert:
     - `result.didDecrypt == true`
     - `result.reason == "group"`
     - `result.title == "New Message"`
     - `result.body == "Rasha joined the group"`
     - `result.threadIdentifier == "group-team"`
     - body does not contain `{`, `}`, `__sys`, `peerId`, or `12D3`.

4. Swift/iOS unknown-system regression in the same test file.
   - Use `__sys: member_role_changed`.
   - Assert `result.body == "Group update"` and no raw JSON or peer ID appears.

Keep the existing normal group preview tests unchanged so they guard against accidentally removing `senderUsername: text` formatting for user-authored messages.

## step-by-step implementation plan

1. Run the focused Dart test file once before editing, if quick, to capture the current baseline:

   ```bash
   flutter test test/features/push/application/push_decrypt_preview_test.dart
   ```

2. Add the Dart RED tests listed above to `test/features/push/application/push_decrypt_preview_test.dart`, near the existing `decrypts group ciphertext preview with sender-prefixed body` test.

3. Run the Dart test and confirm the new tests fail because the body contains raw system JSON or `Rasha: { ... }`.

4. Add the Swift RED tests listed above to `ios/RunnerTests/NotificationPreviewResolverTests.swift`, near `testDecryptsGroupFixturePreview`.

5. Run the focused iOS NSE test and confirm the new tests fail for the same reason:

   ```bash
   xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests
   ```

   If `iPhone 17` is unavailable, use an installed iOS simulator destination and record the exact destination used.

6. Implement Dart sanitization in `lib/features/push/application/push_decrypt_preview.dart`.
   - Add a private helper that accepts the decrypted group `text` and optional `senderUsername`.
   - Trim the text and only attempt JSON decode for object-looking strings.
   - If JSON decode fails, return `null` so ordinary text behavior is untouched.
   - If the decoded map has no `__sys`, return `null`.
   - If `__sys == 'member_joined'`, use `member.username` first, then `senderUsername`, and never use `member.peerId` in visible copy.
   - Return `<name> joined the group` when a display name is available, otherwise `A member joined the group`.
   - For any other `__sys`, return `Group update`.
   - In `_resolveGroupPreview`, use the helper before normal `pushPreviewBody`; when it returns a body, use that body directly and do not prefix `senderUsername`.

7. Implement Swift parity in `ios/NotificationService/NotificationPreviewResolver.swift`.
   - Add a private helper with the same behavior and constants:
     - `Rasha joined the group`
     - `A member joined the group`
     - `Group update`
   - Decode only the nested `text` JSON string, not the entire route data again.
   - Return `nil` for malformed JSON or non-system JSON so ordinary messages are unchanged.
   - In `resolveGroup`, call the helper before `pushPreviewBody`; when it returns a body, use it directly and do not prefix `senderUsername`.

8. Re-run the focused Dart and Swift tests until they pass.

9. Re-run adjacent notification contract tests:

   ```bash
   flutter test test/features/push/application/background_push_notification_fallback_test.dart test/core/notifications/notification_route_contract_matrix_test.dart
   ```

10. If implementation changed only preview files and existing preview tests, do not widen the group gate. If any group acceptance, listener, drain, or relay file was changed despite the scope guard, run:

   ```bash
   FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
   ```

11. If a new test file was added instead of extending existing files, also run:

   ```bash
   ./scripts/run_test_gates.sh completeness-check
   ```

## risks and edge cases

- Nested JSON escaping can make tests fragile. Build nested payloads with `jsonEncode` in Dart and `JSONSerialization` or dictionary helpers in Swift where practical.
- Do not parse or display peer IDs as a fallback display name. Peer IDs are technical identifiers and were part of the visible leak.
- Do not treat any arbitrary JSON message as a system event. Only a decoded object with a non-empty `__sys` key should enter the system-preview branch.
- Malformed system-looking text should remain ordinary text only if it cannot be decoded as a valid system object. The bug is valid `__sys` JSON leaking, not every brace-containing chat message.
- Unknown future system events must never leak raw payloads; use `Group update`.
- `senderUsername` prefixing must be skipped for system preview bodies, otherwise `Rasha: Rasha joined the group` is likely.
- Keep decrypt success/failure telemetry leak-safe. Do not add plaintext, usernames, peer IDs, or system JSON to telemetry details.
- Maintain thread routing and notification tap payloads. The preview body fix must not change `group:<groupId>|message:<messageId>` payload construction.

## exact tests and gates to run

Required focused tests:

```bash
flutter test test/features/push/application/push_decrypt_preview_test.dart
```

```bash
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests
```

Required adjacent notification tests:

```bash
flutter test test/features/push/application/background_push_notification_fallback_test.dart test/core/notifications/notification_route_contract_matrix_test.dart
```

Conditional gate if any group membership, listener, drain, replay, or relay file is changed:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

Conditional gate if new test files or gate docs are added:

```bash
./scripts/run_test_gates.sh completeness-check
```

Do not require the Baseline Gate for this narrow preview fix unless a maintainer explicitly asks for a full release sweep.

## known-failure interpretation

- Any failure in `test/features/push/application/push_decrypt_preview_test.dart` after implementation is in scope and must be fixed.
- Any failure in `ios/RunnerTests/NotificationPreviewResolverTests.swift` after implementation is in scope and must be fixed unless it is purely simulator availability.
- If `xcodebuild` cannot find `iPhone 17`, that is an environment selection issue. Switch to an installed simulator and record the destination.
- `Test-Flight-Improv/test-gates-reference.md:153` records the current unrelated Baseline Gate failure: `integration_test/loading_states_smoke_test.dart` fails to build because `StartupRouter` requires `postRepository`. Do not classify that as a regression from this work unless the failure changes shape after this implementation.
- Posts and transport known failures documented in `Test-Flight-Improv/test-gates-reference.md` are not caused by this plan unless this implementation touches those areas, which it should not.

## done criteria

- Dart and Swift RED tests are committed in the implementation session before production code changes.
- Dart and Swift helper behavior is functionally equivalent for:
  - normal group text
  - `member_joined`
  - unknown `__sys`
  - malformed JSON
  - missing member username
- The specific user-visible failure is prevented: notification body never shows `{"__sys":"member_joined"...}`.
- No visible notification body contains peer IDs from system payloads.
- Existing normal group preview tests still pass unchanged.
- Focused and adjacent notification tests pass, or any unrelated environment failure is documented precisely.

## scope guard

Do not change these unless a failing regression proves the preview-only approach cannot work:

- Group invite acceptance semantics.
- Group membership tables or repositories.
- Group offline replay envelope format.
- Relay fanout, APNS, or FCM payload schema.
- In-app group timeline system message handling.
- Notification tap routing format.
- Decrypt telemetry event names or reason strings.

If pressure appears to modify these areas, stop and write a follow-up plan instead of expanding this implementation session.

## accepted differences / intentionally out of scope

- This plan adds preview-safe copy for `member_joined` only; richer human copy for other system event types remains future work.
- Unknown system events render as `Group update`, even if a more specific sentence could be inferred from payload fields.
- The iOS and Dart helpers will duplicate a small amount of logic because the Notification Service Extension cannot directly reuse Dart code.
- Localization is out of scope; this matches the existing English notification preview strings such as `Photo`, `Video`, `Voice message`, and `Message`.
- Notification title remains the existing fallback title for group pushes. This plan changes the body only.

## dependency impact

- Downstream notification privacy work can rely on decrypted group previews no longer exposing internal system JSON or peer IDs.
- Future group system events should add test rows to these same Dart and Swift preview suites before adding event-specific copy.
- No database, relay, or group-membership migration dependency is introduced.

## Reviewer Pass

Sufficiency questions:

- Does the plan identify the actual failing path? Yes. The failure is isolated to decrypted group notification preview rendering in Dart and Swift, not to group membership mutation.
- Are RED tests specified before production edits? Yes. The plan requires failing Dart and iOS tests for `member_joined` and unknown `__sys` payloads before helper implementation.
- Do tests cover the screenshot failure? Yes. The planned body assertions reject raw JSON, `__sys`, braces, `peerId`, and `12D3` fragments.
- Do tests protect existing behavior? Yes. Existing normal group preview tests remain unchanged and adjacent notification route/fallback tests are included.
- Is the implementation scope narrow enough? Yes. The plan explicitly forbids membership, relay, APNS/FCM schema, database, and in-app timeline changes.
- Is there a product-copy ambiguity? Minor but acceptable. The plan chooses `Rasha joined the group` for the known `member_joined` event and `Group update` for unknown system events. If product later wants silent suppression or different copy, that should be a follow-up decision, not a blocker for preventing the raw JSON leak.

Reviewer finding:

- No structural blocker. The implementation session must preserve the unprefixed system body rule; otherwise the fix could produce `Rasha: Rasha joined the group`, which is not the intended closure bar.

## Arbiter Decision

Verdict: execution-ready.

Finding classification:

- Reviewer unprefixed-system-body caution: accepted as a plan constraint, already covered by the closure bar, tests, implementation steps, and risks.
- Product-copy ambiguity: accepted difference, not a blocker. The selected copy is the minimum safe behavior for the confirmed event, and unknown system events intentionally use generic copy.
- Gate scope: accepted. Focused preview tests are mandatory; the wider group gate is conditional because the intended implementation does not touch group membership or replay semantics.

No structural blocker remains. This plan should be implemented as a single TDD session without expanding into relay, group membership, or notification routing rewrites.
