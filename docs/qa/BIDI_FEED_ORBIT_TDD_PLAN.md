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

- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart` is no longer a red/noisy baseline in the current checkout. It passed during this audit.
- Dedicated `*_bidi_test.dart` files still do not exist in most areas of the tree. The current repo shape relies mainly on broad existing suites; add isolated BiDi files only where the current harness is missing or where a new API shape would otherwise destabilize a broad suite.
- `test/features/feed/presentation/widgets/message_bubble_test.dart` is green, but it still locks in the fragile timestamp overlay by asserting the timestamp lives inside a `Stack`.
- On this machine, `test/features/feed/integration/expanded_collapsed_card_test.dart` and `test/features/feed/integration/feed_card_flow_test.dart` currently fail before test execution because of a Flutter native-assets/Xcode `lipo` issue under `build/native_assets/macos`. Treat that as an environment caveat, not a product verdict.
- The wider worktree is dirty, but the current feed/orbit/posts/share/contact-request/push suites are usable for targeted BiDi planning and regression locks.

## TDD Strategy

### Phase 0: Create stable BiDi-specific test surfaces

Goal: lock a current-tree testing strategy that uses the stable existing suites first, while only adding dedicated BiDi files where isolation is genuinely missing.

Use the existing broad files as the main entry points for the early phases:

- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/inline_reply_input_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/widgets/friend_row_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/share/presentation/share_target_picker_screen_test.dart`
- `test/features/posts/phase2/comments_sheet_test.dart`
- `test/features/posts/phase2/comments_sheet_engagement_test.dart`

Add focused BiDi-specific files only where the current tree still lacks a stable harness or where a new API shape is likely:

- `test/features/orbit/presentation/widgets/group_row_bidi_test.dart`
- `test/features/groups/presentation/group_card_bidi_test.dart`
- `test/features/groups/presentation/group_list_screen_bidi_test.dart`
- `test/features/posts/phase2/comments_sheet_bidi_test.dart`
- Optional current-tree additions when isolation is still useful:
  - `test/features/orbit/presentation/widgets/friend_row_bidi_test.dart`
  - `test/features/posts/phase2/post_card_bidi_test.dart`
  - `test/features/posts/phase5/edit_pinned_post_sheet_bidi_test.dart`
  - `test/features/introduction/presentation/widgets/intro_group_header_test.dart`

Cross-cutting contract for every later phase:

- Every user-entered `TextField` needs Arabic-only, Arabic-first mixed, English-first mixed, and hydrated-`initialText` direction coverage.
- Every user-visible `Text` or `LinkableText` showing user content must pass explicit direction or document why the surface is intentionally direction-agnostic.

### Phase 1: Lock collapsed Feed direction behavior

Use the current green suite first instead of inventing a new harness.

Add failing tests in `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`:

- `session reply preview uses RTL for Arabic-first mixed text`
  - Example text: `مرحبا Hello 123`
- `replied collapsed preview uses RTL for latest outgoing Arabic-first mixed text`
- `read collapsed preview uses RTL for latest incoming Arabic-first mixed text`
- `collapsed preview stays LTR for English-first mixed text`
  - Example text: `Hello مرحبا 123`

Optional top-level regression extension:

- `test/features/feed/integration/expanded_collapsed_card_test.dart`
  - one parity case proving expanded send -> collapsed session preview preserves RTL

Expected implementation after tests fail:

- In `CollapsedModeCardBody`, set `textDirection: detectTextDirection(displayText ?? '')` on the preview body.
- If explicit direction alone is still insufficient on-device, add a small render helper for isolate wrapping and cover it with unit tests before reusing it.

### Phase 2: Lock Orbit direction behavior

Current code already refreshes only the affected Orbit friend on incoming-message updates. This phase is now about adding direction assertions to the existing refresh path and proving the projection stays verbatim.

Add failing tests in `test/features/orbit/presentation/widgets/friend_row_test.dart` or a new `friend_row_bidi_test.dart`:

- `Arabic lastActivity drives RTL`
- `Arabic-first mixed lastActivity drives RTL`
- `English-first mixed lastActivity drives LTR`

