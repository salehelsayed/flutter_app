# 1. Title and Type

- Title: App-Wide Light Theme Screen And Card Readability
- Issue type: bug
- Output doc path: `Test-Flight-Improv/87-app-wide-light-theme-readability.md`

# 2. Problem Statement

Users who select the Daylight Lagoon light background should be able to use every primary screen, card, list row, tab, button, empty state, loading state, and overlay without losing readable text or controls.

Currently, the Orbit screen can render important labels and rows as near-white text on a white or pastel light background. In the reported screenshot, the Orbit `Friends` label, filter tabs, friend row username/message/time, and nearby controls are very low contrast, even though the background itself is visible and the app remains interactive.

This is a product problem because the selected light background makes normal navigation and scanning feel unreliable. Users can miss contacts, messages, group state, tabs, empty-state copy, or action labels simply because foreground and card colors were tuned for dark backgrounds.

# 3. Impact Analysis

- Affected users: anyone who selects Daylight Lagoon, the current production light app background.
- Affected moments: opening Orbit, Feed, Settings, Conversation, group screens, Posts, QR/share/onboarding surfaces, and transient cards or overlays while a light background is active.
- Severity: high for affected screens because the content can become effectively invisible even when the app state is correct.
- Frequency: persistent after selecting a light background until the user switches to a dark background or reaches a surface that already adapts correctly.
- Visible regression: Daylight Lagoon is a production background option, but several user-visible surfaces still contain dark-background-only foreground and glass-card styling.
- User cost: users may not trust whether a list is empty, whether a card is actionable, which tab is active, who sent the latest message, or whether a control is disabled.

# 4. Current State

- The app has a shared selected-background boundary. `AmbientBackground` resolves readable colors from the selected `BackgroundPreference`, injects them through the Flutter theme, applies system chrome, and renders Daylight Lagoon for `BackgroundPreference.daylightLagoon`.
  Evidence: `lib/features/identity/presentation/widgets/ambient_background.dart:62-96`.
- The readable-color contract includes dark and representative-light profiles. Daylight Lagoon resolves to the representative-light profile, which uses dark text/icon colors and dark system chrome icons.
  Evidence: `lib/core/theme/background_readable_colors.dart:80-125`.
- The current shared-background screen inventory includes Feed, Conversation, Posts, Settings, Orbit, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, Group List, Group Conversation, and Group Info.
  Evidence: `test/features/identity/presentation/widgets/ambient_background_test.dart:346-369`.
- That shared-background inventory is not a complete list of user-reachable screens. Additional screen widgets exist outside it, including the introduction friend picker, sent confirmation screen, QR scanner, mnemonic restore input, and identity progress screen.
  Evidence: `lib/features/introduction/presentation/screens/friend_picker_screen.dart:10`, `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart:8`, `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart:10`, `lib/features/identity/presentation/screens/mnemonic_input_screen.dart:4`, `lib/features/identity/presentation/screens/identity_progress_screen.dart:6`.
- Some of those missing surfaces are reachable from active app flows and still use fixed dark styling. Conversation opens the friend picker as a modal sheet and then pushes the sent confirmation screen after introductions are sent; the QR scanner is reachable from Orbit's scan flow and from first-time experience scan flow. The friend picker uses a fixed dark sheet with white foregrounds, the sent confirmation uses a fixed dark scaffold, and the QR scanner uses a camera/dark scanner surface plus fixed dark paste dialog.
  Evidence: `lib/features/conversation/presentation/screens/conversation_wired.dart:982-1022`, `lib/features/introduction/presentation/screens/friend_picker_screen.dart:53-118`, `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart:32-103`, `lib/features/orbit/presentation/screens/orbit_wired.dart:1427-1438`, `lib/features/orbit/presentation/screens/orbit_wired.dart:1478-1490`, `lib/features/home/presentation/screens/first_time_experience_wired.dart:523-535`, `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart:53-130`, `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart:143-177`.
- Prior specs already established the need for background-aware readability and shipped Daylight Lagoon as the first production light background, but the accepted follow-up allowed further visual inventory if remaining background-sensitive assets required image-level assurance.
  Evidence: `Test-Flight-Improv/84-background-readable-theme-extension.md`, `Test-Flight-Improv/86-daylight-lagoon-background-option.md`.
- Orbit has partial light-background support. Its loading placeholders and no-results state read from `context.backgroundReadableColors`.
  Evidence: `lib/features/orbit/presentation/screens/orbit_screen.dart:888-905`, `lib/features/orbit/presentation/screens/orbit_screen.dart:914-1014`.
- Orbit widget coverage currently proves Daylight Lagoon and light-readable loading placeholders, but it does not prove visible Orbit content rows, filters, header labels, search dock, intro banner, archived empty state, friend cards, or group cards remain readable.
  Evidence: `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart:189-235`.
- Orbit visible content still contains hardcoded translucent white text, borders, and card surfaces. Examples include the top `Close Friends` label, intro banner copy, `Friends` header, filter tabs and count badges, friend rows, group rows, archived empty state, and search dock.
  Evidence: `lib/features/orbit/presentation/screens/orbit_screen.dart:367-378`, `lib/features/orbit/presentation/screens/orbit_screen.dart:545-584`, `lib/features/orbit/presentation/widgets/friends_list_header.dart:25-31`, `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart:25-31`, `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart:92-132`, `lib/features/orbit/presentation/widgets/friend_row.dart:34-128`, `lib/features/orbit/presentation/widgets/group_row.dart:35-168`, `lib/features/orbit/presentation/widgets/archived_empty_state.dart:14-42`, `lib/features/orbit/presentation/widgets/orbit_search_dock.dart:30-129`.
