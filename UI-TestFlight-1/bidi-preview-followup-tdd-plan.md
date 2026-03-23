# BiDi Preview Follow-Up Investigation and Test Plan

**Observed issue:** Mixed Arabic + English text still renders incorrectly in preview-only surfaces after the main BiDi fix shipped.

**Confirmed affected surfaces from current code review:**
- Feed collapsed stack card preview in [collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart)
- Orbit friend-row preview in [friend_row.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/widgets/friend_row.dart)

**High-probability sibling risk:**
- Orbit group-row preview in [group_row.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/widgets/group_row.dart)

**What the previous implementation missed:**
- The earlier BiDi rollout covered message display widgets like `LetterCard`, `MessageBubble`, `QuotePreviewBar`, and compose inputs.
- These preview-only surfaces still render message snippets with plain `Text` and no `textDirection`.
- Orbit preview data still comes from raw DB-backed message text via `ConversationThreadSummary.latestMessage.text`, so older rows may still contain unsafe legacy controls if they were saved before the sanitizer fix.
- Orbit group previews are especially risky because [load_orbit_groups_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_groups_use_case.dart) currently concatenates `senderUsername + ": " + text` into one preview string, which can make first-strong-direction detection choose the sender label instead of the actual message body.

## Goal

Fix all preview surfaces that show message snippets so mixed Arabic + English content renders correctly in:
- Feed collapsed cards
- Orbit friend rows
- Orbit group rows

And add enough test coverage to prevent this class of regression at:
- unit/use-case level
- widget/screen integration level
- platform smoke level

---

## Phase 0: Investigation and Scope Lock

**Goal:** Confirm whether this is only a rendering miss, or partly a legacy stored-data issue.

### 0.1 Reproduce with two message classes

Use both:
- a fresh post-fix message sent from the current build
- an older message already present on the test phone

Test strings:
- Arabic-first mixed: `في نفس الوقت English بكتب عربي`
- English-first mixed: `English first ثم عربي`
- Safe markers preserved: `Hello\u200E مرحبا\u200F`
- Unsafe marker removed: `Hello\u202E مرحبا`

### 0.2 Inspect actual preview payloads

Trace the exact text arriving at:
- `CollapsedModeCardBody._buildPreviewContent()`
- `FriendRow.build()`
- `GroupRow.build()`
- `_buildOrbitFriend()` in [load_orbit_data_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_data_use_case.dart)
- `_buildOrbitGroup()` in [load_orbit_groups_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_groups_use_case.dart)

Confirm:
- whether the preview string still contains unsafe legacy controls
- whether safe markers survive
- whether the text is already sanitized but still rendered incorrectly

### 0.3 Branch decision

If fresh messages fail:
- treat this as a render-path regression first

If only old rows fail:
- add a bounded remediation branch for legacy stored text
- do not guess; document whether remediation should be read-side sanitization, one-time migration, or an admin/dev repair script

**Files to inspect during investigation:**
- [collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart)
- [friend_row.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/widgets/friend_row.dart)
- [group_row.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/widgets/group_row.dart)
- [load_orbit_data_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_data_use_case.dart)
- [load_orbit_groups_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_groups_use_case.dart)
- [message_repository_impl.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository_impl.dart)

---

## Phase 1: Feed Collapsed Preview Fix

**Goal:** Fix the collapsed feed-card preview line so the message body uses content-driven direction.

### 1.1 Write failing tests first

Extend:
- [collapsed_mode_card_body_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart)

Add coverage for:
- Arabic-first mixed preview body renders RTL
- English-first mixed preview body renders LTR
- session-reply preview body renders RTL when reply text starts Arabic
- group collapsed preview keeps sender label separate from body direction
- safe markers remain present in rendered preview text
- preview still ellipsizes correctly in one line

Important assertion detail:
- assert against the preview body widget itself, not just `find.text(...)`
- verify the preview `Text` has the expected `textDirection`

### 1.2 Implementation tasks

Update [collapsed_mode_card_body.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart):
- import and use `detectTextDirection()`
- apply `textDirection` to the preview body widget
- keep `label` and `body` separate so `"You"` or sender names do not influence body-direction detection
- do not change media-preview placeholders unless the preview source is actual message text

### 1.3 Screen-level coverage

Extend at least one real feed composition test:
- [feed_card_flow_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/integration/feed_card_flow_test.dart)
or
- [expanded_collapsed_card_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/integration/expanded_collapsed_card_test.dart)

Add a case where:
- a thread lands in collapsed mode
- the visible single-line preview contains mixed Arabic + English
- the actual rendered preview body uses the correct direction

---

## Phase 2: Orbit Friend Row Fix

**Goal:** Fix friend-list last-message previews in Orbit.

### 2.1 Write failing tests first

Extend:
- [friend_row_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/widgets/friend_row_test.dart)

Add coverage for:
- Arabic-first mixed `lastActivity` renders RTL
- English-first mixed `lastActivity` renders LTR
- preserved safe markers do not get dropped by the preview layer
- one-line ellipsis still works

### 2.2 Implementation tasks

Update [friend_row.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/widgets/friend_row.dart):
- import and use `detectTextDirection()`
- apply `textDirection` directly to the preview `Text`
- leave username and relative-time widgets unchanged

### 2.3 Wired/screen coverage

Extend:
- [orbit_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_wired_test.dart)

Add cases for:
- cold load with a mixed Arabic + English latest message
- incremental refresh after receiving a mixed Arabic + English latest message

Assertions should verify:
- the preview row appears
- the rendered preview widget direction matches the message body

