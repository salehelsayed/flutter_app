import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 409: a call that is the newest thing in a conversation owns the Orbit
/// preview line.
///
/// `latestCall` is set upstream ONLY when the call is newer than the latest
/// message, so it takes precedence here unconditionally: by the time it is
/// non-null the ordering question is already settled.
void main() {
  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  ConversationCallTimelineEntry call({
    ConversationCallStatus status = ConversationCallStatus.missed,
    ConversationCallDirection direction = ConversationCallDirection.incoming,
  }) => ConversationCallTimelineEntry(
    callId: 'a2f0a1d6-0000-4000-8000-000000000409',
    contactPeerId: '12D3KooWTestPeerId1234567890',
    direction: direction,
    status: status,
    startedAt: DateTime.utc(2026, 2, 9, 16),
    endedAt: DateTime.utc(2026, 2, 9, 16, 0, 20),
  );

  test('TC-409-10 a missed call is the preview', () {
    expect(
      orbitMediaPreviewLabel(l10n: l10n, call: call()),
      'Missed voice call',
    );
  });

  test('TC-409-11 the preview is direction aware, like the chat row', () {
    expect(
      orbitMediaPreviewLabel(
        l10n: l10n,
        call: call(direction: ConversationCallDirection.outgoing),
      ),
      'No answer',
    );
    expect(
      orbitMediaPreviewLabel(
        l10n: l10n,
        call: call(
          status: ConversationCallStatus.completed,
          direction: ConversationCallDirection.outgoing,
        ),
      ),
      'Voice call',
    );
  });

  test('TC-409-12 a newer call outranks the caption and the media', () {
    expect(
      orbitMediaPreviewLabel(
        l10n: l10n,
        call: call(),
        caption: 'an older message',
        media: const MediaPreviewDescriptor(type: 'image', count: 2),
      ),
      'Missed voice call',
    );
  });

  test('TC-409-13 a newer call outranks the deleted placeholder', () {
    expect(
      orbitMediaPreviewLabel(l10n: l10n, call: call(), isDeleted: true),
      'Missed voice call',
      reason:
          'the deleted message is older than the call, so the row should '
          'describe the call, not the tombstone',
    );
  });

  test('TC-409-14 no call leaves every incumbent rule untouched', () {
    expect(orbitMediaPreviewLabel(l10n: l10n, caption: 'hello'), 'hello');
    expect(
      orbitMediaPreviewLabel(l10n: l10n, isDeleted: true),
      l10n.conversation_message_deleted,
    );
    expect(orbitMediaPreviewLabel(l10n: l10n), '');
  });
}
