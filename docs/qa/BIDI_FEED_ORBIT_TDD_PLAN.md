# BiDi Cross-Surface TDD Plan

## Scope

User-reported regressions:

1. Sender-side Feed stack card scrambles mixed Arabic/English text when the card is collapsed.
2. Receiver-side Feed stack card shows the same text correctly when open, but scrambled when collapsed.
3. Orbit shows the latest mixed Arabic/English message scrambled for both sender and receiver.
4. Sender-side expanded Feed bubble handles Arabic or mixed Arabic/English timestamp/status layout incorrectly.

This plan is intentionally test-first. It maps each symptom to the exact rendering path, the first failing tests to add, the expected implementation direction, and the verification sequence.

## Current Findings

### Collapsed Feed preview

- Path: `FeedCard -> CollapsedModeCardBody -> _buildPreviewContent`.
- Files:
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `lib/features/feed/domain/models/feed_item.dart`
- Root-cause hypothesis:
  - The collapsed preview body is rendered as plain `Text(displayText)` with no explicit `textDirection`.
  - The expanded/open bubble path does set `detectTextDirection(text)`, which explains why open view can be correct while collapsed view is wrong.
- Impact:
  - Symptom 1 and symptom 2 both hit this same path.
  - Session replies also use this same preview builder, so immediate post-send collapsed state is in scope.

### Expanded Feed bubble

- Path: `ScrollableMessagePreview -> MessageBubble`.
- Files:
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  - `lib/features/feed/presentation/widgets/message_bubble.dart`
  - `lib/shared/widgets/linkable_text.dart`
- Root-cause hypothesis:
  - The body direction is detected correctly.
  - The fragile part is layout: sender label, body text, trailing spacer, timestamp, and status are effectively coupled.
  - `MessageBubble` reserves width inside the paragraph, then paints timestamp/status with `Positioned(right: 0, bottom: 0)` in a `Stack`.
  - That is visually brittle for RTL and mixed-script outgoing messages, especially with the hardcoded LTR `"You"` prefix.
- Strong reference surface:
  - `LetterCard` already uses a safer structure: body in its own `LinkableText`, footer time/status in a separate `Row`.

### Orbit last-message preview

- Path: `ConversationThreadSummary.latestMessage.text -> OrbitFriend.lastActivity -> FriendRow`.
- Files:
  - `lib/features/orbit/application/load_orbit_data_use_case.dart`
  - `lib/features/orbit/presentation/widgets/friend_row.dart`
- Root-cause hypothesis:
  - Orbit does not transform the message text incorrectly.
  - The row renders `friend.lastActivity` with plain `Text` and no explicit `textDirection`.
  - That matches the Feed collapsed-preview failure mode.

## Additional Review Outcomes

### Reference-safe surfaces

- 1:1 conversation bubbles and live compose are still the strongest BiDi baseline in the repo.
  - `ComposeArea` drives `TextField.textDirection` from `detectTextDirection(...)`.
  - `LetterCard` sets direction on body and quote text and uses a separate footer row for time/status.
  - Remaining 1:1 gaps are outside that core pair: outgoing sanitization parity, optimistic local-first sanitization, and `IntroSystemMessage`.
- Main group conversation mostly inherits that same behavior.
  - `GroupConversationScreen` reuses `ComposeArea` and `LetterCard`.
  - Announcement groups in that screen only switch between writable composer and read-only banner.

These surfaces should stay in the plan as reference implementations and regression targets, but they are not the highest-priority new fix areas.

### Additional in-scope surfaces to add

- Feed dynamic-name and draft paths:
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/inline_reply_input.dart`
  - `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - Risk is no longer just message bodies; mixed-script names, sender labels, and restored drafts also need coverage.
- Group and announcement summary previews:
  - `lib/features/groups/presentation/widgets/group_card.dart`
  - `lib/features/groups/presentation/screens/group_list_screen.dart`
  - `lib/features/orbit/presentation/widgets/group_row.dart`
  - Risk is structural: these surfaces flatten preview content into a single `sender: text` string before render.
