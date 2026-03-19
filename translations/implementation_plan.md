# Localization Implementation Plan

## Setup (DONE)
- [x] Add `flutter_localizations` and `intl` to pubspec.yaml
- [x] Create `l10n.yaml` config
- [x] Generate ARB files (`lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb`)
- [x] Run `flutter gen-l10n` to generate Dart code
- [x] Wire `localizationsDelegates` and `supportedLocales` into `MaterialApp` in `main.dart`
- [x] Verify build succeeds

## Usage Pattern

Every file that uses translated strings needs:
```dart
import 'package:flutter_app/l10n/app_localizations.dart';
```

Then replace hardcoded strings:
```dart
// Before:
Text('Posts')
// After:
Text(AppLocalizations.of(context)!.posts_title)
```

For strings with variables:
```dart
// Before:
Text('Block $username?')
// After:
Text(AppLocalizations.of(context)!.orbit_block_title(username))
```

---

## File-by-File Replacement Tracker

### Phase 1: Navigation & Core UI
| File | Keys | Status |
|------|------|--------|
| `lib/features/feed/presentation/widgets/feed_navigation_bar.dart` | nav_feed, nav_remember, nav_posts, nav_orbit | [x] |
| `lib/features/identity/presentation/widgets/startup_loading_gate.dart` | startup_checking, startup_checking_desc, startup_feed, startup_feed_desc, startup_setup, startup_setup_desc, startup_onboarding, startup_onboarding_desc | [x] |
| `lib/features/identity/presentation/startup_router.dart` | btn_retry | [x] |

### Phase 2: Onboarding & Identity
| File | Keys | Status |
|------|------|--------|
| `lib/features/identity/presentation/screens/identity_choice_screen.dart` | onboarding_new_here, onboarding_new_desc, onboarding_load_key, onboarding_load_desc, onboarding_privacy_1, onboarding_privacy_2 | [x] |
| `lib/features/identity/presentation/screens/identity_progress_screen.dart` | progress_securing, progress_securing_desc, progress_creating, progress_creating_desc, progress_keep_open, progress_almost, progress_step_keys, progress_step_save | [x] |
| `lib/features/identity/presentation/screens/mnemonic_input_screen.dart` | mnemonic_title, mnemonic_hint | [x] |
| `lib/features/identity/presentation/screens/mnemonic_input_wired.dart` | mnemonic_error_12, mnemonic_error_invalid, mnemonic_error_generic | [x] |
| `lib/features/identity/presentation/screens/identity_choice_wired.dart` | error_generic | [x] |

### Phase 3: First Time Experience & QR
| File | Keys | Status |
|------|------|--------|
| `lib/features/home/presentation/screens/first_time_experience_wired.dart` | error_add_contact, picker_take_photo, picker_gallery, error_update_photo | [x] |
| `lib/features/home/presentation/widgets/qr_code_section.dart` | qr_show_desc, qr_copy_hint, qr_copied | [x] |
| `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart` | qr_scan_title, qr_scan_instruction, qr_scan_subtitle, qr_debug_paste, qr_paste_title, qr_paste_hint, qr_paste_button, btn_cancel, btn_submit | [x] |
| `lib/features/qr_code/presentation/screens/qr_display_wired.dart` | qr_no_identity, qr_error, qr_my_code, qr_try_again | [x] |

### Phase 4: Posts Screen
| File | Keys | Status |
|------|------|--------|
| `lib/features/posts/presentation/screens/posts_screen.dart` | posts_title, posts_header_subtitle, posts_compose_button, posts_empty_title, posts_empty_desc, posts_empty_button, posts_caught_up, posts_time_now, posts_time_earlier, posts_time_yesterday | [x] |
| `lib/features/posts/presentation/widgets/post_card.dart` | post_badge_friend, post_uploading, post_sending, post_partial, post_upload_failed, post_send_failed | [x] |
| `lib/features/posts/presentation/widgets/compose_post_sheet.dart` | compose_title, compose_hint, compose_audience_all, compose_audience_nearby, compose_audience_pick, compose_radius, compose_radius_500, compose_radius_1k, compose_radius_2k, compose_media, compose_media_adding, compose_voice, compose_voice_stop, compose_voice_attached, compose_attachments, compose_pick_people, compose_posting, compose_post, compose_manage, compose_pinned_1, compose_pinned_n, compose_nearby_off, compose_nearby_ready, compose_nearby_refresh, compose_nearby_allow, compose_nearby_perm_off, compose_nearby_services, compose_nearby_off_desc, compose_nearby_ready_desc, compose_nearby_refresh_desc, compose_nearby_allow_desc, compose_nearby_perm_desc, compose_nearby_services_desc, compose_open_settings, compose_refreshing, compose_refresh_nearby | [x] |
| `lib/features/posts/presentation/widgets/pinned_posts_section.dart` | pinned_title, pinned_count_1, pinned_count_n, pinned_see_all, pinned_dismiss, pinned_message, pinned_edit, pinned_remove | [x] |
| `lib/features/posts/presentation/widgets/edit_pinned_post_sheet.dart` | edit_pinned_hint | [x] |
| `lib/features/posts/presentation/widgets/comments_sheet.dart` | comment_hint | [x] |

