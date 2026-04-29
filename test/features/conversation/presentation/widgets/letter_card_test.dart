import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget buildTestWidget({
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
    bool isIncoming = true,
    String? status,
    String senderName = 'Alice',
    String text = 'Hello, this is a test message.',
    String time = '3:30 PM',
    String? transport,
    String? quotedText,
    bool isQuoteUnavailable = false,
    bool isEdited = false,
    bool isDeleted = false,
    List<MediaAttachment> media = const [],
    List<MessageReaction> reactions = const [],
    String? ownPeerId,
    VoidCallback? onLongPress,
    void Function(String emoji)? onReactionTap,
    VoidCallback? onRetryFailedMessage,
    VoidCallback? onRetryFailedMedia,
    VoidCallback? onDeleteFailedMedia,
    String? failedMessageActionKeySuffix,
    String? failedMediaActionKeySuffix,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LetterCard(
            senderPeerId: '12D3KooWTestPeerId1234567890',
            senderName: senderName,
            text: text,
            time: time,
            isIncoming: isIncoming,
            status: status,
            transport: transport,
            quotedText: quotedText,
            isQuoteUnavailable: isQuoteUnavailable,
            isEdited: isEdited,
            isDeleted: isDeleted,
            media: media,
            reactions: reactions,
            ownPeerId: ownPeerId,
            onLongPress: onLongPress,
            onReactionTap: onReactionTap,
            onRetryFailedMessage: onRetryFailedMessage,
            onRetryFailedMedia: onRetryFailedMedia,
            onDeleteFailedMedia: onDeleteFailedMedia,
            failedMessageActionKeySuffix: failedMessageActionKeySuffix,
            failedMediaActionKeySuffix: failedMediaActionKeySuffix,
          ),
        ),
      ),
    );
  }

  group('LetterCard', () {
    group('received (incoming) card', () {
      testWidgets('shows sender name', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('Alice'), findsOneWidget);
      });

      testWidgets('uses representative light readable roles for content', (
        tester,
      ) async {
        const colors = BackgroundReadableColors.representativeLight;

        await tester.pumpWidget(
          buildTestWidget(
            readableColors: colors,
            isIncoming: true,
            text: 'Hello مرحبا from Daylight',
            quotedText: 'Earlier readable message',
            transport: 'relay',
            status: 'delivered',
            reactions: const [
              MessageReaction(
                id: 'reaction-1',
                messageId: 'message-1',
                emoji: '👍',
                senderPeerId: 'own-peer',
                timestamp: '2026-03-15T10:15:30.000Z',
                createdAt: '2026-03-15T10:15:30.000Z',
              ),
            ],
            ownPeerId: 'own-peer',
          ),
        );

        final sender = tester.widget<Text>(find.text('Alice'));
        expectTextContrast(sender.style!.color!, colors.surfaceRaised);

        final body = tester.widget<LinkableText>(
          find.byWidgetPredicate(
            (widget) =>
                widget is LinkableText &&
                widget.text == 'Hello مرحبا from Daylight',
          ),
        );
        expectTextContrast(body.style!.color!, colors.surfaceRaised);

        final quote = tester.widget<Text>(
          find.text('Earlier readable message'),
        );
        expectTextContrast(quote.style!.color!, colors.surfaceRaised);

        final time = tester.widget<Text>(find.text('3:30 PM'));
        expectTextContrast(time.style!.color!, colors.surfaceRaised);
      });

      testWidgets('shows message text', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('Hello, this is a test message.'), findsOneWidget);
      });

      testWidgets('renders a long message body without throwing', (
        tester,
      ) async {
        final longText = List<String>.filled(
          24,
          'Long message content 0123456789',
        ).join(' ');

        await tester.pumpWidget(
          buildTestWidget(isIncoming: true, text: longText),
        );

        expect(find.text(longText), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('shows time', (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));
        expect(find.text('3:30 PM'), findsOneWidget);
      });

      testWidgets('shows edited indicator when the row is edited', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: true, isEdited: true),
        );

        expect(find.text('(edited)'), findsOneWidget);
      });

      testWidgets('shows deleted placeholder styling when the row is deleted', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: true,
            isDeleted: true,
            text: 'This message was deleted',
          ),
        );

        final placeholder = tester.widget<Text>(
          find.text('This message was deleted'),
        );
        expect(placeholder.style?.fontStyle, FontStyle.italic);
      });

      testWidgets('does not show delivery note', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: true, status: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });
    });

    group('sent (outgoing) card', () {
      testWidgets('shows sender name (You)', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, senderName: 'You', status: 'sent'),
        );
        expect(find.text('You'), findsOneWidget);
      });

      testWidgets('shows message body', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sent'),
        );
        expect(find.text('Hello, this is a test message.'), findsOneWidget);
      });

      testWidgets('shows one tick when status is sending', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sending'),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      });

      testWidgets('shows one tick when status is sent', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'sent'),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      });

      testWidgets('shows two ticks when status is delivered', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'delivered'),
        );
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      });

      testWidgets('shows two ticks when status is queued', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'queued'),
        );
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      });

      testWidgets('shows failed icon when status is failed', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'failed'),
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      });

      testWidgets(
        'shows pending icon, color, and semantics when status is pending',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'pending'),
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

      testWidgets('no delivery note when status is null', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      });
    });

    testWidgets('renders RingAvatar with 32px size', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final avatar32 = sizedBoxes.where(
        (sb) => sb.width == 32 && sb.height == 32,
      );
      expect(avatar32, isNotEmpty);
    });

    group('transport icons', () {
      testWidgets('shows wifi icon when transport is wifi', (tester) async {
        await tester.pumpWidget(buildTestWidget(transport: 'wifi'));
        expect(find.byIcon(Icons.wifi), findsOneWidget);
      });

      testWidgets('shows wifi icon when transport is local', (tester) async {
        await tester.pumpWidget(buildTestWidget(transport: 'local'));
        expect(find.byIcon(Icons.wifi), findsOneWidget);
      });

      testWidgets('shows relay icon when transport is relay', (tester) async {
        await tester.pumpWidget(buildTestWidget(transport: 'relay'));
        expect(find.byIcon(Icons.cell_tower), findsOneWidget);
      });

      testWidgets('shows direct icon when transport is direct', (tester) async {
        await tester.pumpWidget(buildTestWidget(transport: 'direct'));
        expect(find.byIcon(Icons.device_hub), findsOneWidget);
      });

      testWidgets('shows direct icon when transport is legacy reuse fallback', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(transport: 'reuse'));
        expect(find.byIcon(Icons.device_hub), findsOneWidget);
      });

      testWidgets('shows inbox icon when transport is inbox', (tester) async {
        await tester.pumpWidget(buildTestWidget(transport: 'inbox'));
        expect(find.byIcon(Icons.inbox), findsOneWidget);
      });

      testWidgets('shows no transport icon when transport is null', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(transport: null));
        expect(find.byIcon(Icons.wifi), findsNothing);
        expect(find.byIcon(Icons.cell_tower), findsNothing);
        expect(find.byIcon(Icons.inbox), findsNothing);
      });

      testWidgets('unrecognized transport shows help_outline icon', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(transport: 'carrier_pigeon'));
        expect(find.byIcon(Icons.help_outline), findsOneWidget);
      });
    });

    group('URL links', () {
      testWidgets('URL in message body renders as tappable link', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'Check https://example.com out'),
        );
        expect(find.byType(LinkableText), findsOneWidget);
      });

      testWidgets('Arabic-first mixed text drives RTL on body RichText', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(text: 'مرحبا Hello كيف حالك'));

        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byType(RichText),
          ),
        );
        expect(richText.textDirection, TextDirection.rtl);
      });

      testWidgets('English-first mixed text drives LTR on body RichText', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(text: 'Hello مرحبا World'));

        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byType(RichText),
          ),
        );
        expect(richText.textDirection, TextDirection.ltr);
      });

      testWidgets('Arabic text drives RTL on body RichText', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'مرحبا بالعالم'));

        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byType(RichText),
          ),
        );
        expect(richText.textDirection, TextDirection.rtl);
      });

      testWidgets('English text drives LTR on body RichText', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Hello world'));

        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byType(RichText),
          ),
        );
        expect(richText.textDirection, TextDirection.ltr);
      });

      testWidgets('URL has underline decoration', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'https://example.com'));
        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byType(RichText),
          ),
        );
        final outer = richText.text as TextSpan;
        final inner = outer.children![0] as TextSpan;
        final urlSpan = inner.children!.whereType<TextSpan>().first;
        expect(urlSpan.style?.decoration, TextDecoration.underline);
      });

      testWidgets('plain text without URLs still renders', (tester) async {
        await tester.pumpWidget(buildTestWidget(text: 'Just a plain message'));
        expect(find.byType(LinkableText), findsOneWidget);
        expect(find.textContaining('Just a plain message'), findsOneWidget);
      });
    });

    group('BiDi text direction', () {
      testWidgets('Arabic quote text drives RTL on quote bar', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'Reply body', quotedText: 'مرحبا بالعالم'),
        );

        final quoteTextWidget = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(LetterCard),
                matching: find.byType(Text),
              ),
            )
            .firstWhere((t) => t.data == 'مرحبا بالعالم');
        expect(quoteTextWidget.textDirection, TextDirection.rtl);
      });

      testWidgets('English quote text drives LTR on quote bar', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'Reply body', quotedText: 'Hello world'),
        );

        final quoteTextWidget = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(LetterCard),
                matching: find.byType(Text),
              ),
            )
            .firstWhere((t) => t.data == 'Hello world');
        expect(quoteTextWidget.textDirection, TextDirection.ltr);
      });

      testWidgets('Arabic-first mixed quoted text drives RTL on quote bar', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(text: 'Reply body', quotedText: 'مرحبا Hello كيف'),
        );

        final quoteTextWidget = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(LetterCard),
                matching: find.byType(Text),
              ),
            )
            .firstWhere((t) => t.data == 'مرحبا Hello كيف');
        expect(quoteTextWidget.textDirection, TextDirection.rtl);
      });
    });

    group('reactions', () {
      testWidgets('fires onLongPress on long-press', (tester) async {
        var pressed = false;
        await tester.pumpWidget(
          buildTestWidget(text: 'Hello', onLongPress: () => pressed = true),
        );
        await tester.longPress(find.text('Hello'));
        expect(pressed, isTrue);
      });

      testWidgets('fires onReactionTap when chip tapped', (tester) async {
        String? tappedEmoji;
        await tester.pumpWidget(
          buildTestWidget(
            text: 'Hello',
            ownPeerId: 'my-peer',
            reactions: const [
              MessageReaction(
                id: 'r1',
                messageId: 'msg-1',
                emoji: '👍',
                senderPeerId: 'sender-1',
                timestamp: '2026-02-27T10:00:00.000Z',
                createdAt: '2026-02-27T10:00:01.000Z',
              ),
            ],
            onReactionTap: (emoji) => tappedEmoji = emoji,
          ),
        );
        await tester.tap(find.text('👍'));
        expect(tappedEmoji, '👍');
      });
    });

    group('inline reactions', () {
      const kReactions = [
        MessageReaction(
          id: 'r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'sender-1',
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        ),
      ];

      testWidgets('reactions and timestamp share the same Row', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            text: 'Hello',
            ownPeerId: 'my-peer',
            reactions: kReactions,
          ),
        );

        final emojiElement = find.text('👍').evaluate().first;
        final timeElement = find.text('3:30 PM').evaluate().first;

        Row? emojiRow;
        emojiElement.visitAncestorElements((element) {
          if (element.widget is Row) {
            emojiRow = element.widget as Row;
            return false;
          }
          return true;
        });

        Row? timeRow;
        timeElement.visitAncestorElements((element) {
          if (element.widget is Row) {
            timeRow = element.widget as Row;
            return false;
          }
          return true;
        });

        expect(emojiRow, isNotNull, reason: 'Emoji should have a Row ancestor');
        expect(timeRow, isNotNull, reason: 'Time should have a Row ancestor');
        expect(
          emojiRow,
          same(timeRow),
          reason: 'Emoji and time should share the same Row',
        );
      });

      testWidgets('no reactions still right-aligns timestamp in footer Row', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(text: 'Hello'));

        final timeElement = find.text('3:30 PM').evaluate().first;
        Row? timeRow;
        timeElement.visitAncestorElements((element) {
          if (element.widget is Row) {
            timeRow = element.widget as Row;
            return false;
          }
          return true;
        });
        expect(timeRow, isNotNull, reason: 'Timestamp should be inside a Row');
      });

      testWidgets('no standalone ReactionDisplay when reactions provided', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(
            text: 'Hello',
            ownPeerId: 'my-peer',
            reactions: kReactions,
          ),
        );
        expect(find.text('👍'), findsOneWidget);
        expect(find.byType(ReactionDisplay), findsNothing);
      });

      testWidgets('multiple reaction emojis render inline with counts', (
        tester,
      ) async {
        const reactions = [
          MessageReaction(
            id: 'r1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'sender-1',
            timestamp: '2026-02-27T10:00:00.000Z',
            createdAt: '2026-02-27T10:00:01.000Z',
          ),
          MessageReaction(
            id: 'r2',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'sender-2',
            timestamp: '2026-02-27T10:01:00.000Z',
            createdAt: '2026-02-27T10:01:01.000Z',
          ),
          MessageReaction(
            id: 'r3',
            messageId: 'msg-1',
            emoji: '❤️',
            senderPeerId: 'sender-3',
            timestamp: '2026-02-27T10:02:00.000Z',
            createdAt: '2026-02-27T10:02:01.000Z',
          ),
        ];

        await tester.pumpWidget(
          buildTestWidget(
            text: 'Great',
            ownPeerId: 'my-peer',
            reactions: reactions,
          ),
        );

        expect(find.text('👍 2'), findsOneWidget);
        expect(find.text('❤️'), findsOneWidget);
        expect(find.text('3:30 PM'), findsOneWidget);
        expect(find.byType(ReactionDisplay), findsNothing);
      });

      testWidgets('own reaction chip has teal border inline', (tester) async {
        const reactions = [
          MessageReaction(
            id: 'r1',
            messageId: 'msg-1',
            emoji: '🎉',
            senderPeerId: 'my-peer',
            timestamp: '2026-02-27T10:00:00.000Z',
            createdAt: '2026-02-27T10:00:01.000Z',
          ),
        ];

        await tester.pumpWidget(
          buildTestWidget(
            text: 'Hooray',
            ownPeerId: 'my-peer',
            reactions: reactions,
          ),
        );

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
        expect(find.byType(ReactionDisplay), findsNothing);
      });

      testWidgets(
        'sent message with reactions and delivery status renders inline',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(
              text: 'Sent msg',
              time: '4:00 PM',
              isIncoming: false,
              status: 'delivered',
              ownPeerId: 'my-peer',
              reactions: kReactions,
            ),
          );

          expect(find.text('👍'), findsOneWidget);
          expect(find.text('4:00 PM'), findsOneWidget);
          expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);

          // Verify emoji and time share the same Row
          final emojiElement = find.text('👍').evaluate().first;
          final timeElement = find.text('4:00 PM').evaluate().first;

          Row? emojiRow;
          emojiElement.visitAncestorElements((element) {
            if (element.widget is Row) {
              emojiRow = element.widget as Row;
              return false;
            }
            return true;
          });

          Row? timeRow;
          timeElement.visitAncestorElements((element) {
            if (element.widget is Row) {
              timeRow = element.widget as Row;
              return false;
            }
            return true;
          });

          expect(
            emojiRow,
            same(timeRow),
            reason: 'Emoji, time, and status should share the same Row',
          );
        },
      );

      testWidgets('timestamp appears in footer row, not in header', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(text: 'Hello'));

        final timeElement = find.text('3:30 PM').evaluate().first;

        // Walk up to find the nearest Row ancestor of the timestamp
        Row? timeRow;
        Element? timeRowElement;
        timeElement.visitAncestorElements((element) {
          if (element.widget is Row) {
            timeRow = element.widget as Row;
            timeRowElement = element;
            return false;
          }
          return true;
        });

        expect(timeRow, isNotNull);

        // The time's Row should NOT contain a UserAvatar descendant
        // (that would mean it's in the header row)
        // Check there's no 32x32 avatar in the same row
        bool hasAvatar = false;
        timeRowElement!.visitChildElements((child) {
          child.visitChildElements((grandchild) {
            if (grandchild.widget is SizedBox) {
              final sb = grandchild.widget as SizedBox;
              if (sb.width == 32 && sb.height == 32) hasAvatar = true;
            }
          });
        });
        expect(
          hasAvatar,
          isFalse,
          reason: 'Timestamp Row should not contain the avatar (header)',
        );
      });
    });

    group('failed media actions', () {
      const kFailedMedia = [
        MediaAttachment(
          id: 'failed-attachment',
          messageId: 'failed-message',
          mime: 'image/jpeg',
          size: 10,
          mediaType: 'image',
          localPath: '/tmp/failed.jpg',
          downloadStatus: 'upload_failed',
          createdAt: '2026-02-27T10:00:00.000Z',
        ),
      ];

      testWidgets('shows retry and delete controls when callbacks are wired', (
        tester,
      ) async {
        var retried = false;
        var deleted = false;

        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: false,
            status: 'failed',
            text: '',
            media: kFailedMedia,
            onRetryFailedMedia: () => retried = true,
            onDeleteFailedMedia: () => deleted = true,
            failedMediaActionKeySuffix: 'failed-message',
          ),
        );

        final retryFinder = find.byKey(
          const ValueKey('failed-media-retry-failed-message'),
        );
        final deleteFinder = find.byKey(
          const ValueKey('failed-media-delete-failed-message'),
        );
        expect(retryFinder, findsOneWidget);
        expect(deleteFinder, findsOneWidget);

        await tester.ensureVisible(retryFinder);
        await tester.tap(retryFinder);
        await tester.pump();
        await tester.ensureVisible(deleteFinder);
        await tester.tap(deleteFinder);
        await tester.pump();

        expect(retried, isTrue);
        expect(deleted, isTrue);
      });

      testWidgets('hides failed media controls when callbacks are absent', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: false,
            status: 'failed',
            text: '',
            media: kFailedMedia,
            failedMediaActionKeySuffix: 'failed-message',
          ),
        );

        expect(
          find.byKey(const ValueKey('failed-media-retry-failed-message')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-media-delete-failed-message')),
          findsNothing,
        );
      });
    });

    group('failed text actions', () {
      testWidgets('shows retry control when callback is wired', (tester) async {
        var retried = false;

        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: false,
            status: 'failed',
            text: 'Retry this text',
            onRetryFailedMessage: () => retried = true,
            failedMessageActionKeySuffix: 'failed-text',
          ),
        );

        final retryFinder = find.byKey(
          const ValueKey('failed-message-retry-failed-text'),
        );
        expect(retryFinder, findsOneWidget);
        expect(find.bySemanticsLabel('Retry failed message'), findsOneWidget);

        await tester.ensureVisible(retryFinder);
        await tester.tap(retryFinder);
        await tester.pump();

        expect(retried, isTrue);
      });
    });
  });
}