- Orbit group previews:
  - `lib/features/orbit/presentation/widgets/group_row.dart`
  - `group.latestMessage` is rendered with plain `Text` and no explicit `textDirection`.
- Posts main compose/render:
  - `lib/features/posts/presentation/widgets/compose_post_sheet.dart`
  - `lib/features/posts/presentation/widgets/post_card.dart`
  - `lib/features/posts/presentation/widgets/edit_pinned_post_sheet.dart`
- Post comments:
  - `lib/features/posts/presentation/widgets/comments_sheet.dart`
  - `lib/features/posts/application/send_post_comment_use_case.dart`
  - `lib/features/posts/application/handle_incoming_post_comment_use_case.dart`
- Share preview:
  - `lib/features/share/presentation/screens/share_target_picker_screen.dart`
  - Shared text preview is rendered with plain `Text` and no explicit `textDirection`.
- 1:1 send-side and optimistic consistency:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - Risk is sanitization parity: outgoing and optimistic local-first text can diverge from the already-sanitized inbound policy.
- Intro and contact-request renderers:
  - `lib/features/introduction/presentation/widgets/intro_system_message.dart`
  - `lib/features/introduction/presentation/widgets/intro_row.dart`
  - `lib/features/introduction/presentation/widgets/intro_group_header.dart`
  - `lib/features/contact_request/presentation/widgets/contact_request_dialog.dart`
  - These are plain-`Text` surfaces for dynamic usernames or mixed static-plus-dynamic strings.

### Low-priority or policy-only surfaces

- `lib/features/groups/presentation/widgets/group_compose_area.dart`
  - It lacks direction handling, but it appears to be unused in the current app flow.
  - Keep it as a follow-up only if it becomes wired into production UI.
- `lib/features/posts/presentation/widgets/pass_post_along_sheet.dart`
  - No freeform text entry; this is mostly recipient selection.
  - Do not expand the BiDi fix scope here unless recipient-name direction becomes a separate product issue.
- Notification and push fallback bodies:
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/push/application/background_push_notification_fallback.dart`
  - These surfaces forward text to OS-level notification rendering.
  - Include only as a policy review for sanitization parity, not as a primary in-app layout fix.
- Share picker search field and `ExpandedComposeInput`:
  - Keep these as optional follow-up surfaces.
  - They are lower priority than the active user-content preview and active inline reply paths.

## Baseline Constraints

- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart` is already red on unrelated stale copy assertions.
- `test/features/feed/presentation/widgets/message_bubble_test.dart` is green, but it currently locks in the fragile timestamp overlay by asserting the timestamp lives inside a `Stack`.
- Several broad test files in the worktree are already modified. Avoid relying on or rewriting those files first if a new dedicated BiDi test file can isolate the work.

## TDD Strategy

### Phase 0: Create stable BiDi-specific test surfaces

Goal: avoid blocking on unrelated red tests and avoid entangling this work with stale copy assertions.

Add new focused files first:

- `test/features/feed/presentation/widgets/collapsed_mode_card_body_bidi_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_bidi_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_bidi_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_bidi_test.dart`
- `test/features/orbit/presentation/widgets/friend_row_bidi_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_bidi_test.dart`

Reason:

- This keeps the new TDD loop reliable even while `collapsed_mode_card_body_test.dart` is noisy.
- It also avoids starting by modifying dirty or overly broad test files.
- It creates room for a cross-cutting contract:
  - every user-entered `TextField` needs Arabic-only, Arabic-first mixed, English-first mixed, and hydrated-`initialText` direction tests;
  - every user-visible `Text` or `LinkableText` showing user content must pass explicit direction or justify why not.

### Phase 1: Lock collapsed Feed direction behavior

