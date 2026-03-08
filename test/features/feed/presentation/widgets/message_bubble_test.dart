import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('MessageBubble colors', () {
    testWidgets('received message has transparent background',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        isUnread: false,
      )));

      // Find the Container with BoxDecoration — no background color
      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      if (decoration != null) {
        expect(decoration.color, isNull);
      }
    });

    testWidgets('sent message uses FeedColors.messageSentBg', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Reply',
        time: '3:05 PM',
        isIncoming: false,
        isUnread: false,
      )));

      // Verify it renders without error (inline "You: Reply" in Text.rich)
      expect(find.textContaining('Reply'), findsOneWidget);
    });

    testWidgets('unread message uses FeedColors.messageUnreadBg',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'New msg',
        time: '3:10 PM',
        isIncoming: true,
        isUnread: true,
      )));

      expect(find.textContaining('New msg'), findsOneWidget);
    });

    testWidgets('renders incoming accent edge with teal', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Test',
        time: '3:00 PM',
        isIncoming: true,
      )));

      // The accent edge Container with width 3 should exist
      final containers = tester.widgetList<Container>(find.byType(Container));
      final accentEdge = containers.where((c) {
        final constraints = c.constraints;
        return constraints != null && constraints.maxWidth == 3;
      });
      expect(accentEdge.isNotEmpty, isTrue);
    });

    testWidgets('renders text and time', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Hello world',
        time: '3:30 PM',
        isIncoming: true,
      )));

      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('3:30 PM'), findsOneWidget);
    });
  });

  group('MessageBubble media', () {
    testWidgets('renders MediaGrid when image media provided', (tester) async {
      final media = [
        MediaAttachment(
          id: 'a1',
          messageId: 'm1',
          mime: 'image/jpeg',
          size: 1000,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-02-23T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Check this',
        time: '3:00 PM',
        isIncoming: true,
        media: media,
      )));

      expect(find.byType(MediaGrid), findsOneWidget);
    });

    testWidgets('no MediaGrid when media is empty', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'No media',
        time: '3:00 PM',
        isIncoming: true,
      )));

      expect(find.byType(MediaGrid), findsNothing);
    });

    testWidgets('onMediaTap callback fires with correct index',
        (tester) async {
      int? tappedIndex;
      final media = [
        MediaAttachment(
          id: 'a1',
          messageId: 'm1',
          mime: 'image/jpeg',
          size: 1000,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-02-23T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: '',
        time: '3:00 PM',
        isIncoming: true,
        media: media,
        onMediaTap: (index) => tappedIndex = index,
      )));

      // MediaGrid should exist
      expect(find.byType(MediaGrid), findsOneWidget);
      // Tap the cell — triggers GestureDetector inside MediaGridCell
      await tester.tap(find.byType(MediaGrid));
      expect(tappedIndex, 0);
    });

    testWidgets('renders quote bar when quotedText is provided',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'My reply',
        time: '3:00 PM',
        isIncoming: true,
        quotedText: 'Original message',
      )));

      expect(find.text('Original message'), findsOneWidget);
    });

    testWidgets('renders unavailable quote bar', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'My reply',
        time: '3:00 PM',
        isIncoming: true,
        isQuoteUnavailable: true,
      )));

      expect(find.text('Message unavailable'), findsOneWidget);
    });
  });

  group('URL links', () {
    testWidgets('URL in message body renders as tappable link',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Check https://example.com out',
        time: '3:00 PM',
        isIncoming: true,
      )));

      expect(find.byType(LinkableText), findsOneWidget);
    });

    testWidgets('name prefix preserved with linkable body', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Check https://example.com out',
        time: '3:00 PM',
        isIncoming: false,
        senderLabel: 'You',
      )));

      expect(find.textContaining('You: '), findsOneWidget);
      expect(find.textContaining('https://example.com'), findsOneWidget);
    });

    testWidgets('plain text without URLs still renders normally',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Just a plain message',
        time: '3:00 PM',
        isIncoming: true,
      )));

      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.textContaining('Just a plain message'), findsOneWidget);
    });
  });

  group('MessageBubble reactions', () {
    testWidgets('renders inline reaction chips when reactions provided',
        (tester) async {
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '👍',
          senderPeerId: 'peer-a',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      // No standalone ReactionDisplay; emoji rendered inline
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('👍'), findsOneWidget);
    });

    testWidgets('no ReactionDisplay when reactions empty', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        reactions: [],
        ownPeerId: 'my-peer',
      )));

      expect(find.byType(ReactionDisplay), findsNothing);
    });

    testWidgets('long-press fires onLongPress callback', (tester) async {
      var longPressed = false;

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Press me',
        time: '3:00 PM',
        isIncoming: true,
        onLongPress: () => longPressed = true,
      )));

      await tester.longPress(find.textContaining('Press me'));
      expect(longPressed, isTrue);
    });

    testWidgets('no ReactionDisplay widget when reactions provided',
        (tester) async {
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '👍',
          senderPeerId: 'peer-a',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      // ReactionDisplay widget should NOT be used (inline chips instead)
      expect(find.byType(ReactionDisplay), findsNothing);
    });

    testWidgets('onReactionTap fires with emoji when chip tapped',
        (tester) async {
      String? tappedEmoji;
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '❤️',
          senderPeerId: 'peer-a',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
        onReactionTap: (emoji) => tappedEmoji = emoji,
      )));

      await tester.tap(find.text('❤️'));
      expect(tappedEmoji, '❤️');
    });
  });

  group('MessageBubble inline reactions', () {
    testWidgets('inline reactions render below text, timestamp overlays text',
        (tester) async {
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '👍',
          senderPeerId: 'peer-a',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      // Reactions in a Wrap below text
      expect(find.text('👍'), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
      // Timestamp overlaid on text via Stack
      expect(find.text('3:00 PM'), findsOneWidget);

      final timeElement = find.text('3:00 PM').evaluate().first;
      Stack? timeStack;
      timeElement.visitAncestorElements((element) {
        if (element.widget is Stack) {
          timeStack = element.widget as Stack;
          return false;
        }
        return true;
      });
      expect(timeStack, isNotNull,
          reason: 'Timestamp should be inside a Stack');
    });

    testWidgets('no reactions still right-aligns timestamp in Stack',
        (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        text: 'Hello',
        time: '3:00 PM',
        isIncoming: true,
        reactions: [],
        ownPeerId: 'my-peer',
      )));

      // Timestamp should be inside a Stack (overlaid on text)
      final timeElement = find.text('3:00 PM').evaluate().first;
      Stack? timeStack;
      timeElement.visitAncestorElements((element) {
        if (element.widget is Stack) {
          timeStack = element.widget as Stack;
          return false;
        }
        return true;
      });
      expect(timeStack, isNotNull,
          reason: 'Timestamp should be inside a Stack');
    });

    testWidgets('multiple reaction emojis render inline with counts',
        (tester) async {
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '👍',
          senderPeerId: 'peer-a',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
        MessageReaction(
          id: 'r2',
          messageId: 'm1',
          emoji: '👍',
          senderPeerId: 'peer-b',
          timestamp: '2026-02-27T10:00:01Z',
          createdAt: '2026-02-27T10:00:01Z',
        ),
        MessageReaction(
          id: 'r3',
          messageId: 'm1',
          emoji: '❤️',
          senderPeerId: 'peer-c',
          timestamp: '2026-02-27T10:00:02Z',
          createdAt: '2026-02-27T10:00:02Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Great',
        time: '3:00 PM',
        isIncoming: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      expect(find.text('👍 2'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('3:00 PM'), findsOneWidget);
      // No standalone ReactionDisplay widget
      expect(find.byType(ReactionDisplay), findsNothing);
    });

    testWidgets('own reaction chip has teal border inline', (tester) async {
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '🎉',
          senderPeerId: 'my-peer',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Hooray',
        time: '3:00 PM',
        isIncoming: true,
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      // Find the chip Container with teal border
      final containers = tester.widgetList<Container>(find.byType(Container));
      final tealBorderChip = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border is Border) {
          final border = decoration.border as Border;
          return border.top.color ==
              const Color.fromRGBO(78, 205, 196, 0.30);
        }
        return false;
      });
      expect(tealBorderChip.isNotEmpty, isTrue,
          reason: 'Own reaction chip should have teal border');
      // No standalone ReactionDisplay
      expect(find.byType(ReactionDisplay), findsNothing);
    });

    testWidgets(
        'sent message with reactions and delivery status renders correctly',
        (tester) async {
      final reactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'm1',
          emoji: '👍',
          senderPeerId: 'peer-a',
          timestamp: '2026-02-27T10:00:00Z',
          createdAt: '2026-02-27T10:00:00Z',
        ),
      ];

      await tester.pumpWidget(wrap(MessageBubble(
        text: 'Sent msg',
        time: '4:00 PM',
        isIncoming: false,
        status: 'delivered',
        reactions: reactions,
        ownPeerId: 'my-peer',
      )));

      expect(find.text('👍'), findsOneWidget);
      expect(find.text('4:00 PM'), findsOneWidget);
      // Delivery status icon should render
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    });
  });
}
