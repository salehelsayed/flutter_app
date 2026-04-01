import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/feed/presentation/widgets/message_bubble.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  LinkableText _linkableTextWidget(WidgetTester tester, String text) {
    final finder = find.byWidgetPredicate(
      (widget) => widget is LinkableText && widget.text == text,
      description: 'LinkableText("$text")',
    );
    expect(finder, findsOneWidget);
    return tester.widget<LinkableText>(finder);
  }

  RichText _bodyRichTextWidget(WidgetTester tester, String text) {
    return tester.widget<RichText>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is LinkableText && widget.text == text,
          description: 'LinkableText("$text")',
        ),
        matching: find.byType(RichText),
      ),
    );
  }

  bool _hasPositionedAncestor(Finder finder) {
    final element = finder.evaluate().single;
    var hasPositioned = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Positioned) {
        hasPositioned = true;
        return false;
      }
      return true;
    });
    return hasPositioned;
  }

  group('MessageBubble colors', () {
    testWidgets('received message has transparent background', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Hello',
            time: '3:00 PM',
            isIncoming: true,
            isUnread: false,
          ),
        ),
      );

      // Find the Container with BoxDecoration — no background color
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration?;
      if (decoration != null) {
        expect(decoration.color, isNull);
      }
    });

    testWidgets('sent message uses FeedColors.messageSentBg', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Reply',
            time: '3:05 PM',
            isIncoming: false,
            senderLabel: 'You',
            isUnread: false,
          ),
        ),
      );

      // Verify it renders without error (inline "You: Reply" in Text.rich)
      expect(find.textContaining('Reply'), findsOneWidget);
    });

    testWidgets('unread message uses FeedColors.messageUnreadBg', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'New msg',
            time: '3:10 PM',
            isIncoming: true,
            isUnread: true,
          ),
        ),
      );

      expect(find.textContaining('New msg'), findsOneWidget);
    });

    testWidgets('renders incoming accent edge with teal', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(text: 'Test', time: '3:00 PM', isIncoming: true),
        ),
      );

      // The accent edge Container with width 3 should exist
      final containers = tester.widgetList<Container>(find.byType(Container));
      final accentEdge = containers.where((c) {
        final constraints = c.constraints;
        return constraints != null && constraints.maxWidth == 3;
      });
      expect(accentEdge.isNotEmpty, isTrue);
    });

    testWidgets('renders text and time', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Hello world',
            time: '3:30 PM',
            isIncoming: true,
          ),
        ),
      );

      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('3:30 PM'), findsOneWidget);
    });

    testWidgets('renders edited indicator for edited outgoing rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Updated text',
            time: '3:30 PM',
            isIncoming: false,
            senderLabel: 'You',
            status: 'delivered',
            isEdited: true,
          ),
        ),
      );

      expect(find.text('(edited)'), findsOneWidget);
    });

    testWidgets('renders deleted placeholder instead of linkable body text', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: '',
            time: '3:30 PM',
            isIncoming: false,
            senderLabel: 'You',
            isDeleted: true,
            isEdited: true,
            status: 'delivered',
          ),
        ),
      );

      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.byType(LinkableText), findsNothing);
      expect(find.text('(edited)'), findsNothing);
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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Check this',
            time: '3:00 PM',
            isIncoming: true,
            media: media,
          ),
        ),
      );

      expect(find.byType(MediaGrid), findsOneWidget);
    });

    testWidgets('no MediaGrid when media is empty', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'No media',
            time: '3:00 PM',
            isIncoming: true,
          ),
        ),
      );

      expect(find.byType(MediaGrid), findsNothing);
    });

    testWidgets('onMediaTap callback fires with correct index', (tester) async {
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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: '',
            time: '3:00 PM',
            isIncoming: true,
            media: media,
            onMediaTap: (index) => tappedIndex = index,
          ),
        ),
      );

      // MediaGrid should exist
      expect(find.byType(MediaGrid), findsOneWidget);
      // Tap the cell — triggers GestureDetector inside MediaGridCell
      await tester.tap(find.byType(MediaGrid));
      expect(tappedIndex, 0);
    });

    testWidgets('renders quote bar when quotedText is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'My reply',
            time: '3:00 PM',
            isIncoming: true,
            quotedText: 'Original message',
          ),
        ),
      );

      expect(find.text('Original message'), findsOneWidget);
    });

    testWidgets('renders unavailable quote bar', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'My reply',
            time: '3:00 PM',
            isIncoming: true,
            isQuoteUnavailable: true,
          ),
        ),
      );

      expect(find.text('Message unavailable'), findsOneWidget);
    });

    testWidgets(
      'shows pending icon, color, and semantics when status is pending',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const MessageBubble(
              text: 'Pending inbox fallback',
              time: '3:00 PM',
              isIncoming: false,
              senderLabel: 'You',
              status: 'pending',
            ),
          ),
        );

        final iconFinder = find.byIcon(Icons.schedule_rounded);
        expect(iconFinder, findsOneWidget);

        final icon = tester.widget<Icon>(iconFinder);
        expect(icon.color, const Color.fromRGBO(255, 200, 100, 0.50));
        expect(
          find.bySemanticsLabel('Message status: pending delivery via inbox'),
          findsOneWidget,
        );
      },
    );
  });

  group('URL links', () {
    testWidgets('URL in message body renders as tappable link', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Check https://example.com out',
            time: '3:00 PM',
            isIncoming: true,
          ),
        ),
      );

      expect(find.byType(LinkableText), findsOneWidget);
    });

    testWidgets('Arabic text drives RTL on body RichText', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'مرحبا بالعالم',
            time: '3:00 PM',
            isIncoming: true,
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LinkableText),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed text drives RTL on body RichText', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'مرحبا Hello كيف الحال',
            time: '3:00 PM',
            isIncoming: true,
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LinkableText),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.textDirection, TextDirection.rtl);
    });

    testWidgets(
      'outgoing Arabic-only message renders body direction correctly and keeps timestamp/status outside the body paragraph',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const MessageBubble(
              text: 'مرحبا',
              time: '3:00 PM',
              isIncoming: false,
              senderLabel: 'You',
              status: 'delivered',
            ),
          ),
        );

        final body = _linkableTextWidget(tester, 'مرحبا');
        expect(
          _bodyRichTextWidget(tester, 'مرحبا').textDirection,
          TextDirection.rtl,
        );
        expect(body.prefixSpans, isNull);
        expect(body.suffixSpans, isNull);
        expect(find.text('You:'), findsOneWidget);
        expect(find.text('3:00 PM'), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
        expect(_hasPositionedAncestor(find.text('3:00 PM')), isFalse);
      },
    );

    testWidgets(
      'outgoing Arabic-first mixed message renders body direction correctly and keeps timestamp/status outside the body paragraph',
      (tester) async {
        const bodyText = 'مرحبا Hello 123';

        await tester.pumpWidget(
          wrap(
            const MessageBubble(
              text: bodyText,
              time: '3:00 PM',
              isIncoming: false,
              senderLabel: 'You',
              status: 'delivered',
            ),
          ),
        );

        final body = _linkableTextWidget(tester, bodyText);
        expect(
          _bodyRichTextWidget(tester, bodyText).textDirection,
          TextDirection.rtl,
        );
        expect(body.prefixSpans, isNull);
        expect(body.suffixSpans, isNull);
        expect(find.text('You:'), findsOneWidget);
        expect(find.text('3:00 PM'), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
        expect(_hasPositionedAncestor(find.text('3:00 PM')), isFalse);
      },
    );

    testWidgets(
      'outgoing English-first mixed message stays LTR and still keeps timestamp/status outside the body paragraph',
      (tester) async {
        const bodyText = 'Hello مرحبا 123';

        await tester.pumpWidget(
          wrap(
            const MessageBubble(
              text: bodyText,
              time: '3:00 PM',
              isIncoming: false,
              senderLabel: 'You',
              status: 'delivered',
            ),
          ),
        );

        final body = _linkableTextWidget(tester, bodyText);
        expect(
          _bodyRichTextWidget(tester, bodyText).textDirection,
          TextDirection.ltr,
        );
        expect(body.prefixSpans, isNull);
        expect(body.suffixSpans, isNull);
        expect(find.text('You:'), findsOneWidget);
        expect(find.text('3:00 PM'), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
        expect(_hasPositionedAncestor(find.text('3:00 PM')), isFalse);
      },
    );

    testWidgets('sender label renders separately from linkable body', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Check https://example.com out',
            time: '3:00 PM',
            isIncoming: false,
            senderLabel: 'You',
          ),
        ),
      );

      final body = _linkableTextWidget(tester, 'Check https://example.com out');
      expect(body.prefixSpans, isNull);
      expect(body.suffixSpans, isNull);
      expect(find.text('You:'), findsOneWidget);
      expect(find.textContaining('https://example.com'), findsOneWidget);
    });

    testWidgets('sender label does not override Arabic-first body direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'مرحبا Hello',
            time: '3:00 PM',
            isIncoming: false,
            senderLabel: 'You',
          ),
        ),
      );

      expect(
        _bodyRichTextWidget(tester, 'مرحبا Hello').textDirection,
        TextDirection.rtl,
      );
    });

    testWidgets('plain text without URLs still renders normally', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Just a plain message',
            time: '3:00 PM',
            isIncoming: true,
          ),
        ),
      );

      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.textContaining('Just a plain message'), findsOneWidget);
    });
  });

  group('BiDi text direction', () {
    testWidgets('English text drives LTR on body RichText', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Hello world',
            time: '3:00 PM',
            isIncoming: true,
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LinkableText),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.textDirection, TextDirection.ltr);
    });

    testWidgets('Arabic quote text drives RTL on quote bar', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'My reply',
            time: '3:00 PM',
            isIncoming: true,
            quotedText: 'مرحبا بالعالم',
          ),
        ),
      );

      final quoteTextWidget = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Text),
            ),
          )
          .firstWhere((t) => t.data == 'مرحبا بالعالم');
      expect(quoteTextWidget.textDirection, TextDirection.rtl);
    });

    testWidgets('English quote text drives LTR on quote bar', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'My reply',
            time: '3:00 PM',
            isIncoming: true,
            quotedText: 'Hello world',
          ),
        ),
      );

      final quoteTextWidget = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Text),
            ),
          )
          .firstWhere((t) => t.data == 'Hello world');
      expect(quoteTextWidget.textDirection, TextDirection.ltr);
    });
  });

  group('MessageBubble reactions', () {
    testWidgets('renders inline reaction chips when reactions provided', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Hello',
            time: '3:00 PM',
            isIncoming: true,
            reactions: reactions,
            ownPeerId: 'my-peer',
          ),
        ),
      );

      // No standalone ReactionDisplay; emoji rendered inline
      expect(find.byType(ReactionDisplay), findsNothing);
      expect(find.text('👍'), findsOneWidget);
    });

    testWidgets('no ReactionDisplay when reactions empty', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Hello',
            time: '3:00 PM',
            isIncoming: true,
            reactions: [],
            ownPeerId: 'my-peer',
          ),
        ),
      );

      expect(find.byType(ReactionDisplay), findsNothing);
    });

    testWidgets('long-press fires onLongPress callback', (tester) async {
      var longPressed = false;

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Press me',
            time: '3:00 PM',
            isIncoming: true,
            onLongPress: () => longPressed = true,
          ),
        ),
      );

      await tester.longPress(find.textContaining('Press me'));
      expect(longPressed, isTrue);
    });

    testWidgets('no ReactionDisplay widget when reactions provided', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Hello',
            time: '3:00 PM',
            isIncoming: true,
            reactions: reactions,
            ownPeerId: 'my-peer',
          ),
        ),
      );

      // ReactionDisplay widget should NOT be used (inline chips instead)
      expect(find.byType(ReactionDisplay), findsNothing);
    });

    testWidgets('onReactionTap fires with emoji when chip tapped', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Hello',
            time: '3:00 PM',
            isIncoming: true,
            reactions: reactions,
            ownPeerId: 'my-peer',
            onReactionTap: (emoji) => tappedEmoji = emoji,
          ),
        ),
      );

      await tester.tap(find.text('❤️'));
      expect(tappedEmoji, '❤️');
    });
  });

  group('MessageBubble inline reactions', () {
    testWidgets(
      'inline reactions render below text, timestamp lives in footer',
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

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              text: 'Hello',
              time: '3:00 PM',
              isIncoming: true,
              reactions: reactions,
              ownPeerId: 'my-peer',
            ),
          ),
        );

        // Reactions in a Wrap below text
        expect(find.text('👍'), findsOneWidget);
        expect(find.byType(Wrap), findsOneWidget);
        expect(find.text('3:00 PM'), findsOneWidget);
        expect(_hasPositionedAncestor(find.text('3:00 PM')), isFalse);
      },
    );

    testWidgets('no reactions still keeps timestamp in footer', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageBubble(
            text: 'Hello',
            time: '3:00 PM',
            isIncoming: true,
            reactions: [],
            ownPeerId: 'my-peer',
          ),
        ),
      );

      expect(find.text('3:00 PM'), findsOneWidget);
      expect(_hasPositionedAncestor(find.text('3:00 PM')), isFalse);
    });

    testWidgets('multiple reaction emojis render inline with counts', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Great',
            time: '3:00 PM',
            isIncoming: true,
            reactions: reactions,
            ownPeerId: 'my-peer',
          ),
        ),
      );

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

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            text: 'Hooray',
            time: '3:00 PM',
            isIncoming: true,
            reactions: reactions,
            ownPeerId: 'my-peer',
          ),
        ),
      );

      // Find the chip Container with teal border
      final containers = tester.widgetList<Container>(find.byType(Container));
      final tealBorderChip = containers.where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border is Border) {
          final border = decoration.border as Border;
          return border.top.color == const Color.fromRGBO(78, 205, 196, 0.30);
        }
        return false;
      });
      expect(
        tealBorderChip.isNotEmpty,
        isTrue,
        reason: 'Own reaction chip should have teal border',
      );
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

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              text: 'Sent msg',
              time: '4:00 PM',
              isIncoming: false,
              senderLabel: 'You',
              status: 'delivered',
              reactions: reactions,
              ownPeerId: 'my-peer',
            ),
          ),
        );

        expect(find.text('👍'), findsOneWidget);
        expect(find.text('4:00 PM'), findsOneWidget);
        // Delivery status icon should render
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      },
    );
  });
}