Extend the existing refresh-path test in `test/features/orbit/presentation/screens/orbit_wired_test.dart`:

- `incoming mixed Arabic-first message refreshes the row and renders RTL`

Low-level preservation guard:

- Extend `load_orbit_data_use_case_test.dart` with mixed-script preservation checks for both bulk load and snapshot load.

Expected implementation after tests fail:

- In `FriendRow`, set `textDirection: detectTextDirection(friend.lastActivity!)` on the preview text.

### Phase 3: Replace the fragile expanded Feed timestamp layout

Existing body-direction coverage already exists in `test/features/feed/presentation/widgets/message_bubble_test.dart`. The missing work is structural, not heuristic.

Add failing tests in `test/features/feed/presentation/widgets/message_bubble_test.dart` first:

- `outgoing Arabic-only message renders body direction correctly and keeps timestamp/status outside the body paragraph`
- `outgoing Arabic-first mixed message keeps timestamp/status outside the body paragraph`
- `outgoing English-first mixed message stays LTR and still keeps timestamp/status outside the body paragraph`

Assertions:

- Keep the existing Arabic/Arabic-first/English-first body-direction assertions green.
- Remove or rewrite the existing tests that explicitly require timestamp overlay inside a `Stack`.
- Assert that time/status live in a dedicated footer `Row` or equivalent footer container.
- Assert that sender label and body are no longer one bidi paragraph via `prefixSpans`/`suffixSpans`.

Add propagation coverage in `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`:

- `sender-side mixed Arabic/English message preserves body direction and footer time layout through ScrollableMessagePreview`

Expected implementation after tests fail:

- Refactor `MessageBubble` toward the `LetterCard` structure.
- Move timestamp/status out of the overlaid `Stack` and into a footer `Row`.
- Keep the message body as its own bidi paragraph instead of one `LinkableText` with label prefix and trailing spacer spans.
- Keep the sender label out of the same bidi paragraph when possible.

### Phase 4: Prove open/collapsed parity on Feed

Current draft rehydration, send-failure restore, and session-reply clear behavior are already implemented and covered functionally. This phase now adds direction coverage on top of those existing behaviors.

Add failing tests in the current files first:

- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
  - collapsed preview direction matches the open surface for the same mixed-script message