- Feed has direct Daylight tests for loading, connection cards, and thread headers, so part of the reported Feed risk is now covered, but the app-wide guarantee is not complete.
  Evidence: `test/features/feed/presentation/screens/feed_screen_test.dart:241-329`.
- Settings and one-to-one Conversation have focused light-background tests for selected chrome/header behavior, but this does not cover every card, row, overlay, or group surface.
  Evidence: `test/features/settings/presentation/screens/settings_screen_test.dart:54-75`, `test/features/settings/presentation/screens/settings_screen_test.dart:179-202`, `test/features/conversation/presentation/screens/conversation_screen_test.dart:214-231`.
- One-to-one Conversation builds actual visible messages through `LetterCard`, and `LetterCard` still has fixed translucent white card surfaces, borders, sender text, transport icons, deleted-message text, and other pale foregrounds. That leaves message content, quote/reply states, failed/deleted states, media/audio cards, and reaction surfaces outside the current Daylight header-only proof.
  Evidence: `lib/features/conversation/presentation/screens/conversation_screen.dart:517-552`, `lib/features/conversation/presentation/widgets/letter_card.dart:83-92`, `lib/features/conversation/presentation/widgets/letter_card.dart:181-201`, `lib/features/conversation/presentation/widgets/letter_card.dart:207-230`, `lib/features/conversation/presentation/widgets/letter_card.dart:231-244`.
- Group surfaces still show the same class of dark-background-only colors in headers, empty states, loading rows, group cards, pending invite cards, and group conversation banners.
  Evidence: `lib/features/groups/presentation/screens/group_list_screen.dart:68-116`, `lib/features/groups/presentation/screens/group_list_screen.dart:220-305`, `lib/features/groups/presentation/screens/group_conversation_screen.dart:217-288`, `lib/features/groups/presentation/screens/group_conversation_screen.dart:310-367`, `lib/features/groups/presentation/widgets/group_card.dart:38-226`, `lib/features/groups/presentation/widgets/pending_group_invite_card.dart:26-137`.
- Group Info is part of the shared-background inventory and uses fixed white or muted-white header, title, description, member row, admin action, and member action styling in its main content path.
  Evidence: `lib/features/groups/presentation/screens/group_info_screen.dart:100-118`, `lib/features/groups/presentation/screens/group_info_screen.dart:141-164`, `lib/features/groups/presentation/screens/group_info_screen.dart:176-184`, `lib/features/groups/presentation/widgets/group_member_row.dart:36-47`, `lib/features/groups/presentation/widgets/group_member_row.dart:61-95`.
- Several other shared-background surfaces named in the acceptance inventory also have fixed dark-background foreground assumptions. Share Target Picker uses fixed white header, preview, caption, search, loading, empty, row, and action styling; Create Group Picker and Contact Picker wrap `AmbientBackground` while still using fixed white headers and fixed white creation/invite processing states; First Time Experience QR/scan widgets and Identity Choice cards rely on `AppColors.textPrimary` or `AppColors.textMuted`, which are white or muted white.
  Evidence: `lib/features/share/presentation/screens/share_target_picker_screen.dart:115-143`, `lib/features/share/presentation/screens/share_target_picker_screen.dart:163-175`, `lib/features/share/presentation/screens/share_target_picker_screen.dart:257-305`, `lib/features/share/presentation/screens/share_target_picker_screen.dart:326-340`, `lib/features/share/presentation/screens/share_target_picker_screen.dart:391-400`, `lib/features/groups/presentation/screens/create_group_picker_screen.dart:86-143`, `lib/features/groups/presentation/widgets/group_name_panel.dart:132-164`, `lib/features/groups/presentation/screens/contact_picker_screen.dart:70-130`, `lib/features/home/presentation/widgets/qr_code_section.dart:33-51`, `lib/features/home/presentation/widgets/scan_friend_card.dart:97-110`, `lib/features/identity/presentation/screens/identity_choice_screen.dart:117-118`, `lib/features/identity/presentation/widgets/choice_card.dart:99-112`, `lib/core/theme/app_colors.dart:14-16`.
- QR Display uses `AmbientBackground` for the normal QR, scan, and empty-circle path, but the visible QR hint, loading shimmer, and empty-circle copy use fixed grey or AppColors-based styling. Its no-identity and error states are separate fallback scaffolds, so they need explicit readability evidence instead of being assumed covered by the normal QR display path.
  Evidence: `lib/features/qr_code/presentation/screens/qr_display_screen.dart:104-140`, `lib/features/qr_code/presentation/screens/qr_display_screen.dart:157-168`, `lib/features/home/presentation/widgets/qr_code_section.dart:83-88`, `lib/features/home/presentation/widgets/qr_code_section.dart:151-155`, `lib/features/home/presentation/widgets/empty_circle_state.dart:70-84`, `lib/features/qr_code/presentation/screens/qr_display_wired.dart:196-223`.
