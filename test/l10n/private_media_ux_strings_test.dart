import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const exactEnglish = <String, String>{
    'private_media_sheet_title_photo': 'How should {name} see this photo?',
    'private_media_sheet_title_video': 'How should {name} see this video?',
    'private_media_sheet_title_gif': 'How should {name} see this GIF?',
    'group_private_media_sheet_title': 'How should members see this photo?',
    'private_media_set_expiry': 'Set an expiry',
    'private_media_expiry_choose_detail':
        "Disappears from {name}'s phone after a time you choose.",
    'private_media_delete_after': 'Delete after',
    'private_media_duration_1h': '1 hour',
    'private_media_duration_1d': '1 day',
    'private_media_duration_7d': '7 days',
    'private_media_use_mode_cta': 'Use {mode}',
    'private_media_summary_change': 'Change',
    'private_media_summary_ordinary_detail':
        'Normal photo · can be saved or shared',
    'private_media_summary_protected_detail':
        'Viewable again · no saving or sharing',
    'private_media_summary_view_once_detail': 'One view for {name}',
    'private_media_summary_expiry_detail':
        'No saving or sharing · deleted after {duration}',
    'private_media_disclosure_protected':
        'Only {name} can open it. Saving and sharing are disabled.',
    'private_media_disclosure_view_once':
        "{name} can open it once, then it's gone. Saving and sharing are disabled.",
    'private_media_disclosure_expiry':
        'Only {name} can open it until it expires. Saving and sharing are disabled.',
    'private_media_disclosure_reopen':
        'You can reopen it once here after sending.',
    'private_media_card_title_protected_photo': 'Protected photo',
    'private_media_card_title_protected_video': 'Protected video',
    'private_media_card_title_view_once_photo': 'View-once photo',
    'private_media_card_title_view_once_video': 'View-once video',
    'private_media_card_title_expiry_photo':
        'Photo · disappears after {duration}',
    'private_media_card_title_expiry_video':
        'Video · disappears after {duration}',
    'private_media_open_photo': 'Open photo',
    'private_media_open_video': 'Open video',
    'private_media_view_photo': 'View photo',
    'private_media_view_video': 'View video',
    'private_media_sender_consumed': "You've used your one more look",
    'offline_send_promise': "Will send when you're back online",
    'offline_retry_delayed': 'Delivery delayed — retrying automatically',
    'share_stored_offline_promise':
        "Stored — will send when you're back online.",
    'offline_banner_title': "You're offline",
    'offline_banner_body':
        "Messages and media will send when you're back online.",
    'media_sending_automatically': 'Sending automatically…',
    'media_uploading_percent': 'Uploading photo · {percent}%',
    'media_uploading': 'Uploading photo…',
    'media_view_once_not_viewed': 'Not viewed yet.',
    'media_missing_terminal_title_photo': 'Photo is no longer on this phone',
    'media_missing_terminal_title_video': 'Video is no longer on this phone',
    'media_missing_terminal_body': 'Choose it again to send.',
    'media_remove': 'Remove',
    'private_media_open_failed_title_photo': "Couldn't open this photo",
    'private_media_open_failed_title_video': "Couldn't open this video",
    'private_media_open_failed_view_safe': 'Your one view is still available.',
    'private_media_open_failed_reopen_safe':
        'Your one more look is still available.',
    'private_media_sender_local_missing_body':
        "Your sent media can't be reopened on this phone.",
    'private_media_try_again': 'Try again',
    'group_invite_ask_new': 'Ask for a new invite',
    'group_invite_request_new_draft':
        'Could you send me a new invite to {groupName}?',
    'group_invite_contact_unavailable': 'This contact is no longer available.',
  };

  const placeholderTypes = <String, Map<String, String>>{
    'private_media_sheet_title_photo': {'name': 'String'},
    'private_media_sheet_title_video': {'name': 'String'},
    'private_media_sheet_title_gif': {'name': 'String'},
    'private_media_expiry_choose_detail': {'name': 'String'},
    'private_media_use_mode_cta': {'mode': 'String'},
    'private_media_summary_view_once_detail': {'name': 'String'},
    'private_media_summary_expiry_detail': {'duration': 'String'},
    'private_media_disclosure_protected': {'name': 'String'},
    'private_media_disclosure_view_once': {'name': 'String'},
    'private_media_disclosure_expiry': {'name': 'String'},
    'private_media_card_title_expiry_photo': {'duration': 'String'},
    'private_media_card_title_expiry_video': {'duration': 'String'},
    'media_uploading_percent': {'percent': 'int'},
    'group_invite_request_new_draft': {'groupName': 'String'},
  };

  test('plan 260 English private-media copy is exact', () {
    final english = _loadArb('en');

    for (final entry in exactEnglish.entries) {
      expect(english[entry.key], entry.value, reason: entry.key);
    }
  });

  test('plan 260 keys and typed placeholders exist in every locale', () {
    for (final locale in const ['en', 'ar', 'de']) {
      final bundle = _loadArb(locale);
      for (final key in exactEnglish.keys) {
        expect(bundle[key], isA<String>(), reason: '$locale:$key');
        expect(
          (bundle[key] as String).trim(),
          isNotEmpty,
          reason: '$locale:$key',
        );

        final expected = placeholderTypes[key] ?? const <String, String>{};
        final metadata = bundle['@$key'];
        final actual = <String, String>{};
        if (metadata is Map<String, dynamic>) {
          final placeholders = metadata['placeholders'];
          if (placeholders is Map<String, dynamic>) {
            for (final entry in placeholders.entries) {
              final value = entry.value;
              if (value is Map<String, dynamic>) {
                actual[entry.key] = value['type'] as String? ?? '';
              }
            }
          }
        }
        expect(actual, expected, reason: '$locale:@$key');
      }
    }
  });

  test('plan 270 compact copy and image-video eligibility text are exact', () {
    const compactByLocale = <String, String>{
      'en': "{name} doesn't allow saving or sharing.",
      'ar': '{name} لا يسمح بالحفظ أو المشاركة.',
      'de': '{name} erlaubt kein Speichern oder Teilen.',
    };
    const invalidShapeByLocale = <String, String>{
      'en': 'Private media needs one photo or video with no caption.',
      'ar': 'تتطلب الوسائط الخاصة صورة أو فيديو واحدًا بلا تعليق.',
      'de':
          'Private Medien benötigen ein Foto oder Video ohne Bildunterschrift.',
    };
    const legacyBodyByLocale = <String, String>{
      'en': "You can view it again. {name} doesn't allow saving or sharing.",
      'ar': 'يمكنك مشاهدته مجددًا. {name} لا يسمح بالحفظ أو المشاركة.',
      'de':
          'Du kannst es erneut ansehen. {name} erlaubt kein Speichern oder Teilen.',
    };
    const oldLeadInByLocale = <String, String>{
      'en': 'You can view it again.',
      'ar': 'يمكنك مشاهدته مجددًا.',
      'de': 'Du kannst es erneut ansehen.',
    };

    for (final locale in const ['en', 'ar', 'de']) {
      final bundle = _loadArb(locale);
      final compact = compactByLocale[locale]!;
      expect(
        bundle['private_media_protected_body_received_compact'],
        compact,
        reason: '$locale:compact',
      );
      expect(
        compact,
        isNot(contains(oldLeadInByLocale[locale]!)),
        reason: '$locale:compact-old-lead-in',
      );
      expect(
        bundle['private_media_invalid_shape'],
        invalidShapeByLocale[locale],
        reason: '$locale:image-video-only-shape',
      );
      expect(
        bundle['private_media_protected_body_received'],
        legacyBodyByLocale[locale],
        reason: '$locale:legacy-body-must-not-be-retexted',
      );

      final metadata =
          bundle['@private_media_protected_body_received_compact']
              as Map<String, dynamic>?;
      expect(metadata, isNotNull, reason: '$locale:compact-metadata');
      final placeholders = metadata?['placeholders'] as Map<String, dynamic>?;
      expect(placeholders?.keys, <String>[
        'name',
      ], reason: '$locale:compact-placeholders');
      expect(
        (placeholders?['name'] as Map<String, dynamic>?)?['type'],
        'String',
        reason: '$locale:compact-name-type',
      );
    }
  });

  test('disclosures make no screenshot-blocking claim', () {
    for (final locale in const ['en', 'ar', 'de']) {
      final bundle = _loadArb(locale);
      final disclosures = [
        bundle['private_media_disclosure_protected'],
        bundle['private_media_disclosure_view_once'],
        bundle['private_media_disclosure_expiry'],
      ].join(' ').toLowerCase();

      expect(disclosures, isNot(contains('screenshot')));
      expect(disclosures, isNot(contains('screen capture')));
    }
  });
}

Map<String, dynamic> _loadArb(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
}
