import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/features/feed/presentation/widgets/open_mode_card_body.dart';
import 'package:flutter_app/features/feed/presentation/widgets/scrollable_message_preview.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  ThreadFeedItem _thread({List<ThreadMessage>? messages, int unreadCount = 2}) {
    final msgs =
        messages ??
        [
          ThreadMessage(
            id: 'm1',
            text: 'Read msg',
            time: '2:00 PM',
            timestamp: DateTime(2026, 2, 9, 14, 0),
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'm2',
            text: 'Unread 1',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isUnread: true,
            isIncoming: true,
          ),
          ThreadMessage(
            id: 'm3',
            text: 'Unread 2',
            time: '3:05 PM',
            timestamp: DateTime(2026, 2, 9, 15, 5),
            isUnread: true,
            isIncoming: true,
          ),
        ];
    return ThreadFeedItem(
      id: 'thread_1',
      timestamp: DateTime(2026, 2, 9, 15, 5),
      contactPeerId: 'peer1',
      contactUsername: 'Alice',
      messages: msgs,
      unreadCount: unreadCount,
      conversationState: ConversationState.unread,
    );
  }

  group('OpenModeCardBody', () {
    testWidgets('renders ScrollableMessagePreview with unread messages', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      expect(find.byType(ScrollableMessagePreview), findsOneWidget);
      expect(find.textContaining('Unread 1'), findsOneWidget);
      expect(find.textContaining('Unread 2'), findsOneWidget);
    });

    testWidgets('shows ViewEarlierLink when hasEarlierHistory', (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      // Thread has a read message before unread, so hasEarlierHistory = true
      expect(find.text('View earlier messages'), findsOneWidget);
    });

    testWidgets('renders InlineReplyInput with Reply... hint', (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      expect(find.text('Reply...'), findsOneWidget);
    });

    testWidgets(
      'resolves reply quotes from full thread history, not unread slice only',
      (tester) async {
        final thread = _thread(
          unreadCount: 1,
          messages: [
            ThreadMessage(
              id: 'm1',
              text: 'Older read message',
              time: '2:00 PM',
              timestamp: DateTime(2026, 2, 9, 14, 0),
              isIncoming: true,
            ),
            ThreadMessage(
              id: 'm2',
              text: 'This is a reply',
              time: '3:00 PM',
              timestamp: DateTime(2026, 2, 9, 15, 0),
              isUnread: true,
              isIncoming: true,
              quotedMessageId: 'm1',
            ),
          ],
        );

        await tester.pumpWidget(wrap(OpenModeCardBody(thread: thread)));

        expect(find.text('Older read message'), findsOneWidget);
        expect(find.text('Message unavailable'), findsNothing);
      },
    );

    testWidgets(
      'renders quote preview bar when active quote text is provided',
      (tester) async {
        var dismissed = false;
        await tester.pumpWidget(
          wrap(
            OpenModeCardBody(
              thread: _thread(),
              activeQuoteText: 'Quoted message text',
              onClearQuote: () => dismissed = true,
            ),
          ),
        );

        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Quoted message text'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();

        expect(dismissed, isTrue);
      },
    );

    testWidgets('renders friend indicator with name and time', (tester) async {
      await tester.pumpWidget(wrap(OpenModeCardBody(thread: _thread())));
      expect(find.text('Alice'), findsAtLeast(1));
    });

    testWidgets('shows UnreadCountBadge when count > 0', (tester) async {
      await tester.pumpWidget(
        wrap(OpenModeCardBody(thread: _thread(unreadCount: 3))),
      );
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('renders group icon and group name for GroupThreadFeedItem', (
      tester,
    ) async {
      final groupThread = GroupThreadFeedItem(
        id: 'g1',
        timestamp: DateTime(2026, 2, 9, 15, 5),
        groupId: 'group-abc',
        groupName: 'Test Group',
        groupType: GroupType.chat,
        messages: [
          ThreadMessage(
            id: 'gm1',
            text: 'Group message',
            time: '3:00 PM',
            timestamp: DateTime(2026, 2, 9, 15, 0),
            isUnread: true,
            isIncoming: true,
            senderUsername: 'Sarah',
            senderPeerId: 'peer-sarah',
          ),
        ],
        unreadCount: 1,
        conversationState: ConversationState.unread,
      );

      await tester.pumpWidget(wrap(OpenModeCardBody(thread: groupThread)));
      // Group icon should be present
      expect(find.byIcon(Icons.group_rounded), findsOneWidget);
      // Group name should be shown
      expect(find.text('Test Group'), findsOneWidget);
    });

    testWidgets(
      'group message with media passes media to MessageBubble in open mode',
      (tester) async {
        final attachment = MediaAttachment(
          id: 'att-1',
          messageId: 'gm1',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          downloadStatus: 'done',
          localPath: '/tmp/photo.jpg',
          createdAt: '2026-02-09T15:00:00Z',
        );

        final groupThread = GroupThreadFeedItem(
          id: 'g1',
          timestamp: DateTime(2026, 2, 9, 15, 5),
          groupId: 'group-abc',
          groupName: 'Photo Group',
          groupType: GroupType.chat,
          messages: [
            ThreadMessage(
              id: 'gm1',
              text: 'check this',
              time: '3:00 PM',
              timestamp: DateTime(2026, 2, 9, 15, 0),
              isUnread: true,
              isIncoming: true,
              senderUsername: 'Hisam',
              senderPeerId: 'peer-hisam',
              media: [attachment],
            ),
          ],
          unreadCount: 1,
          conversationState: ConversationState.unread,
        );

        await tester.pumpWidget(wrap(OpenModeCardBody(thread: groupThread)));

        // MessageBubble should receive media
        final bubbles = tester.widgetList<MessageBubble>(
          find.byType(MessageBubble),
        );
        expect(bubbles, isNotEmpty);
        expect(bubbles.first.media, isNotEmpty);
        expect(bubbles.first.media.first.id, 'att-1');
      },
    );
  });
}