- Startup routing can pass the saved app-shell background preference into Identity Choice. From there, identity generation and restore push separate progress or mnemonic routes, which are outside the current shared-background inventory and need explicit classification rather than implicit coverage through Identity Choice.
  Evidence: `lib/features/identity/presentation/startup_router.dart:418-426`, `lib/features/identity/presentation/screens/identity_choice_wired.dart:60-69`, `lib/features/identity/presentation/screens/identity_choice_wired.dart:153-159`, `lib/features/identity/presentation/screens/mnemonic_input_screen.dart:44-55`, `lib/features/identity/presentation/screens/identity_progress_screen.dart:39-44`.
- Large transient surfaces are also part of the user-visible light-background risk, and several are currently fixed dark surfaces or fixed dark dialogs. Examples include post compose/comments/pass/edit sheets, contact request dialogs, QR scanner success/already-exists/paste dialogs, full emoji picker, message context overlay and delete/attachment sheets, group reaction details sheet, group info dialogs, and full-screen media viewer chrome.
  Evidence: `lib/features/posts/presentation/widgets/compose_post_sheet.dart:424-448`, `lib/features/posts/presentation/widgets/comments_sheet.dart:147-195`, `lib/features/posts/presentation/widgets/pass_post_along_sheet.dart:39-109`, `lib/features/posts/presentation/widgets/edit_pinned_post_sheet.dart:90-121`, `lib/features/contact_request/presentation/widgets/contact_request_dialog.dart:44-115`, `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart:295-430`, `lib/features/conversation/presentation/widgets/full_emoji_picker.dart:52-120`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart:147-160`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart:323-376`, `lib/features/conversation/presentation/screens/conversation_wired.dart:1446-1455`, `lib/features/conversation/presentation/screens/conversation_wired.dart:2216-2244`, `lib/features/groups/presentation/widgets/group_reaction_details_sheet.dart:164-220`, `lib/features/groups/presentation/screens/group_info_wired.dart:206-220`, `lib/features/groups/presentation/screens/group_info_wired.dart:810-815`, `lib/shared/widgets/media/full_screen_image_viewer.dart:59-75`.
- Posts cards, pinned posts, upload progress, and attachment preview surfaces are also part of the named acceptance inventory and currently include fixed dark card surfaces, white foregrounds, or dark overlays.
  Evidence: `lib/features/posts/presentation/screens/posts_screen.dart:97-100`, `lib/features/posts/presentation/screens/posts_screen.dart:261-299`, `lib/features/posts/presentation/widgets/post_card.dart:83-87`, `lib/features/posts/presentation/widgets/post_card.dart:153-170`, `lib/features/posts/presentation/widgets/post_card.dart:204-208`, `lib/features/posts/presentation/widgets/post_card.dart:222-244`, `lib/features/posts/presentation/widgets/pinned_posts_section.dart:39-43`, `lib/features/posts/presentation/widgets/pinned_posts_section.dart:60-72`, `lib/features/posts/presentation/widgets/pinned_posts_section.dart:197-216`, `lib/features/conversation/presentation/widgets/upload_progress_banner.dart:33-68`, `lib/features/conversation/presentation/widgets/attachment_preview_strip.dart:100-126`.

# 5. Scope Clarification

In scope:

- User-visible readability for every selected-background screen and every user-reachable screen, card, modal, sheet, dialog, overlay, or media chrome that can appear while a light background is active.
- Daylight Lagoon as the current production light selected background.
- Primary text, secondary text, muted text, icons, dividers, borders, cards, glass panels, inputs, disabled states, loading placeholders, empty states, unread badges, status badges, filters, navigation, headers, dialogs, sheets, search surfaces, invite cards, message cards, group cards, and swipe/action controls.
- Explicit classification for every screen and major transient surface: selected-background adaptive, intentionally dark/camera/media, or out of selected-background scope because it appears before any background preference exists.
- Measurable readability: normal text and essential labels meet at least `4.5:1` contrast against their effective surface; large text, icons, dividers, borders, disabled controls, focus/selection indicators, and meaningful non-text UI meet at least `3:1`; disabled and muted states remain identifiable without becoming invisible.
- On light surfaces, white or near-white foregrounds, dividers, borders, and muted labels are only acceptable when they sit on a classified dark/camera/media surface with sufficient contrast.
- Orbit as the first concrete failure to catch: the screen must remain readable for header labels, orbit visualization labels, QR/scan controls, filter tabs, friend rows, group rows, intro banners, archived empty states, search controls, unread indicators, and bottom navigation.
- Feed as a regression surface: connection cards, introduction cards, thread cards, message previews, reply controls, loading states, empty states, status indicators, and navigation must stay readable on Daylight Lagoon.
- Group and Conversation surfaces as app-wide coverage surfaces: group lists, pending invites, group conversations, one-to-one conversations, compose areas, upload banners, attachment previews, message overlays, reaction surfaces, read-only states, and empty/loading states must be legible on light backgrounds.
- Introduction, QR scanner, identity restore/progress, and other app surfaces outside the previous shared-background inventory must be explicitly covered or explicitly excluded with a product-facing reason and readability evidence for their own effective surface.
- Current dark backgrounds must remain readable and visually stable.

Non-goals:

- Adding another background option.
- Defining acceptance for future light background options that are not currently present in `BackgroundPreference`.
- Redesigning the app's brand, layout, typography, navigation model, animation model, group model, conversation model, or messaging behavior.
- Replacing the existing readable-color contract for its own sake.
- Changing persistence, transport, notification, identity, backup, post delivery, group membership, or media upload behavior except where visible UI needs to stay readable.
- Requiring a pixel-perfect match to the current dark-background styling.
- Forcing camera/media or pre-preference identity surfaces to adopt Daylight Lagoon when they are explicitly classified as intentionally dark or out of selected-background scope; they still need readable controls, copy, and state indicators on their own effective surface.

Accepted ambiguities to leave open for the later implementation pass:

- The exact final color values and opacity choices, as long as observable light-background readability and existing dark-background preservation pass.
- The exact mix of widget, visual/screenshot, integration, smoke, or simulator evidence for each surface. Static inventory can identify rows and gaps, but it cannot be the only proof for an in-scope readable surface.
- The exact order in which surfaces are completed, as long as the final user-visible result covers the full screen, modal, card, and overlay inventory named here.
- Which decorative accents may stay background-independent because they remain readable on both dark and light backgrounds.

Coverage inventory required for acceptance:

| Screen file | Current inventory status | Required classification |
| --- | --- | --- |
| `lib/features/feed/presentation/screens/feed_screen.dart` | In shared-background inventory | Selected-background surface; content, cards, loading/empty states, composer, overlays, and navigation need light/dark readability evidence. |
| `lib/features/conversation/presentation/screens/conversation_screen.dart` | In shared-background inventory | Selected-background surface; header, messages, composer, upload/attachment/reaction/context surfaces, and empty/loading states need evidence. |
| `lib/features/posts/presentation/screens/posts_screen.dart` | In shared-background inventory | Selected-background surface; feed cards, compose/comments/pass/edit sheets, empty/loading states, and actions need evidence. |
| `lib/features/settings/presentation/screens/settings_screen.dart` | In shared-background inventory | Selected-background surface; every settings card and picker state needs evidence, not only header chrome. |
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | In shared-background inventory | Selected-background surface and observed failure; visible content path needs evidence beyond loading placeholders. |
| `lib/features/share/presentation/screens/share_target_picker_screen.dart` | In shared-background inventory | Selected-background surface; picker rows, send/skip controls, loading/empty states, and errors need evidence. |
| `lib/features/qr_code/presentation/screens/qr_display_screen.dart` | In shared-background inventory | Selected-background surface; QR display card, close/scan controls, loading shimmer, empty-circle copy, no-identity/error states, and any debug-only copy affordance need evidence. |
| `lib/features/home/presentation/screens/first_time_experience_screen.dart` | In shared-background inventory | Selected-background or onboarding surface; scan/add friend cards and dialogs need explicit classification and evidence. |
| `lib/features/identity/presentation/screens/identity_choice_screen.dart` | In shared-background inventory | Pre-preference/onboarding surface with ambient background; choice cards and actions need readable evidence. |
| `lib/features/groups/presentation/screens/create_group_picker_screen.dart` | In shared-background inventory | Selected-background surface; picker rows, loading/empty states, and create controls need evidence. |
| `lib/features/groups/presentation/screens/contact_picker_screen.dart` | In shared-background inventory | Selected-background surface; contact rows, invite controls, loading/empty states, and disabled states need evidence. |
| `lib/features/groups/presentation/screens/group_list_screen.dart` | In shared-background inventory | Selected-background surface; group cards, invite cards, loading/empty states, and section labels need evidence. |
| `lib/features/groups/presentation/screens/group_conversation_screen.dart` | In shared-background inventory | Selected-background surface; header, messages, read-only/dissolved states, composer, banners, and overlays need evidence. |
| `lib/features/groups/presentation/screens/group_info_screen.dart` | In shared-background inventory | Selected-background surface; member rows, admin actions, metadata edit, and confirmation dialogs need evidence. |
| `lib/features/introduction/presentation/screens/friend_picker_screen.dart` | Missing from shared-background inventory | Reachable introduction picker surface; classify as selected-background adaptive or intentionally dark sheet, then provide readable evidence. |
| `lib/features/introduction/presentation/screens/sent_confirmation_screen.dart` | Missing from shared-background inventory | Reachable introduction confirmation surface; classify as selected-background adaptive or intentionally dark confirmation, then provide readable evidence. |
| `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart` | Missing from shared-background inventory | Camera scanner surface; intentional dark/camera classification is acceptable only with scanner chrome and dialogs readable. |
| `lib/features/identity/presentation/screens/mnemonic_input_screen.dart` | Missing from shared-background inventory | Pre-preference restore surface unless shown after a saved preference; needs explicit out-of-scope/default-readable evidence or selected-background evidence if preference can apply. |
| `lib/features/identity/presentation/screens/identity_progress_screen.dart` | Missing from shared-background inventory | Pre-preference progress surface unless shown after a saved preference; needs explicit out-of-scope/default-readable evidence or selected-background evidence if preference can apply. |

Major transient and card inventory required for acceptance:

| Surface group | Examples | Required evidence |
| --- | --- | --- |
| Feed and conversation cards | `FeedCard`, `ConnectionCard`, `IntroductionConnectionCard`, `LetterCard`, message previews, quote/reply bars | Actual content, long text, media, reactions, failed/deleted states, empty/loading states where applicable. |
| Orbit and group rows/cards | `FriendRow`, `GroupRow`, `GroupCard`, `PendingGroupInviteCard`, archived/no-results states, swipe actions | Visible row/card foregrounds, timestamps, badges, disabled/expired states, and action controls. |
| Post sheets and cards | `PostCard`, `ComposePostSheet`, `CommentsSheet`, `PassPostAlongSheet`, `EditPinnedPostSheet` | Actual content, inputs, handles, buttons, selected rows, empty/disabled/submitting states, and localized/mixed-direction text. |
| Request, QR, and confirmation dialogs | `ContactRequestDialog`, QR paste/success/already-exists dialogs, Orbit confirmation dialog, group info confirmation dialogs | Dialog background, title/body copy, buttons, disabled/progress states, and focus indicators over the active background. |
| Message and reaction overlays | `MessageContextOverlay`, delete message sheets, full emoji picker, `GroupReactionDetailsSheet`, reaction bars | Backdrop/scrim, selected message, menu items, emoji/category labels, delete/destructive actions, and participant rows. |
| Media and attachment surfaces | Attachment source sheets, upload/progress banners, attachment previews, `FullScreenImageViewer`, media error overlays | Intentional dark/media classification where appropriate, plus readable chrome, controls, captions, counts, and error states. |

# 6. Test Cases

## Happy Path

- With Daylight Lagoon selected, Orbit renders its top labels, `Friends` header, `My QR` and `Scan` actions, `All`/`Intros`/`Archived` filters, friend rows, group rows, unread badges, intro banner, search dock, and bottom navigation with the contrast thresholds named in this spec on a representative phone viewport.
  Existing gap: current Orbit light-background tests cover loading placeholders, not the reported visible content path.
- With Daylight Lagoon selected, Feed renders loading, empty, connection, introduction, thread, message preview, reply, and navigation surfaces with readable foregrounds and visible cards.
  Existing partial coverage: current Feed tests cover Daylight loading, connection cards, and thread headers.
- With Daylight Lagoon selected, Settings renders profile, background picker, media quality, nearby sharing, peer ID, recovery phrase, and navigation cards with readable copy, controls, selected states, disabled states, and error states.
  Existing partial coverage: current Settings tests cover header and selected Daylight picker chrome.
- With Daylight Lagoon selected, one-to-one Conversation renders header, empty/loading state, message cards, composer, upload banner, attachment preview, reaction/context overlays, and quote/reply states with readable copy and controls.
  Existing partial coverage: current Conversation tests cover Daylight header text.
- With Daylight Lagoon selected, Group List and Group Conversation render headers, group cards, pending invite cards, loading rows, empty states, read-only/dissolved states, backlog banners, compose controls, and message cards with readable copy and controls.
- With Daylight Lagoon selected, the remaining shared-background surfaces from the inventory render their primary cards and controls legibly: Posts, Share Target Picker, QR Display, First Time Experience, Identity Choice, Create Group Picker, Contact Picker, and Group Info.
- With Daylight Lagoon selected, introduction picker and sent-confirmation surfaces are either readable as selected-background surfaces or are explicitly shown as intentionally dark surfaces with readable copy, controls, progress, selected rows, and disabled states.
- QR scanner camera chrome, scan overlay, paste dialog, success dialog, and already-exists dialog remain readable when launched from light-background journeys, whether classified as intentional dark/camera UI or selected-background UI.
- Pre-preference identity restore and identity progress screens have explicit default-readable evidence, and any state that can appear after a saved light preference has selected-background readability evidence.
- Major modal and overlay surfaces named in the transient inventory render actual content, empty/disabled/loading states, and primary actions with the contrast thresholds named in this spec.
- Switching between Feed and Orbit preserves readable foregrounds and cards on both screens without stale dark-background-only styling.
- Switching from Daylight Lagoon back to `Default`, `Cosmic`, or `Mirrored cosmic` preserves the existing dark-background readable appearance.

## Edge Cases

- Empty states remain readable on light backgrounds for Orbit archived/no-results, Feed empty/loading, Conversation empty/loading, Group List empty/loading, and Group Conversation empty/loading.
- Long usernames, group names, latest-message previews, localized labels, Arabic/mixed-direction text, and large unread counts remain readable and do not visually collide with badges or controls on light backgrounds.
- Disabled, blocked, expired, read-only, processing, failed-upload, failed-send, and unavailable-quote states stay distinguishable without relying on pale-on-white text.
- Search surfaces remain readable while the keyboard is open and while search has no results.
- Swipe actions and context overlays remain readable when opened over light-background cards.
- Badges, tabs, selected indicators, and notification counts remain visible on light backgrounds and still communicate state beyond color alone where the UI already does so.
- Reduced-motion or static background modes keep the same readable foreground expectation.
- A missing or unknown stored background preference still falls back to the current default dark-readable experience and does not leave mixed foreground/background styling.

## Regressions To Preserve