---

## Phase 3: Orbit Group Preview Audit and Fix

**Goal:** Prevent the same bug from surviving in group rows.

### 3.1 Write failing tests first

Create:
- [group_row_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/widgets/group_row_test.dart)

Extend:
- [load_orbit_groups_use_case_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/application/load_orbit_groups_use_case_test.dart)
- one Orbit screen test:
  - [orbit_screen_loading_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_screen_loading_test.dart)
  - or [orbit_screen_archived_groups_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart)

### 3.2 Structural design decision

Do not simply call `detectTextDirection(group.latestMessage)` on the current combined preview string if it still includes a sender prefix.

Choose one of these approaches:
- Preferred: keep sender label and body separate in the UI/model
- Acceptable fallback: preserve a separate message-body field specifically for direction detection while keeping the display string combined

### 3.3 Implementation tasks

Update:
- [load_orbit_groups_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_groups_use_case.dart)
- [orbit_group.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/domain/models/orbit_group.dart) if needed
- [group_row.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/presentation/widgets/group_row.dart)

Requirements:
- detect direction from the actual message body, not the sender prefix
- keep rendering backward-compatible for rows without a latest message
- keep one-line preview truncation intact

---

## Phase 4: Legacy Data Remediation Branch

**Run this phase only if Phase 0 proves old stored rows still contain unsafe controls.**

### 4.1 Decide repair scope

Options to evaluate:
- read-side sanitization when building summaries/previews
- one-time DB migration to sanitize historical `messages.text`
- narrow admin/dev repair script for test and QA devices only

### 4.2 Constraints

Do not silently mutate live message text history without explicitly deciding:
- whether stored text is the canonical message payload
- whether changing old rows affects dedupe, signatures, retry payloads, or user expectations

### 4.3 Minimum test coverage if this branch is taken

Add tests proving:
- historical unsafe chars are removed before preview render
- safe markers still survive
- newer already-sanitized rows are unchanged

Likely files:
- [message_repository_impl.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository_impl.dart)
- [load_orbit_data_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_data_use_case.dart)
- [load_orbit_groups_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/orbit/application/load_orbit_groups_use_case.dart)

---

## Phase 5: Integration and Smoke Coverage Expansion

**Goal:** Cover the real screen compositions that the previous smoke missed.

### 5.1 Extend app-level smoke

Extend:
- [bidi_text_smoke_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/integration_test/bidi_text_smoke_test.dart)

Add real preview scenarios for:
- `CollapsedModeCardBody` with Arabic-first mixed preview
- `CollapsedModeCardBody` with English-first mixed preview
- `FriendRow` with Arabic-first mixed preview
- `FriendRow` with English-first mixed preview
- `GroupRow` mixed preview if Phase 3 changes that path

The previous smoke only covered:
- `MessageBubble`
- `LetterCard`
- `QuotePreviewBar`
- compose inputs

It did **not** cover the problematic screen-level preview widgets from the screenshots.

### 5.2 Device smoke commands

Run on both platforms:

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/bidi_text_smoke_test.dart -d <ios-simulator-id>
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/bidi_text_smoke_test.dart -d <android-device-id>
```

### 5.3 Manual QA checklist

Verify on real Android and iPhone builds:
- Feed collapsed card
- Feed expanded/open card
- Orbit friend row
- Orbit group row
- Conversation message bubbles
- Quote preview bars
- Compose inputs

For each surface:
- Arabic-first mixed text
- English-first mixed text
- text containing preserved safe markers
- text with long enough content to ellipsize

---

## Test Matrix

### Unit / use-case

- [load_orbit_data_use_case_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/application/load_orbit_data_use_case_test.dart)
- [load_orbit_groups_use_case_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/application/load_orbit_groups_use_case_test.dart)
- legacy-data test additions only if Phase 4 is needed

### Widget / screen

- [collapsed_mode_card_body_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart)
- [friend_row_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/widgets/friend_row_test.dart)
- [group_row_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/widgets/group_row_test.dart) (new)
- [feed_card_flow_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/integration/feed_card_flow_test.dart)
- [expanded_collapsed_card_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/feed/integration/expanded_collapsed_card_test.dart)
- [orbit_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_wired_test.dart)
- [orbit_screen_loading_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_screen_loading_test.dart)
- [orbit_screen_archived_groups_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart)

### Platform smoke

- [bidi_text_smoke_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/integration_test/bidi_text_smoke_test.dart)

---

## Minimum Verification Commands

```sh
flutter test test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart
flutter test test/features/orbit/presentation/widgets/friend_row_test.dart
flutter test test/features/orbit/presentation/widgets/group_row_test.dart
flutter test test/features/orbit/application/load_orbit_data_use_case_test.dart
flutter test test/features/orbit/application/load_orbit_groups_use_case_test.dart
flutter test test/features/feed/integration/feed_card_flow_test.dart
flutter test test/features/feed/integration/expanded_collapsed_card_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/bidi_text_smoke_test.dart -d <ios-simulator-id>
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/bidi_text_smoke_test.dart -d <android-device-id>
```

---

## Acceptance Criteria

- No preview surface showing message snippets relies on ambient LTR defaults.
- Feed collapsed preview body uses content-based direction detection.
- Orbit friend preview uses content-based direction detection.
- Orbit group preview, if it includes sender labels, determines direction from the message body rather than the prefixed label.
- Safe BiDi markers remain intact through preview render.
- If legacy stored rows are involved, the remediation path is explicit, tested, and limited in scope.
- iOS and Android smoke runs both pass with the preview scenarios included.