Add failing tests in `collapsed_mode_card_body_bidi_test.dart`:

- `session reply preview uses RTL for Arabic-first mixed text`
  - Example text: `مرحبا Hello 123`
- `replied collapsed preview uses RTL for latest outgoing Arabic-first mixed text`
- `read collapsed preview uses RTL for latest incoming Arabic-first mixed text`
- `collapsed preview stays LTR for English-first mixed text`
  - Example text: `Hello مرحبا 123`

Assertions:

- Find the exact preview `Text` widget by string match.
- Assert `textDirection` directly.
- Do not assert localized copy like `"You replied"` or `"Tap to expand"`.

Expected implementation after tests fail:

- In `CollapsedModeCardBody`, set `textDirection: detectTextDirection(displayText ?? '')` on the preview body.
- If explicit direction alone is still insufficient on-device, add a small render helper for isolate wrapping and cover it with unit tests before reusing it.

### Phase 2: Lock Orbit direction behavior

Add failing tests in `friend_row_bidi_test.dart`:

- `Arabic lastActivity drives RTL`
- `Arabic-first mixed lastActivity drives RTL`
- `English-first mixed lastActivity drives LTR`

Add one refresh-path test in `orbit_wired_bidi_test.dart`:

- `incoming mixed Arabic-first message refreshes the row and renders RTL`

Optional low-level guard:

- Extend `load_orbit_data_use_case_test.dart` with one case proving mixed-script text is preserved verbatim in `lastActivity`.

Expected implementation after tests fail:

- In `FriendRow`, set `textDirection: detectTextDirection(friend.lastActivity!)` on the preview text.

### Phase 3: Replace the fragile expanded Feed timestamp layout

Add failing tests in `message_bubble_bidi_test.dart`:

- `outgoing Arabic-only message renders body direction correctly and keeps timestamp/status outside the body paragraph`
- `outgoing Arabic-first mixed message keeps timestamp/status outside the body paragraph`
- `outgoing English-first mixed message stays LTR and still keeps timestamp/status outside the body paragraph`

Assertions:

- Keep the body direction assertions.
- Assert the time/status are not descendants of the same `Stack` that owns the body text.
- Prefer asserting a separate footer `Row` or equivalent semantic container.

Add one integration-level propagation test in `scrollable_message_preview_bidi_test.dart`:

- `sender-side mixed Arabic/English message preserves body direction and footer time layout through ScrollableMessagePreview`

Expected implementation after tests fail:

- Refactor `MessageBubble` toward the `LetterCard` structure.
- Move timestamp/status out of the overlaid `Stack` and into a footer `Row`.
- Keep the message body in its own `LinkableText`.
- Keep the sender label out of the same bidi paragraph when possible.

### Phase 4: Prove open/collapsed parity on Feed

Add failing tests in `expanded_collapsed_card_bidi_test.dart`:

- `expanded and collapsed feed views agree on RTL for Arabic-first mixed text`
- `receiver sees correct direction in open view and keeps it after collapse`
- `sender sees correct direction after sending and after session-reply collapse`

Assertions:

- Render the same thread in expanded/open state first and assert direction.
- Re-render in collapsed/read or collapsed/session-reply state and assert the same direction.
- This phase directly covers symptom 1 and symptom 2 end-to-end.
- Extend this phase with additional active Feed risks:
  - `open_mode_card_body.dart`: mixed-script contact/group names in the open-mode header.
  - `scrollable_message_preview.dart`: mixed-script `senderUsername` plus body text in group bubbles.
  - `inline_reply_input.dart` and `feed_wired.dart`: draft rehydration, send-failure restore, and `initialText` direction after restore.
  - Include one announcement-member Feed case where `canWrite == false` so read-only announcement state is covered alongside the writable paths.

### Phase 5: Cover group and announcement summary previews

Add failing tests:

- `test/features/orbit/presentation/widgets/group_row_bidi_test.dart`
  - `LTR sender plus Arabic-first body remains readable`
  - `Arabic sender plus English-first body stays LTR when body is English-first`
- `test/features/groups/presentation/group_card_bidi_test.dart`
  - `announcement preview separates sender label from Arabic-first mixed body`
  - `group preview keeps English-first body LTR even with mixed sender name`
- `test/features/groups/presentation/group_list_screen_bidi_test.dart`
  - `group list preview does not force a single LTR-biased sender-plus-body string`

Expected implementation after tests fail:

- Stop flattening preview content into one `sender: text` string too early.
- Carry sender label and body text separately through projection when possible.
- Only after structural separation, apply `detectTextDirection(...)` to the actual body text surface.

### Phase 6: Cover posts main text input/render

Add failing tests:

- `test/features/posts/phase1/compose_post_sheet_bidi_test.dart`
  - Arabic-only input drives RTL
  - Arabic-first mixed input drives RTL
  - English-first mixed input stays LTR
- `test/features/posts/phase2/post_card_bidi_test.dart`
  - Arabic-only post body drives RTL
  - Arabic-first mixed post body drives RTL
  - English-first mixed post body stays LTR
- `test/features/posts/phase5/edit_pinned_post_sheet_bidi_test.dart`
  - Same input-direction assertions as compose post

Expected implementation after tests fail:

- Drive post text-entry fields from `detectTextDirection(...)`.
- Pass explicit `textDirection` into `LinkableText` for post bodies.

### Phase 7: Cover post comments and sanitization parity

Add failing tests:

- `test/features/posts/phase2/comments_sheet_bidi_test.dart`
  - Composer `TextField` direction tracks Arabic-only and mixed-script comment input.
  - Post summary text in the sheet respects mixed-script direction.
  - Comment body text respects mixed-script direction.
- Extend:
  - `test/features/posts/phase1/send_post_comment_use_case_test.dart`
  - `test/features/posts/phase1/handle_incoming_post_comment_use_case_test.dart`

New behavior to prove:

- Dangerous BiDi controls are stripped from outbound and inbound comment text if posts/comments are meant to match chat/group policy.
- Safe markers remain preserved.

Scope note:

- `pass_post_along_sheet.dart` itself is not a text-entry surface and should not be promoted into the main BiDi implementation scope unless a separate username-direction issue is observed.

### Phase 8: Cover 1:1 send-side sanitization and optimistic parity

Add failing tests:

- Extend `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - dangerous BiDi controls are stripped while safe markers are preserved on outgoing payload/save
  - Arabic-first mixed text survives intact except for dangerous controls
- Extend `test/features/conversation/presentation/screens/conversation_wired_test.dart`
  - optimistic outgoing message is sanitized before first render/save
  - optimistic row and persisted row remain consistent

Implementation target:

- Outgoing 1:1 should match the sanitization contract already enforced for incoming 1:1 and for groups.
- Local-first optimistic rows must use the same sanitized text as the eventual saved/sent message.

### Phase 9: Cover share preview and share-boundary policy

Add failing tests:

- `test/features/share/presentation/share_target_picker_screen_bidi_test.dart`
  - Shared Arabic text preview drives RTL
  - Shared Arabic-first mixed preview drives RTL
  - Shared English-first mixed preview stays LTR

Policy-only tests to consider:

- `test/core/services/share_intent_service_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`

Decision to make explicitly:

- Should external shared text be sanitized at the share boundary, or preserved verbatim and only rendered directionally?

### Phase 10: Cover intro/contact-request renderers and notification passthrough

Add failing tests:

- Extend `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  - Arabic system text drives RTL
  - Arabic-first mixed system text drives RTL
  - English-first mixed system text stays LTR