- Bug regression: on Daylight Lagoon, no primary screen label, card title, row username, row preview, timestamp, tab label, action label, empty-state message, loading label, divider, disabled control, muted label, or overlay control may render as white or near-white on a white/light surface such that it matches the reported Orbit invisibility failure.
- Bug regression: every in-scope surface classified as selected-background adaptive meets at least `4.5:1` contrast for normal text and essential labels, and at least `3:1` for large text, icons, borders, dividers, disabled controls, focus/selection indicators, and meaningful non-text UI.
- Preservation/regression: dark backgrounds keep their current readable light foreground appearance unless another visual spec explicitly changes them.
- Preservation/regression: Daylight Lagoon still renders as the selected light background wherever the shared-background inventory expects `AmbientBackground`.
- Preservation/regression: Feed connection cards and thread headers remain readable on Daylight Lagoon.
- Preservation/regression: Settings Daylight selected state, Settings header readability, and Conversation Daylight header readability remain covered.
- Preservation/regression: controls for message sending, group invites, archive/unarchive, QR/scan, search, navigation, notification badges, and media/attachment interactions remain reachable and their visible states remain readable; this spec does not define new transport, delivery, notification, or persistence behavior acceptance.
- Preservation/regression: intentionally dark camera/media/pre-preference surfaces remain readable and retain their product purpose after being classified; they do not accidentally inherit pale-on-light styling from the selected background.
- Preservation/regression: no readability change should introduce layout overflow, clipped button text, hidden badges, or unreachable controls on representative mobile viewports.

Acceptance evidence layers:

- Unit evidence is appropriate for deterministic readable-tone and contrast expectations that are independent of a specific screen.
- Static inventory evidence is required to prove every screen, major modal, and major card/overlay row has a classification, but static inventory alone is not sufficient acceptance for an in-scope readable surface.
- Widget or visual evidence is required for each in-scope screen category with actual content and primary actions; if the surface has empty, loading, disabled, destructive, or error states, at least one representative state from each applicable class needs evidence.
- Widget or visual evidence is required for each major transient/card group named in the inventory, including actual content and at least one empty/loading/disabled/destructive/error state where that state exists.
- Integration or smoke evidence is required for at least the Settings-to-Feed, Feed-to-Orbit, and light-background-to-transient-surface journeys because the observed risk spans selected preference, background rendering, navigation, modals, overlays, and visible content.
- Simulator evidence is required for representative phone viewport readability where safe areas, system chrome, keyboard, camera scanner chrome, bottom navigation, or real route transitions affect what the user sees.

# 7. Session 01 Static Classification Ledger

Session 01 converts the source inventory into a maintenance ledger for the rollout. `Current classification` is not acceptance; selected-background rows still require the widget, visual, integration, smoke, or simulator evidence named in their owning sessions.

| Surface | Current classification | Owning rollout session | Evidence state after Session 01 |
| --- | --- | --- | --- |
| Feed screen | Selected-background adaptive | Session 03 | Partial prior Daylight evidence exists; visible content and remaining states still open. |
| Conversation screen | Selected-background adaptive | Session 04 | Header evidence exists; cards, composer, attachments, and overlays still open. |
| Posts screen and post sheets | Selected-background adaptive | Session 03 | Open; card and sheet evidence required. |
| Settings screen | Selected-background adaptive | Session 03 | Partial prior Daylight picker/header evidence exists; full card/error/disabled states still open. |
| Orbit screen | Selected-background adaptive | Session 02 | Observed failure; visible content path open. |
| Share Target Picker | Selected-background adaptive | Session 06 | Open; picker rows, send/skip controls, loading/empty/error states need evidence. |
| QR Display | Selected-background adaptive | Session 06 | Open; QR card, hints, loading, empty, no-identity, and error states need evidence. |
| First Time Experience | Onboarding selected-background candidate | Session 06 | Open; scan/add cards and dialogs need classification and evidence. |
| Identity Choice | Pre-preference/onboarding ambient surface | Session 06 | Open; choice cards and actions need default-readable or selected-background evidence. |
| Create Group Picker | Selected-background adaptive | Session 06 | Open; picker rows, loading/empty, create controls, and disabled/progress states need evidence. |
| Contact Picker | Selected-background adaptive | Session 06 | Open; contact rows, invite controls, loading/empty, disabled states, and progress states need evidence. |
| Group List | Selected-background adaptive | Session 05 | Open; group cards, invites, loading/empty, and section labels need evidence. |
| Group Conversation | Selected-background adaptive | Session 05 | Open; header, messages, read-only/dissolved states, composer, banners, and overlays need evidence. |
| Group Info | Selected-background adaptive | Session 05 | Open; member rows, admin actions, metadata edit, and confirmation dialogs need evidence. |
| Introduction Friend Picker | Reachable introduction surface; classification pending | Session 06 | Open; selected-background adaptive versus intentionally dark sheet classification required. |
| Introduction Sent Confirmation | Reachable introduction surface; classification pending | Session 06 | Open; selected-background adaptive versus intentionally dark confirmation classification required. |
| QR Scanner | Intentional dark/camera candidate | Session 06 | Open; scanner chrome and dialogs must be readable on camera/dark surface. |
| Mnemonic Input | Pre-preference or saved-preference route; classification pending | Session 06 | Open; route state decides default-readable versus selected-background evidence. |
| Identity Progress | Pre-preference or saved-preference route; classification pending | Session 06 | Open; route state decides default-readable versus selected-background evidence. |
| Feed and conversation cards | Selected-background adaptive card group | Sessions 03 and 04 | Open; actual content, long text, media, reactions, failed/deleted, empty/loading evidence required. |
| Orbit and group rows/cards | Selected-background adaptive row/card group | Sessions 02 and 05 | Open; timestamps, badges, disabled/expired states, and actions need evidence. |
| Post sheets and cards | Selected-background adaptive transient/card group | Session 03 | Open; inputs, handles, buttons, selected rows, disabled/submitting, and mixed-direction text need evidence. |
| Request, QR, and confirmation dialogs | Mixed selected-background and intentionally dark dialog group | Session 07 | Open; dialog backgrounds, title/body copy, buttons, progress/disabled, and focus indicators need evidence. |
| Message and reaction overlays | Selected-background adaptive overlay group | Sessions 04, 05, and 07 | Open; selected message, menu items, emoji/category labels, delete actions, and participant rows need evidence. |
| Media and attachment surfaces | Intentional dark/media or selected-background adaptive group | Sessions 04 and 07 | Open; chrome, controls, captions, counts, progress, previews, and error states need evidence. |

