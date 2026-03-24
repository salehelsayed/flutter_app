import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import '../../../shared/fakes/fake_notification_service.dart';

MediaAttachment _attachment(String mediaType) => MediaAttachment(
  id: 'attach-1',
  messageId: 'msg-1',
  mime: switch (mediaType) {
    'image' => 'image/jpeg',
    'video' => 'video/mp4',
    'audio' => 'audio/aac',
    _ => 'application/octet-stream',
  },
  size: 1024,
  mediaType: mediaType,
  downloadStatus: 'done',
  createdAt: '2026-01-01T00:00:00.000Z',
);

void main() {
  group('notificationBodyForMessage', () {
    // --- text present ---

    test('returns text as-is when non-empty (text-only message)', () {
      expect(notificationBodyForMessage('Hello!', []), 'Hello!');
    });

    test('returns text even when media is also present (caption wins)', () {
      expect(
        notificationBodyForMessage('Check this out', [_attachment('image')]),
        'Check this out',
      );
    });

    test('trims whitespace before checking emptiness', () {
      expect(notificationBodyForMessage('  ', [_attachment('image')]), 'Photo');
    });

    test(
      'preserves Arabic-first mixed content while trimming outer whitespace',
      () {
        const mixed = '\u0645\u0631\u062d\u0628\u0627 Alpha 123';
        expect(notificationBodyForMessage('  $mixed  ', []), mixed);
      },
    );

    test(
      'preserves English-first mixed content while trimming outer whitespace',
      () {
        const mixed = 'Alpha 123 \u0645\u0631\u062d\u0628\u0627';
        expect(notificationBodyForMessage('\n$mixed\t', []), mixed);
      },
    );

    test('preserves bidi control marks inside trimmed mixed content', () {
      const withBidi = '\u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f';
      expect(notificationBodyForMessage(' $withBidi ', []), withBidi);
    });

    // --- image-only ---

    test('returns Photo for image-only message', () {
      expect(notificationBodyForMessage('', [_attachment('image')]), 'Photo');
    });

    // --- video-only ---

    test('returns Video for video-only message', () {
      expect(notificationBodyForMessage('', [_attachment('video')]), 'Video');
    });

    // --- audio-only ---

    test('returns Voice message for audio-only message', () {
      expect(
        notificationBodyForMessage('', [_attachment('audio')]),
        'Voice message',
      );
    });

    // --- file-only ---

    test('returns File for file-only message', () {
      expect(notificationBodyForMessage('', [_attachment('file')]), 'File');
    });

    // --- unknown mediaType ---

    test('returns Media for unknown single attachment type', () {
      expect(notificationBodyForMessage('', [_attachment('sticker')]), 'Media');
    });

    // --- multiple attachments ---

    test('returns Photo for multiple image attachments (all same type)', () {
      expect(
        notificationBodyForMessage('', [
          _attachment('image'),
          _attachment('image'),
        ]),
        'Photo',
      );
    });

    test('returns Media for mixed image and video attachments', () {
      expect(
        notificationBodyForMessage('', [
          _attachment('image'),
          _attachment('video'),
        ]),
        'Media',
      );
    });

    test('returns Media for mixed image and audio attachments', () {
      expect(
        notificationBodyForMessage('', [
          _attachment('image'),
          _attachment('audio'),
        ]),
        'Media',
      );
    });

    // --- no attachments ---

    test('returns Message when text is empty and media list is empty', () {
      expect(notificationBodyForMessage('', []), 'Message');
    });

    // --- group message body composition ---

    test('group image-only message body is "Alice: Photo"', () {
      final body = notificationBodyForMessage('', [_attachment('image')]);
      expect('Alice: $body', 'Alice: Photo');
    });

    test('group audio-only message body is "Alice: Voice message"', () {
      final body = notificationBodyForMessage('', [_attachment('audio')]);
      expect('Alice: $body', 'Alice: Voice message');
    });

    test('group captioned image body is "Alice: Check this out"', () {
      final body = notificationBodyForMessage('Check this out', [
        _attachment('image'),
      ]);
      expect('Alice: $body', 'Alice: Check this out');
    });
  });

  group('maybeShowNotification — media body integration', () {
    // These tests verify that the correct body reaches NotificationService
    // when maybeShowNotification is called with a media-only message.

    test('image-only 1:1 message shows "Photo" as notification body', () async {
      final notificationService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'peer-alice',
        senderUsername: 'Alice',
        messageText: notificationBodyForMessage('', [_attachment('image')]),
      );

      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.first.messageText, 'Photo');
    });

    test(
      'voice-only 1:1 message shows "Voice message" as notification body',
      () async {
        final notificationService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-alice',
          senderUsername: 'Alice',
          messageText: notificationBodyForMessage('', [_attachment('audio')]),
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.messageText, 'Voice message');
      },
    );

    test('video-only 1:1 message shows "Video" as notification body', () async {
      final notificationService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'peer-alice',
        senderUsername: 'Alice',
        messageText: notificationBodyForMessage('', [_attachment('video')]),
      );

      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.first.messageText, 'Video');
    });

    test('captioned image shows caption text not "Photo"', () async {
      final notificationService = FakeNotificationService();
      final tracker = ActiveConversationTracker();

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'peer-alice',
        senderUsername: 'Alice',
        messageText: notificationBodyForMessage('Look at this!', [
          _attachment('image'),
        ]),
      );

      expect(notificationService.shown.first.messageText, 'Look at this!');
    });
  });
}
