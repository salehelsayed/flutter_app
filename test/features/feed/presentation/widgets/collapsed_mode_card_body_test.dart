import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/session_reply.dart';
import 'package:flutter_app/features/feed/presentation/widgets/collapsed_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Minimal valid 1x1 red PNG (67 bytes).
final Uint8List _tinyPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, // 8-bit RGB
  0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
  0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, // compressed data
  0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, // ...
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
  0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('CollapsedModeCardBody', () {
    testWidgets('replied state shows reply indicator', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hey',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'm2',
            text: 'My reply',
            time: '2:05 PM',
            timestamp: DateTime(2026, 2, 9, 14, 5),
            isIncoming: false,
          ),
        ],
        conversationState: ConversationState.replied,
        lastRepliedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));
      expect(find.textContaining('You replied'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('read state shows last received message, no check',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hello there',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));
      expect(find.textContaining('You replied'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('session reply shows reply text with Just now',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hello',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.unread,
      );

      final reply = SessionReply(text: 'My quick reply', time: DateTime.now());

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
      )));

      // Session reply text should be in the preview
      expect(find.text('My quick reply'), findsOneWidget);
      // Check icon should show (replied via session)
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('InlineReplyInput has Continue... hint', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));
      expect(find.text('Continue...'), findsOneWidget);
    });

    testWidgets('fires onTapExpand on tap', (tester) async {
      var tapped = false;
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        onTapExpand: () => tapped = true,
      )));

      // Tap on the name (part of the GestureDetector area)
      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });
    testWidgets('collapsed card shows "Tap to expand" hint', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        isExpanded: false,
      )));
      expect(find.text('Tap to expand'), findsOneWidget);
    });

    testWidgets('expanded card hides "Tap to expand" hint', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        isExpanded: true,
      )));
      expect(find.text('Tap to expand'), findsNothing);
    });

    testWidgets('session reply still shows "Tap to expand" hint', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hello',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.unread,
      );

      final reply = SessionReply(text: 'Quick reply', time: DateTime.now());

      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
        isExpanded: false,
      )));
      expect(find.text('Tap to expand'), findsOneWidget);
    });
  });

  group('CollapsedModeCardBody group support', () {
    testWidgets('renders group icon for GroupThreadFeedItem', (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm1',
            text: 'Group message',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            senderUsername: 'Sarah',
            senderPeerId: 'peer-sarah',
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: groupThread)));
      expect(find.byIcon(Icons.group_rounded), findsOneWidget);
      expect(find.text('Test Group'), findsOneWidget);
    });

    testWidgets('preview label uses per-message senderUsername for group',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm1',
            text: 'Hello from Mike',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            senderUsername: 'Mike',
            senderPeerId: 'peer-mike',
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: groupThread)));
      // Should show "Mike: " as the preview label, not "Test Group: "
      expect(find.text('Mike: '), findsOneWidget);
    });
  });

  group('CollapsedModeCardBody expanded state', () {
    ThreadFeedItem _readThread({int messageCount = 3}) {
      return ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: List.generate(
          messageCount,
          (i) => ThreadMessage(
            id: 'm${i + 1}',
            text: 'Message ${i + 1}',
            time: '3:0$i PM',
            timestamp: DateTime(2026, 2, 9, 15, i),
            isIncoming: true,
          ),
        ),
        conversationState: ConversationState.read,
      );
    }

    testWidgets('isExpanded false does not show ScrollableMessagePreview',
        (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: false,
      )));
      expect(find.byType(ScrollableMessagePreview), findsNothing);
    });

    testWidgets('isExpanded true shows ScrollableMessagePreview',
        (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
      )));
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('header still shows username when expanded', (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
      )));
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('InlineReplyInput still present when expanded',
        (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
      )));
      expect(find.text('Continue...'), findsOneWidget);
    });

    testWidgets('single-line preview hidden when expanded', (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Preview line text',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.read,
      );

      // Not expanded: preview text visible as "Alice: Preview line text"
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        isExpanded: false,
      )));
      // The preview shows "Alice: " label and "Preview line text"
      expect(find.text('Preview line text'), findsOneWidget);

      // Expanded: preview text replaced by ScrollableMessagePreview
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        isExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('tap header fires onTapExpand in expanded state',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
        onTapExpand: () => tapped = true,
      )));

      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });

    testWidgets('Collapse link present in expanded state', (tester) async {
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: _readThread(),
        isExpanded: true,
        onCollapse: () {},
      )));
      expect(find.text('Collapse'), findsOneWidget);
    });

    testWidgets('clearing session reply while expanded shows ScrollableMessagePreview',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.replied,
        lastRepliedAt: DateTime.now(),
      );

      final reply = SessionReply.justNow('My reply');

      // Session reply + expanded → no ScrollableMessagePreview
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
        isExpanded: true,
      )));
      expect(find.byType(ScrollableMessagePreview), findsNothing);

      // Clear session reply while still expanded → ScrollableMessagePreview appears
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: null,
        isExpanded: true,
      )));
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
    });

    testWidgets('session reply with isExpanded does not show ScrollableMessagePreview',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Alice',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'Hi',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
          ),
        ],
        conversationState: ConversationState.unread,
      );

      final reply = SessionReply.justNow('My reply');
      await tester.pumpWidget(wrap(CollapsedModeCardBody(
        thread: thread,
        sessionReply: reply,
        isExpanded: true,
      )));
      // Session reply overrides expanded — shows single-line preview, not ScrollableMessagePreview
      expect(find.byType(ScrollableMessagePreview), findsNothing);
      expect(find.text('My reply'), findsOneWidget);
    });
  });

  group('CollapsedModeCardBody media thumbnail', () {
    late Directory tmpDir;
    late String imagePath;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('thumb_test_');
      imagePath = '${tmpDir.path}/photo.png';
      File(imagePath).writeAsBytesSync(_tinyPng);
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    testWidgets('shows thumbnail when message has downloaded image + text',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Solz',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'again',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            media: [
              MediaAttachment(
                id: 'a1',
                messageId: 'm1',
                mime: 'image/jpeg',
                size: 1000,
                mediaType: 'image',
                localPath: imagePath,
                downloadStatus: 'done',
                createdAt: '2026-02-09T15:00:00Z',
              ),
            ],
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));

      // Thumbnail Image.file should be present
      expect(find.byType(Image), findsOneWidget);
      // Text preview should still show
      expect(find.text('again'), findsOneWidget);
    });

    testWidgets('shows icon fallback when media not yet downloaded',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Solz',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: 'again',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            media: [
              MediaAttachment(
                id: 'a1',
                messageId: 'm1',
                mime: 'image/jpeg',
                size: 1000,
                mediaType: 'image',
                downloadStatus: 'pending',
                createdAt: '2026-02-09T15:00:00Z',
              ),
            ],
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));

      // Icon fallback instead of thumbnail
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
      // No Image widget
      expect(find.byType(Image), findsNothing);
      // Text preview should still show
      expect(find.text('again'), findsOneWidget);
    });

    testWidgets('media-only message shows thumbnail + Photo label',
        (tester) async {
      final thread = ThreadFeedItem(
        id: 'thread_1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        contactPeerId: 'peer1',
        contactUsername: 'Solz',
        messages: [
          ThreadMessage(
            id: 'm1',
            text: '',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            media: [
              MediaAttachment(
                id: 'a1',
                messageId: 'm1',
                mime: 'image/jpeg',
                size: 1000,
                mediaType: 'image',
                localPath: imagePath,
                downloadStatus: 'done',
                createdAt: '2026-02-09T15:00:00Z',
              ),
            ],
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester.pumpWidget(wrap(CollapsedModeCardBody(thread: thread)));

      // Thumbnail should render
      expect(find.byType(Image), findsOneWidget);
      // "Photo" label should show
      expect(find.text('Photo'), findsOneWidget);
    });

    testWidgets(
        'group card shows thumbnail when message has downloaded image',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm1',
            text: 'photo here',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            senderUsername: 'Hisam',
            senderPeerId: 'peer-hisam',
            media: [
              MediaAttachment(
                id: 'a1',
                messageId: 'gm1',
                mime: 'image/jpeg',
                size: 1000,
                mediaType: 'image',
                localPath: imagePath,
                downloadStatus: 'done',
                createdAt: '2026-02-09T15:00:00Z',
              ),
            ],
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester
          .pumpWidget(wrap(CollapsedModeCardBody(thread: groupThread)));

      // Thumbnail Image.file should be present
      expect(find.byType(Image), findsOneWidget);
      // Sender label should show
      expect(find.textContaining('Hisam'), findsOneWidget);
      // Text preview should still show
      expect(find.text('photo here'), findsOneWidget);
    });

    testWidgets(
        'group card shows icon fallback when media not yet downloaded',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm1',
            text: 'image coming',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            senderUsername: 'Hisam',
            senderPeerId: 'peer-hisam',
            media: [
              MediaAttachment(
                id: 'a1',
                messageId: 'gm1',
                mime: 'image/jpeg',
                size: 1000,
                mediaType: 'image',
                downloadStatus: 'pending',
                createdAt: '2026-02-09T15:00:00Z',
              ),
            ],
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester
          .pumpWidget(wrap(CollapsedModeCardBody(thread: groupThread)));

      // Icon fallback instead of thumbnail
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('group card media-only message shows thumbnail + Photo label',
        (tester) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9, 15, 0),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm1',
            text: '',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isIncoming: true,
            senderUsername: 'Hisam',
            senderPeerId: 'peer-hisam',
            media: [
              MediaAttachment(
                id: 'a1',
                messageId: 'gm1',
                mime: 'image/jpeg',
                size: 1000,
                mediaType: 'image',
                localPath: imagePath,
                downloadStatus: 'done',
                createdAt: '2026-02-09T15:00:00Z',
              ),
            ],
          ),
        ],
        conversationState: ConversationState.read,
      );

      await tester
          .pumpWidget(wrap(CollapsedModeCardBody(thread: groupThread)));

      // Thumbnail should render
      expect(find.byType(Image), findsOneWidget);
      // "Photo" label should show
      expect(find.text('Photo'), findsOneWidget);
    });
  });
}