- `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
  - mixed-script contact/group header names render directionally correctly
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
  - mixed-script sender-label/body combinations stay correct for group bubbles
- `test/features/feed/presentation/widgets/inline_reply_input_test.dart`
  - hydrated `initialText` and restored drafts keep the right `TextField.textDirection`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  - send-failure restore preserves text, quote, and restored direction
- `test/features/feed/integration/expanded_collapsed_card_test.dart` or a new `expanded_collapsed_card_bidi_test.dart`
  - open/collapsed/session-reply parity for the same Arabic-first mixed message

Assertions:

- Render the same content in open mode first and collapsed/session-reply mode second, and assert the same direction.
- Cover mixed-script header names and group sender labels separately from message body direction.
- Include one announcement-member Feed case where `canWrite == false` so read-only announcement state is covered alongside the already-tested admin path.

### Phase 5: Cover group and announcement summary previews

Current nuance to preserve:

- `group_list_wired.dart` and the groups-domain summary already keep structured `GroupMessage` data.
- The remaining flattening bugs are in `group_list_screen.dart`, `GroupCard`'s single-string API, and the Orbit projection/model path (`load_orbit_groups_use_case.dart` -> `OrbitGroup` -> `GroupRow`).

Add failing tests:

- `test/features/orbit/presentation/widgets/group_row_bidi_test.dart`
  - `LTR sender plus Arabic-first body remains readable`
  - `Arabic sender plus English-first body stays LTR when body is English-first`
- `test/features/groups/presentation/group_card_bidi_test.dart`
  - `announcement preview separates sender label from Arabic-first mixed body`
  - `group preview keeps English-first body LTR even with mixed sender name`
- `test/features/groups/presentation/group_list_screen_bidi_test.dart`
  - `group list preview does not force a single LTR-biased sender-plus-body string`
- Extend existing regression locks:
  - `test/features/orbit/application/load_orbit_groups_use_case_test.dart`
  - `test/features/orbit/presentation/screens/orbit_wired_test.dart`

Expected implementation after tests fail:

- Stop flattening preview content into one `sender: text` string in `group_list_screen.dart` and in the Orbit projection/model path.
- Update `GroupCard` and, if needed, `OrbitGroup` so sender and body stay separate until render.
- Only after structural separation, apply `detectTextDirection(...)` to the actual body text surface.
- Use both a normal group fixture and a `GroupType.announcement` fixture. Announcement is not a separate renderer in current code; it is a required fixture on the same shared surfaces.

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
- For `EditPinnedPostSheet`, also lock correct first-frame direction from hydrated `initialText`, not only after user typing.

### Phase 7: Cover post comments and sanitization parity

Add failing tests:

- `test/features/posts/phase2/comments_sheet_bidi_test.dart`
  - Composer `TextField` direction tracks Arabic-only and mixed-script comment input.
  - Post summary text in the sheet respects mixed-script direction.
  - Comment body text respects mixed-script direction.
- Extend:
  - `test/features/posts/phase2/send_post_comment_use_case_test.dart`
  - `test/features/posts/phase2/handle_incoming_post_comment_use_case_test.dart`

New behavior to prove:

- Dangerous BiDi controls are stripped from outbound and inbound comment text if posts/comments are meant to match chat/group policy.
- Safe markers remain preserved.

Current-tree note:

- Post comments already have strong non-BiDi coverage for chronology, auto-scroll, engagement, staging, duplicate handling, and recipient fanout.
- This phase is now about direction coverage plus the explicit decision to adopt or reject the existing sanitizer contract for comments.

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
- Sanitize before empty validation, before optimistic insert/save, and before payload/wire-envelope persistence.
- Local-first optimistic rows must use the same sanitized text as the eventual saved/sent message.
- Add one explicit edge case: text that becomes empty after sanitization is rejected unless attachments are present.

### Phase 9: Cover share preview and share-boundary policy

Current-tree reality:

- Warm-start and settled replay are already pass-through routing flows.
- Share conversion already preserves content semantically, but it is not a pure passthrough: it trims some media-share messages, drops empties, and joins multiple text items with `\n`.
- The current missing work is the picker preview direction and an explicit share-boundary policy test.

Add failing tests by extending the existing screen harness:

- `test/features/share/presentation/share_target_picker_screen_test.dart`
  - Shared Arabic text preview drives RTL
  - Shared Arabic-first mixed preview drives RTL
  - Shared English-first mixed preview stays LTR
- `test/core/services/share_intent_service_test.dart`
  - lock the chosen boundary policy and current trim/join normalization
- `test/core/services/share_intent_ios_test.dart`
  - keep the iOS conversion contract aligned with the service-level policy
- Optional end-to-end locks if wanted:
  - `test/features/share/application/handle_share_intent_use_case_test.dart`
  - `test/features/share/application/settle_share_intent_flow_test.dart`

Decision to make explicitly:

- Should external shared text be sanitized at the share boundary, or should the current preserve-plus-trim/join normalization remain the policy?

### Phase 10: Cover intro/contact-request renderers and notification passthrough

Add failing tests:

- Extend `test/features/introduction/presentation/widgets/intro_system_message_test.dart`
  - Arabic system text drives RTL
  - Arabic-first mixed system text drives RTL
  - English-first mixed system text stays LTR
- Extend `test/features/introduction/presentation/widgets/intro_row_test.dart`
  - `displayUsername` direction matches mixed-script content
  - introducer attribution line respects mixed-script username direction
- Prefer adding `intro_group_header_test.dart` over widening `intros_tab_test.dart` when the goal is the header renderer itself.
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
- Notification text generation is treated as a preservation surface, but current behavior already trims surrounding whitespace before forwarding/defaulting.
- The push source reference for this phase is `lib/features/push/application/show_notification_use_case.dart`; there is no separate `notification_body_for_message.dart` production file.
- For `From [username]`, `Introduced by [username]`, and similar English-prefix strings, do not rely on a whole-widget direction check alone. Assert the dynamic username segment behaves correctly inside the mixed static-plus-dynamic surface.

### Phase 11: Align helper and sanitization policy across domains

Current-tree reality:

- The helper layer already exists and is green: `text_direction_utils.dart`, `text_sanitizer.dart`, and `LinkableText.textDirection`.
- Feed and conversation are already ahead on explicit render direction in `MessageBubble` and `LetterCard`.
- The remaining work is policy alignment and eliminating reliance on ambient direction for the remaining user-content call sites.

Decision to make explicitly:

- Should posts, post comments, contact requests, and share-boundary text match chat/group-message sanitization rules for dangerous BiDi controls?

If yes:

- Reuse `sanitizeMessageText(...)` in post, post-comment, contact-request, and any approved share-boundary flows.
- Add unit tests proving parity with the existing chat/group behavior.

If no:

- Record the policy difference in the plan and keep the work limited to UI direction/render fixes.

Also add a helper rule:

- Raw `LinkableText(text: ...)` without explicit `textDirection` should be treated as invalid for user content, even if library-level backward compatibility remains for non-user-content callers.
- Current-tree note: `post_card.dart` is the remaining user-content `LinkableText` call site without explicit direction.
- Keep Phase 11 focused on helper-policy alignment. Feed/orbit/group preview UI acceptance criteria belong to earlier phases, not this one.

## Existing Tests That Will Need Adjustment

- `test/features/feed/presentation/widgets/message_bubble_test.dart`
- `test/shared/widgets/linkable_text_test.dart` if Phase 11 chooses to tighten the user-content contract without removing library-level backward compatibility

Current behavior to remove:

- Tests that explicitly require timestamp overlay inside a `Stack`.

Replacement behavior:

- Tests should require stable body direction and stable footer placement, not the current overlay implementation.
- `LinkableText` tests may keep ambient fallback as a library-level compatibility behavior, but they should not be used as evidence that ambient fallback is acceptable for user-content surfaces.

## Verification Commands

Current-tree tight loop while implementing:

```bash
flutter test test/core/utils/text_direction_utils_test.dart
flutter test test/core/utils/text_sanitizer_test.dart
flutter test test/shared/widgets/linkable_text_test.dart
flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart
flutter test test/features/feed/presentation/widgets/message_bubble_test.dart
flutter test test/features/feed/presentation/widgets/scrollable_message_preview_test.dart
flutter test test/features/feed/presentation/widgets/open_mode_card_body_test.dart
flutter test test/features/feed/presentation/widgets/inline_reply_input_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/orbit/presentation/widgets/friend_row_test.dart
flutter test test/features/orbit/application/load_orbit_data_use_case_test.dart
flutter test test/features/orbit/application/load_orbit_groups_use_case_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/groups/presentation/group_card_test.dart
flutter test test/features/groups/presentation/group_list_screen_test.dart
flutter test test/features/posts/phase1/compose_post_sheet_test.dart
flutter test test/features/posts/phase2/comments_sheet_test.dart
flutter test test/features/posts/phase2/comments_sheet_engagement_test.dart
flutter test test/features/posts/phase2/send_post_comment_use_case_test.dart
flutter test test/features/posts/phase2/handle_incoming_post_comment_use_case_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/share/presentation/share_target_picker_screen_test.dart
flutter test test/core/services/share_intent_service_test.dart
flutter test test/core/services/share_intent_ios_test.dart
flutter test test/features/share/application/handle_share_intent_use_case_test.dart
flutter test test/features/share/application/settle_share_intent_flow_test.dart
flutter test test/features/introduction/presentation/widgets/intro_system_message_test.dart
flutter test test/features/introduction/presentation/widgets/intro_row_test.dart
flutter test test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart
flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart
flutter test test/features/push/application/notification_body_for_message_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart
flutter test test/features/push/application/background_push_notification_fallback_test.dart
```

Broader regression pass after green targeted tests:

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

Known current-machine caveat:

```bash
flutter test test/features/feed/integration/expanded_collapsed_card_test.dart
flutter test test/features/feed/integration/feed_card_flow_test.dart
```

These commands currently fail before test execution on this machine because of a Flutter native-assets/Xcode `lipo` problem under `build/native_assets/macos`. Do not treat that as a Phase 4 product failure.

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