- Extend `test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `displayUsername` direction matches mixed-script content
  - introducer attribution line respects mixed-script username direction
- Extend `test/features/introduction/presentation/widgets/intros_tab_test.dart` or add `intro_group_header_test.dart`
  - `From [username]` or `Introduced by [username]` stays directionally correct
- Extend `test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart`
  - Arabic username drives RTL
  - Arabic-first mixed username drives RTL
  - English-first mixed username stays LTR
- Extend:
  - `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
  - `test/features/push/application/notification_body_for_message_test.dart`
  - `test/features/push/application/background_push_notification_fallback_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`

Implementation target:

- Intro/contact-request widgets become explicit render-direction surfaces.
- Notification text generation is treated as a preservation surface: mixed-script title/body should survive forwarding unchanged unless the policy says otherwise.

### Phase 11: Align helper and sanitization policy across domains

Decision to make explicitly:

- Should posts, post comments, contact requests, and share-boundary text match chat/group-message sanitization rules for dangerous BiDi controls?

If yes:

- Reuse `sanitizeMessageText(...)` in post, post-comment, contact-request, and any approved share-boundary flows.
- Add unit tests proving parity with the existing chat/group behavior.

If no:

- Record the policy difference in the plan and keep the work limited to UI direction/render fixes.

Also add a helper rule:

- Raw `LinkableText(text: ...)` without explicit `textDirection` should be treated as invalid for user content unless a surface proves it is direction-agnostic.

## Existing Tests That Will Need Adjustment

- `test/features/feed/presentation/widgets/message_bubble_test.dart`

Current behavior to remove:

- Tests that explicitly require timestamp overlay inside a `Stack`.

Replacement behavior:

- Tests should require stable body direction and stable footer placement, not the current overlay implementation.

## Verification Commands

Tight loop while implementing:

```bash
flutter test test/core/utils/text_direction_utils_test.dart
flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_bidi_test.dart
flutter test test/features/orbit/presentation/widgets/friend_row_bidi_test.dart
flutter test test/features/feed/presentation/widgets/message_bubble_bidi_test.dart
flutter test test/features/feed/presentation/widgets/scrollable_message_preview_bidi_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_bidi_test.dart
flutter test test/features/feed/integration/expanded_collapsed_card_bidi_test.dart
```

Broader regression pass after green unit/widget tests:

```bash
flutter test test/features/feed
flutter test test/features/orbit
flutter test test/features/groups/presentation/group_card_test.dart
flutter test test/features/groups/presentation/group_list_screen_test.dart
flutter test test/features/posts
flutter test test/features/share
flutter test test/features/introduction
flutter test test/features/contact_request
flutter test test/features/push/application
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test
```

Known baseline note:

```bash
flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart
```

This currently fails for unrelated stale assertions and should not be used as the entry point for the new BiDi work until those expectations are cleaned up.

## Exit Criteria

- Collapsed Feed preview direction is explicitly tested for sender and receiver mixed-script cases.
- Orbit preview direction is explicitly tested for mixed-script cases.
- Orbit group preview direction is explicitly tested for mixed-script cases.
- Group and announcement summary previews no longer depend on a pre-concatenated `sender: text` string.
- Expanded Feed outgoing bubble no longer depends on timestamp overlay inside the message paragraph.
- Feed open-to-collapsed parity is covered by an integration-style test.
- Feed dynamic names, sender labels, and restored drafts are covered by mixed-script direction tests.
- Post text-entry and post-body render paths are explicitly tested for mixed-script direction.
- Post comments have explicit UI direction coverage and a clear sanitization-policy decision.
- 1:1 outgoing send and optimistic local-first paths have an explicit sanitization contract.
- Shared-text preview surfaces are explicitly tested where users can review mixed-script text before sending.
- Intro/contact-request renderers are explicitly covered as dynamic mixed-script surfaces.
- Mixed-script notification title/body passthrough behavior is explicitly covered or explicitly deferred by policy.
- Raw `LinkableText` ambient-direction fallback is no longer relied on for user content.
- No new implementation depends on ambient app direction for message previews.