Session 01 also adds the reusable test helper `test/shared/helpers/readability_test_helpers.dart` so later tests can assert normal text at `4.5:1` and meaningful non-text controls at `3:1` using the same alpha-aware contrast calculation.

# 8. Session 02 Orbit Closure Evidence

Orbit's visible Daylight Lagoon failure is closed for the main screen path. The following Orbit surfaces now consume `BackgroundReadableColors` roles instead of fixed white-on-light styling:

- top `Close Friends` label and the `Friends` header
- `My QR` and `Scan` pill buttons
- `All`/`Intros`/`Archived` filter tabs and count badges
- friend rows, group rows, row cards, previews, timestamps, chevrons, and group initials
- intro review banner copy and chevron
- archived empty state and search no-results copy
- bottom search dock background, input, hint, clear button, and close button

Verification:

- `flutter test test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`

Residual ownership:

- Orbit swipe action gradients and Orbit confirmation dialogs remain classified as transient/action surfaces for Session 07 unless a real Daylight readability regression appears earlier.

# 9. Session 03 Feed, Settings, And Posts Evidence

Feed and Settings retain their existing Daylight readable-screen evidence, and Session 03 adds Posts main-screen/card coverage. The following Posts surfaces now consume `BackgroundReadableColors` roles:

- Posts title, subtitle, compose affordance, status copy, time-section labels, caught-up copy, and empty state
- `PostCard` surface, borders, author, timestamp, body text, nearby copy, actions, expiry copy, delivery chips, media skeleton, voice wrapper, and secondary badges
- pinned posts container, title, summary, count, expand chrome, pinned card author/body, overflow count, avatar badge borders, and see-all route chrome

Verification:

- `flutter test test/features/posts/phase1/posts_screen_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test test/features/settings/presentation/screens/settings_screen_test.dart`

Residual ownership:

- Full post compose, comment, pass-along, and edit sheets remain classified as cross-app transient/post sheet surfaces for Session 07.

# 10. Session 04 Conversation Evidence

One-to-one Conversation visible message content is now role-backed for Daylight Lagoon:

- `LetterCard` card surfaces, borders, sender names, message body, deleted placeholders, quote bars, timestamps, edited copy, transport/status icons, failed action buttons, and inline reaction chips
- upload progress banner surface, title, progress copy, progress background, helper copy, and cancel affordance
- attachment preview placeholder/error and processing thumbnail copy/progress states

Verification:

- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart`

Residual ownership:

- Full emoji picker, context overlay menus, delete sheets, attachment source sheets, and full-screen media viewer chrome remain Session 07 transient/media surfaces.

# 11. Session 05 Group Evidence

Group List, Group Info, and Group Conversation persistent surfaces now consume readable roles under Daylight Lagoon:

- Group List header, section labels, empty/loading states, group rows, timestamps, previews, unread badges, pending invite cards, expired invite copy, invite actions, and no-joined-groups copy
- group avatars, group type badges, dissolved badges, group card names/previews/status text, and member role badges
- Group Info header, metadata, description, member count, mute card, member rows, admin/member action controls, add-member affordance, dissolved status card, leave/dissolve actions, and local-delete card
- Group Conversation header, info icon, backlog banner, empty/loading states, highlighted row shell, and read-only/dissolved copy

Verification:

- `flutter test test/features/groups/presentation/group_card_test.dart`
- `flutter test test/features/groups/presentation/group_list_screen_test.dart`
- `flutter test test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`

Residual ownership:

- Group reaction detail sheets, metadata edit dialogs, destructive confirmation dialogs, attachment source sheets, and full media chrome remain Session 07 transient/media surfaces.

# 12. Session 06 Share, QR, Introduction, And Identity Evidence

Selected-background edge surfaces now consume readable roles under Daylight Lagoon:

- Share Target Picker header, preview, caption, search, loading/empty state, section labels, contact/group rows, selection icons, send CTA, and sending overlay
- QR Display close button plus QR description, QR loading shimmer, scan-card text, empty-circle copy, and shared glass card surface
- Contact Picker and Create Group Picker headers, search fields, empty states, contact rows, confirm/start buttons, and `GroupNamePanel`
- Identity Choice brand text, choice card titles/descriptions, arrows, shared glass surfaces, and privacy footer

Classification evidence:

- Introduction Friend Picker and Sent Confirmation remain intentionally dark intro surfaces for this session and retain focused test coverage.
- Mnemonic Input remains a platform/default pre-preference restore route and retains focused test coverage.
- Identity Progress remains an intentionally dark blocking progress route and retains focused test coverage.
- QR scanner overlay remains camera/dark chrome and retains focused widget coverage; full scanner camera visuals remain final simulator evidence.

Verification:

- `flutter test test/features/share/presentation/share_target_picker_screen_test.dart`
- `flutter test test/features/qr_code/presentation/screens/qr_display_wired_test.dart`
- `flutter test test/features/groups/presentation/contact_picker_screen_test.dart`
- `flutter test test/features/groups/presentation/create_group_picker_screen_test.dart`
- `flutter test test/features/identity/presentation/screens/identity_choice_screen_test.dart`
- `flutter test test/features/introduction/presentation/screens/friend_picker_test.dart`
- `flutter test test/features/introduction/presentation/screens/sent_confirmation_test.dart`
- `flutter test test/features/identity/presentation/screens/mnemonic_input_screen_test.dart`
- `flutter test test/features/identity/presentation/screens/identity_progress_screen_test.dart`
- `flutter test test/features/qr_code/presentation/widgets/scan_overlay_test.dart`

Residual ownership:

- QR scanner camera chrome, introduction bottom-sheet/dialog internals beyond current focused tests, and remaining cross-app dialogs/sheets/media chrome remain Session 07 or final simulator evidence.

# 13. Session 07 Cross-App Transients And Media Evidence

Cross-app transient surfaces now have focused readable-role coverage or explicit dark-surface classification:

- Contact Request dialog background, border, username, body copy, disabled states, decline action, and accept foreground now consume readable roles for selected light backgrounds.
- One-to-one and group attachment source sheets now use readable sheet backgrounds, dividers, icons, and row text instead of fixed white-on-dark assumptions.
- Conversation context overlay, menu rows, destructive action, reaction bar, and full emoji picker now consume readable roles for glass surfaces, dividers, muted category labels, and selected states.
- Group reaction detail sheets now use readable handle, title/count, divider, and participant row text.
- Group metadata editor dialog now uses readable background, labels, input fill/border, input text, and placeholders.
- Orbit confirmation dialog remains intentionally dark, but its destructive gradient was darkened so the white danger label meets contrast on both gradient endpoints.
- QR scanner remains intentionally dark/camera chrome; paste and success dialog primary actions now use black text on the green accent.
- Full-screen media viewer remains intentionally dark media chrome and retains focused widget coverage.

Verification:

- `flutter test test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart test/features/conversation/presentation/widgets/message_context_overlay_test.dart test/features/conversation/presentation/widgets/full_emoji_picker_test.dart test/features/groups/presentation/widgets/group_reaction_details_sheet_test.dart test/shared/widgets/media/full_screen_image_viewer_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/conversation/presentation/screens/conversation_wired_gif_test.dart test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test test/features/orbit/presentation/widgets/confirmation_dialog_test.dart test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart test/features/qr_code/presentation/widgets/scan_overlay_test.dart`

Residual ownership:

- Simulator-only camera framing, system chrome, keyboard/search placement, and route-transition visual proof remain final Session 08 acceptance evidence.

# 14. Session 08 Final Acceptance And Residual Evidence

Final acceptance verdict: `accepted_with_explicit_follow_up`.

The app-wide Daylight Lagoon readability rollout is accepted for local direct evidence. Primary selected-background surfaces, persistent row/card families, dialogs, sheets, pickers, overlays, and intentionally dark camera/media surfaces named in this doc now have direct role-backed coverage, focused dark-surface contrast checks, or explicit classification.

Final verification:

- `flutter test test/core/theme/background_readable_colors_test.dart test/features/orbit/presentation/screens/orbit_screen_loading_test.dart test/features/orbit/presentation/widgets/confirmation_dialog_test.dart test/features/posts/phase1/posts_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/features/settings/presentation/screens/settings_screen_test.dart test/features/conversation/presentation/widgets/letter_card_test.dart test/features/conversation/presentation/widgets/attachment_preview_strip_test.dart test/features/conversation/presentation/widgets/message_context_overlay_test.dart test/features/conversation/presentation/widgets/full_emoji_picker_test.dart test/features/conversation/presentation/screens/conversation_screen_test.dart test/shared/widgets/media/full_screen_image_viewer_test.dart test/features/groups/presentation/group_card_test.dart test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_info_screen_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/widgets/group_reaction_details_sheet_test.dart test/features/share/presentation/share_target_picker_screen_test.dart test/features/qr_code/presentation/screens/qr_display_wired_test.dart test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart test/features/qr_code/presentation/widgets/scan_overlay_test.dart test/features/groups/presentation/contact_picker_screen_test.dart test/features/groups/presentation/create_group_picker_screen_test.dart test/features/identity/presentation/screens/identity_choice_screen_test.dart test/features/introduction/presentation/screens/friend_picker_test.dart test/features/introduction/presentation/screens/sent_confirmation_test.dart test/features/identity/presentation/screens/mnemonic_input_screen_test.dart test/features/identity/presentation/screens/identity_progress_screen_test.dart test/features/contact_request/presentation/widgets/contact_request_dialog_test.dart`
- `flutter test -d macos integration_test/settings_background_choice_smoke_test.dart`

Notes:

- The unqualified integration smoke command requires `-d` in this local environment because multiple devices/simulators are connected.
- `Test-Flight-Improv/02-integration-test-coverage.md` was not updated because this rollout added focused widget/readability coverage and reused the existing background integration smoke rather than adding a new durable integration category.
- Remaining follow-up is visual/device evidence only: camera scanner framing and permission overlays, phone system status/navigation chrome, route-transition screenshots, keyboard/search placement, and platform-specific media controls.