### Phase 5: Orbit Screen (Friends)
| File | Keys | Status |
|------|------|--------|
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | orbit_close_friends, orbit_new_group, orbit_new_announce | [x] |
| `lib/features/orbit/presentation/widgets/qr_action_cards.dart` | qr_my_code, orbit_qr_share, orbit_scan, orbit_qr_scan_desc | [x] |
| `lib/features/orbit/presentation/widgets/friends_list_header.dart` | orbit_my_qr, orbit_scan | [x] |
| `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart` | orbit_filter_all, orbit_filter_intros, orbit_filter_archived | [x] |
| `lib/features/orbit/presentation/widgets/orbit_search_dock.dart` | orbit_search | [x] |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | orbit_block_title, orbit_delete_chat, orbit_leave_group | [x] |

### Phase 6: Conversation
| File | Keys | Status |
|------|------|--------|
| `lib/features/conversation/presentation/widgets/compose_area.dart` | conversation_hint | [x] |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | conversation_voice_fail, conversation_block, conversation_delete_chat | [x] |
| `lib/features/conversation/presentation/widgets/collapsed_mode_card_body.dart` | conversation_continue | [x] |
| `lib/features/conversation/presentation/widgets/open_mode_card_body.dart` | conversation_reply | [x] |

### Phase 7: Groups
| File | Keys | Status |
|------|------|--------|
| `lib/features/groups/presentation/screens/create_group_screen.dart` | group_create_title, group_name_hint, group_desc_hint | [x] |
| `lib/features/groups/presentation/widgets/group_compose_area.dart` | group_message_hint | [x] |
| `lib/features/groups/presentation/widgets/group_name_panel.dart` | group_name_optional | [x] |
| `lib/features/groups/presentation/screens/create_group_picker_wired.dart` | group_create_failed | [x] |
| `lib/features/orbit/presentation/screens/contact_picker_wired.dart` | group_invite_failed | [x] |

### Phase 8: Pickers
| File | Keys | Status |
|------|------|--------|
| `lib/features/introduction/presentation/screens/friend_picker_screen.dart` | picker_introduce_to, picker_search, picker_no_friends, picker_no_results, picker_introduce_count, picker_introduce | [x] |
| `lib/features/groups/presentation/screens/contact_picker_screen.dart` | picker_search_contacts | [x] |
| `lib/features/groups/presentation/screens/create_group_picker_screen.dart` | picker_search_contacts | [x] |
| `lib/features/share/presentation/screens/share_target_picker_screen.dart` | picker_search_all | [x] |

### Phase 9: Settings
| File | Keys | Status |
|------|------|--------|
| `lib/features/settings/presentation/screens/settings_screen.dart` | settings_title, settings_video_quality | [x] |
| `lib/features/settings/presentation/widgets/image_quality_toggle.dart` | settings_compressed, settings_original, settings_original_desc, settings_compressed_desc | [x] |
| `lib/features/settings/presentation/screens/settings_wired.dart` | settings_photo_fail | [x] |

### Phase 10: Feed Wired (error messages)
| File | Keys | Status |
|------|------|--------|
| `lib/features/feed/presentation/screens/feed_wired.dart` | error_add_contact, error_send_message, status_processing_video, error_update_username | [x] |

### Phase 11: Notification Listeners (non-UI, lower priority)
| File | Keys | Status |
|------|------|--------|
| `lib/features/orbit/application/introduction_listener.dart` | notif_new_intro, notif_new_connection | [SKIP] (no widget context available in listeners) |
| `lib/features/posts/application/post_listener.dart` | (dynamic notification titles) | [SKIP] (no widget context available in listeners) |

### Phase 12: iOS Info.plist (requires separate localization)
iOS permission strings cannot use Flutter localization. They require `InfoPlist.strings` files per language.

| File | Keys | Status |
|------|------|--------|
| `ios/Runner/en.lproj/InfoPlist.strings` | perm_camera, perm_photos, perm_microphone, perm_location, perm_local_network | [x] |
| `ios/Runner/de.lproj/InfoPlist.strings` | (same keys, German) | [x] |
| `ios/Runner/ar.lproj/InfoPlist.strings` | (same keys, Arabic) | [x] |

---

## Notes
- **RTL (Arabic)**: Flutter handles RTL automatically via `Directionality`. Test all screens with Arabic to verify layout doesn't break.
- **Notification listener strings** (Phase 11): These run outside widget context. May need to pass locale or use a global accessor.
- **iOS permission strings** (Phase 12): These are native iOS strings, not Flutter. Require `InfoPlist.strings` files in language-specific `.lproj` directories.
- **String length**: German strings are typically 30% longer than English. Arabic may be shorter. Test UI overflow.
- **Testing**: After each phase, run the app in simulator with device language set to German and Arabic to verify.
