import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/reaction_display.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
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
    String? failedReasonText,
    VoidCallback? onDeleteFailedMessage,
    void Function(String attachmentId)? onRetryUnavailableMedia,
    bool isRetryFailedMessageEnabled = true,
    String? failedMessageActionKeySuffix,
    String? failedMediaActionKeySuffix,
    bool requireVerifiedContentHash = false,
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
            failedReasonText: failedReasonText,
            onDeleteFailedMessage: onDeleteFailedMessage,
            onRetryUnavailableMedia: onRetryUnavailableMedia,
            isRetryFailedMessageEnabled: isRetryFailedMessageEnabled,
            failedMessageActionKeySuffix: failedMessageActionKeySuffix,
            failedMediaActionKeySuffix: failedMediaActionKeySuffix,
            requireVerifiedContentHash: requireVerifiedContentHash,
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

      testWidgets('shows pending media delivery note while media is sending', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: false,
            status: 'sending',
            text: '',
            media: const [
              MediaAttachment(
                id: 'sending-media',
                messageId: 'sending-message',
                mime: 'image/jpeg',
                size: 1024,
                mediaType: 'image',
                localPath: '/tmp/sending.jpg',
                downloadStatus: 'done',
                createdAt: '2026-02-27T10:00:00.000Z',
              ),
            ],
          ),
        );

        expect(find.text('Uploading media'), findsOneWidget);
        expect(
          find.text('Recipients will receive this after the upload finishes.'),
          findsOneWidget,
        );
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

      // 115 Phase 1.4 — 'inboxed' is relay CUSTODY, not delivery: render the
      // pending visual family (schedule glyph, amber, pending-inbox
      // semantics), never done_all (doc 115 G-B / D-1).
      testWidgets(
        "status 'inboxed' renders schedule icon with pending-inbox semantics, never done_all",
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'inboxed'),
          );

          final iconFinder = find.byIcon(Icons.schedule_rounded);
          expect(iconFinder, findsOneWidget);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);
          expect(find.byIcon(Icons.done_rounded), findsNothing);

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

      testWidgets(
        'MD-012 unavailable media actions are separate from failed-message resend',
        (tester) async {
          var failedMessageRetried = false;
          var failedMediaRetried = false;
          String? unavailableAttachmentId;

          await tester.pumpWidget(
            buildTestWidget(
              isIncoming: false,
              status: 'failed',
              text: '',
              requireVerifiedContentHash: true,
              media: const [
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
                MediaAttachment(
                  id: 'transient-failed-attachment',
                  messageId: 'failed-message',
                  mime: 'image/jpeg',
                  size: 10,
                  mediaType: 'image',
                  localPath: '/tmp/transient-failed.jpg',
                  // A transient `failed` download under the retry ceiling is
                  // retryable; tamper (integrity_failed) would be terminal.
                  downloadStatus: 'failed',
                  downloadRetryCount: 1,
                  contentHash:
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  encryptionKeyBase64: 'key-transient',
                  encryptionNonce: 'nonce-transient',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  createdAt: '2026-02-27T10:00:00.000Z',
                ),
              ],
              onRetryFailedMessage: () => failedMessageRetried = true,
              onRetryFailedMedia: () => failedMediaRetried = true,
              onRetryUnavailableMedia: (attachmentId) {
                unavailableAttachmentId = attachmentId;
              },
              failedMessageActionKeySuffix: 'failed-message',
              failedMediaActionKeySuffix: 'failed-message',
            ),
          );

          final unavailableRetry = find.byKey(
            const ValueKey(
              'unavailable-media-retry-failed-message-transient-failed-attachment',
            ),
          );
          expect(unavailableRetry, findsOneWidget);
          expect(
            find.byKey(const ValueKey('failed-message-retry-failed-message')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('failed-media-retry-failed-message')),
            findsOneWidget,
          );

          await tester.ensureVisible(unavailableRetry);
          await tester.tap(unavailableRetry);
          await tester.pump();

          expect(unavailableAttachmentId, 'transient-failed-attachment');
          expect(failedMessageRetried, isFalse);
          expect(failedMediaRetried, isFalse);
        },
      );
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

      testWidgets(
        'GFR-003 disables retry control when row retry is in flight',
        (tester) async {
          var retried = false;

          await tester.pumpWidget(
            buildTestWidget(
              isIncoming: false,
              status: 'failed',
              text: 'Retry this text',
              onRetryFailedMessage: () => retried = true,
              isRetryFailedMessageEnabled: false,
              failedMessageActionKeySuffix: 'failed-text',
            ),
          );

          final retryFinder = find.byKey(
            const ValueKey('failed-message-retry-failed-text'),
          );
          expect(retryFinder, findsOneWidget);
          expect(tester.widget<OutlinedButton>(retryFinder).onPressed, isNull);

          await tester.ensureVisible(retryFinder);
          await tester.tap(retryFinder);
          await tester.pump();

          expect(retried, isFalse);
        },
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Bubble layout (136 Phase 2) — TC-08..16. New OPTIONAL params on LetterCard.
  // Defaults preserve the legacy full-width card (TC-13 preservation sentinel).
  // ---------------------------------------------------------------------------
  group('bubble layout (136 Phase 2)', () {
    Widget buildBubble({
      double width = 400,
      bool isIncoming = true,
      bool bubbleLayout = true,
      bool isFirstInGroup = true,
      bool isLastInGroup = true,
      bool showAvatar = true,
      bool showSenderName = true,
      bool avatarOutsideBubble = false,
      bool isDeleted = false,
      bool isEdited = false,
      String senderName = 'Alice',
      String text = 'Hello, this is a test message.',
      String time = '3:30 PM',
      String? status,
      List<MessageReaction> reactions = const [],
      String? ownPeerId,
      VoidCallback? onLongPress,
      void Function(String emoji)? onReactionTap,
    }) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: <ThemeExtension<dynamic>>[
            BackgroundReadableColors.dark,
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: LetterCard(
                  senderPeerId: '12D3KooWTestPeerId1234567890',
                  senderName: senderName,
                  text: text,
                  time: time,
                  isIncoming: isIncoming,
                  status: status,
                  isDeleted: isDeleted,
                  isEdited: isEdited,
                  reactions: reactions,
                  ownPeerId: ownPeerId,
                  onLongPress: onLongPress,
                  onReactionTap: onReactionTap,
                  bubbleLayout: bubbleLayout,
                  isFirstInGroup: isFirstInGroup,
                  isLastInGroup: isLastInGroup,
                  showAvatar: showAvatar,
                  showSenderName: showSenderName,
                  avatarOutsideBubble: avatarOutsideBubble,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Returns the Align that directly wraps the card chrome in bubble mode.
    Align bubbleAlign(WidgetTester tester) {
      return tester.widget<Align>(
        find.ancestor(
          of: find.byType(ClipRRect),
          matching: find.byType(Align),
        ).first,
      );
    }

    // The Container that paints the bubble fill (carries the position-aware
    // BorderRadius) — the descendant of the ClipRRect with a BoxDecoration.
    BorderRadius bubbleRadius(WidgetTester tester) {
      final container = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.borderRadius != null;
      });
      return (container.decoration as BoxDecoration).borderRadius!
          as BorderRadius;
    }

    // The painted bubble width = the outer bubble ClipRRect's laid-out width.
    // The LetterCard's outer ClipRRect is an ancestor of any nested (avatar /
    // media) ClipRRect, so it is `.first` in depth-first order. Use a plain-text
    // bubble for geometry tests (a single ClipRRect) to avoid ambiguity.
    double bubbleWidth(WidgetTester tester) =>
        tester.getSize(find.byType(ClipRRect).first).width;

    // The painted bubble's left edge (outer ClipRRect top-left dx).
    double bubbleLeft(WidgetTester tester) =>
        tester.getTopLeft(find.byType(ClipRRect).first).dx;

    // TC-08
    testWidgets('aligns incoming left and outgoing right', (tester) async {
      await tester.pumpWidget(buildBubble(isIncoming: true));
      expect(bubbleAlign(tester).alignment, Alignment.centerLeft);

      await tester.pumpWidget(buildBubble(isIncoming: false));
      expect(bubbleAlign(tester).alignment, Alignment.centerRight);
    });

    // TC-09
    testWidgets('constrains bubble max width to ~78% of available width', (
      tester,
    ) async {
      await tester.pumpWidget(buildBubble(width: 400));

      final constrained = tester.widgetList<ConstrainedBox>(
        find.descendant(
          of: find.byType(Align),
          matching: find.byType(ConstrainedBox),
        ),
      );
      // A ConstrainedBox with a finite maxWidth <= ~78% of the 400px slot.
      final hasCap = constrained.any(
        (c) =>
            c.constraints.maxWidth.isFinite &&
            c.constraints.maxWidth <= 400 * 0.78 + 0.5 &&
            c.constraints.maxWidth >= 400 * 0.50,
      );
      expect(
        hasCap,
        isTrue,
        reason: 'Bubble should be wrapped in a ConstrainedBox capping maxWidth '
            'around 78% of the available width.',
      );
    });

    // TC-10 — corner radii stack by first/middle/last per side (WhatsApp look).
    // Speaker edge = LEFT for incoming, RIGHT for outgoing.
    // first-in-run (not last): squares the BOTTOM speaker-edge corner.
    // last-in-run (not first): squares the TOP speaker-edge corner.
    // middle (neither first nor last): squares BOTH speaker-edge corners.
    // first&last (standalone): fully kBubbleRadius (no squaring).
    testWidgets('corner radii stack by first/middle/last per side', (
      tester,
    ) async {
      const r = Radius.circular(kBubbleRadius);
      const sq = Radius.circular(kBubbleStackRadius);

      // Incoming first-in-run (not last): bottom-left squared.
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          isFirstInGroup: true,
          isLastInGroup: false,
          showAvatar: false,
          showSenderName: false,
        ),
      );
      var radius = bubbleRadius(tester);
      expect(radius.bottomLeft, sq, reason: 'incoming first squares bottom-left');
      expect(radius.topLeft, r);
      expect(radius.topRight, r);
      expect(radius.bottomRight, r);

      // Incoming middle (neither first nor last): top-left + bottom-left squared.
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          isFirstInGroup: false,
          isLastInGroup: false,
          showAvatar: false,
          showSenderName: false,
        ),
      );
      radius = bubbleRadius(tester);
      expect(radius.topLeft, sq);
      expect(radius.bottomLeft, sq);
      expect(radius.topRight, r);
      expect(radius.bottomRight, r);

      // Incoming last-in-run (not first): top-left squared.
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          isFirstInGroup: false,
          isLastInGroup: true,
          showAvatar: false,
          showSenderName: false,
        ),
      );
      radius = bubbleRadius(tester);
      expect(radius.topLeft, sq);
      expect(radius.bottomLeft, r);
      expect(radius.topRight, r);
      expect(radius.bottomRight, r);

      // Standalone (first & last): fully rounded.
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          isFirstInGroup: true,
          isLastInGroup: true,
          showAvatar: false,
          showSenderName: false,
        ),
      );
      radius = bubbleRadius(tester);
      expect(radius.topLeft, r);
      expect(radius.bottomLeft, r);
      expect(radius.topRight, r);
      expect(radius.bottomRight, r);

      // Outgoing mirrors on the RIGHT edge: first-in-run squares bottom-right.
      await tester.pumpWidget(
        buildBubble(
          isIncoming: false,
          isFirstInGroup: true,
          isLastInGroup: false,
          showAvatar: false,
          showSenderName: false,
        ),
      );
      radius = bubbleRadius(tester);
      expect(radius.bottomRight, sq, reason: 'outgoing first squares bottom-right');
      expect(radius.topRight, r);
      expect(radius.topLeft, r);
      expect(radius.bottomLeft, r);
    });

    // TC-11
    testWidgets(
      'showAvatar=false & showSenderName=false hides header and grows body '
      'top padding',
      (tester) async {
        // Baseline: header shown -> capture body top padding.
        await tester.pumpWidget(
          buildBubble(showAvatar: true, showSenderName: true, text: 'Hello'),
        );
        final headerPadding = tester
            .widgetList<Padding>(
              find.ancestor(
                of: find.byType(LinkableText),
                matching: find.byType(Padding),
              ),
            )
            .first
            .padding
            .resolve(TextDirection.ltr);
        final headerTop = headerPadding.top;

        // Chrome hidden: no avatar, no sender-name text, bigger body top pad.
        await tester.pumpWidget(
          buildBubble(showAvatar: false, showSenderName: false, text: 'Hello'),
        );
        expect(find.byType(UserAvatar), findsNothing);
        expect(find.text('Alice'), findsNothing);

        final hiddenPadding = tester
            .widgetList<Padding>(
              find.ancestor(
                of: find.byType(LinkableText),
                matching: find.byType(Padding),
              ),
            )
            .first
            .padding
            .resolve(TextDirection.ltr);
        expect(
          hiddenPadding.top,
          greaterThan(headerTop),
          reason: 'Body top padding should grow when the header is hidden.',
        );
      },
    );

    // TC-12 (INVERTED, 137) — continuation incoming balloons must be flush-left
    // (no ~42px avatar gutter). 136 indented continuations under the avatar;
    // 137 reverses that so every incoming balloon shares the recipient's left
    // edge (group screenshot bug #1).
    testWidgets(
      'continuation incoming balloon has NO ~42px leading avatar gutter',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: false,
            showSenderName: false,
            isFirstInGroup: false,
            isLastInGroup: true,
          ),
        );

        final gutters = tester.widgetList<SizedBox>(find.byType(SizedBox));
        final hasGutter = gutters.any(
          (sb) => sb.width != null && sb.width! >= 40 && sb.width! <= 46,
        );
        expect(
          hasGutter,
          isFalse,
          reason: 'Continuation incoming bubble must NOT keep a ~42px leading '
              'gutter — it should be flush-left like the first balloon.',
        );
      },
    );

    // TC-14
    testWidgets('bubble balloon still fires onLongPress', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        buildBubble(
          text: 'Hello',
          showAvatar: false,
          showSenderName: false,
          onLongPress: () => pressed = true,
        ),
      );
      await tester.longPress(find.text('Hello'));
      expect(pressed, isTrue);
    });

    // TC-15
    testWidgets('bubble balloon still fires onReactionTap for its message', (
      tester,
    ) async {
      String? tapped;
      await tester.pumpWidget(
        buildBubble(
          text: 'Hello',
          showAvatar: false,
          showSenderName: false,
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
          onReactionTap: (emoji) => tapped = emoji,
        ),
      );
      await tester.tap(find.text('👍'));
      expect(tapped, '👍');
    });

    // TC-16
    testWidgets(
      'chrome-hidden bubble exposes a continuation Semantics label naming the '
      'sender',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            senderName: 'Alice',
            showAvatar: false,
            showSenderName: false,
          ),
        );
        // No visible sender-name Text, but the sender stays attributable via
        // a Semantics label carrying the sender name.
        expect(find.text('Alice'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('Alice')), findsWidgets);
      },
    );

    // -----------------------------------------------------------------------
    // 137 — alignment / content-hug / inline timestamp (1:1 + group).
    // -----------------------------------------------------------------------

    // TC-A1 — every incoming balloon shares the same left edge (INV-1).
    testWidgets(
      'TC-A1 incoming first and continuation balloons share the same left edge',
      (tester) async {
        // First-in-run balloon (header: avatar + name).
        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: true,
            showSenderName: true,
            isFirstInGroup: true,
            isLastInGroup: false,
            text: 'same text',
          ),
        );
        final firstLeft = bubbleLeft(tester);

        // Continuation balloon (chrome hidden) with identical text/width.
        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: false,
            showSenderName: false,
            isFirstInGroup: false,
            isLastInGroup: false,
            text: 'same text',
          ),
        );
        final continuationLeft = bubbleLeft(tester);

        expect(
          continuationLeft,
          closeTo(firstLeft, 1.0),
          reason: 'Continuation incoming balloon must be flush-left with the '
              'first balloon (no avatar gutter drift).',
        );
      },
    );

    // TC-W1 — group first-in-run headered bubble hugs short text (header
    // Row+Expanded driver, INV-2).
    testWidgets('TC-W1 group first-in-run headered bubble hugs short text', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          width: 400,
          isIncoming: true,
          showAvatar: true,
          showSenderName: true,
          text: 'bbb',
        ),
      );

      expect(
        bubbleWidth(tester),
        lessThan(200),
        reason: 'A headered bubble with short text must hug name+text, not '
            'stretch to the 0.78 cap (~312 at a 400px slot).',
      );
    });

    // TC-W2 — continuation / 1:1 incoming bubble hugs short text (footer
    // Row+Expanded driver, INV-2).
    testWidgets('TC-W2 continuation incoming bubble hugs short text', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          width: 400,
          isIncoming: true,
          showAvatar: false,
          showSenderName: false,
          text: 'bbb',
        ),
      );

      expect(
        bubbleWidth(tester),
        lessThan(200),
        reason: 'A chrome-hidden bubble with short text must hug its content.',
      );
    });

    // TC-W3 — outgoing 1:1 bubble hugs short text and stays right-aligned.
    testWidgets(
      'TC-W3 outgoing bubble hugs short text and stays right-aligned',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            width: 400,
            isIncoming: false,
            showAvatar: false,
            showSenderName: false,
            text: 'ok',
            status: 'sent',
          ),
        );

        expect(
          bubbleWidth(tester),
          lessThan(200),
          reason: 'An outgoing bubble with short text must hug its content.',
        );
        expect(bubbleAlign(tester).alignment, Alignment.centerRight);
      },
    );

    // TC-T1 — incoming inline timestamp folds into the body text (INV-3, no
    // double-render).
    testWidgets(
      'TC-T1 timestamp renders inline within the body text (incoming)',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: false,
            showSenderName: false,
            text: 'bbb',
            time: '9:57 AM',
          ),
        );

        // The time Text is a DESCENDANT of the body LinkableText (a trailing
        // WidgetSpan), not a standalone footer Text.
        expect(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.text('9:57 AM'),
          ),
          findsOneWidget,
        );
        // And it is not double-rendered.
        expect(find.text('9:57 AM'), findsOneWidget);
      },
    );

    // TC-T2 — outgoing inline timestamp keeps the status tick adjacent in the
    // body (INV-3).
    testWidgets(
      'TC-T2 outgoing inline timestamp keeps the status tick in the body',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            isIncoming: false,
            showAvatar: false,
            showSenderName: false,
            text: 'ok',
            time: '9:57 AM',
            status: 'sent',
          ),
        );

        expect(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.text('9:57 AM'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.byIcon(Icons.done_rounded),
          ),
          findsOneWidget,
        );

        // Deviation A (the computeToPlainText no-op on _InlineMetaWidgetSpan)
        // must NOT strip the inline status a11y label — semantics travels the
        // independent computeSemanticsInformation path, not the plain-text one.
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsLabel(RegExp('Message status')), findsOneWidget);
        handle.dispose();
      },
    );

    // TC-W4 — a short bubble WITH reactions must STILL hug (INV-2 "hugs on
    // every code path"; plan §Risks "verify a reactions+inline-time bubble
    // still hugs"). Guards against the inline-footer reactions Wrap expanding
    // to the 0.78 width cap.
    testWidgets('TC-W4 short bubble with reactions still hugs', (tester) async {
      await tester.pumpWidget(
        buildBubble(
          width: 400,
          isIncoming: true,
          showAvatar: false,
          showSenderName: false,
          text: 'bbb',
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
        ),
      );

      expect(
        bubbleWidth(tester),
        lessThan(200),
        reason: 'A short bubble that also shows reactions must hug its content, '
            'not stretch to the 0.78 cap.',
      );
    });

    // TC-T5 (guard) — an empty-text (e.g. media-only) non-deleted bubble has no
    // body LinkableText to host the inline suffix, so it KEEPS the footer
    // timestamp (INV-4: metaInlined requires text.isNotEmpty).
    testWidgets('TC-T5 empty-text bubble keeps the footer timestamp', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          showAvatar: false,
          showSenderName: false,
          text: '',
          time: '9:57 AM',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('9:57 AM'), findsOneWidget);
      expect(find.byType(LinkableText), findsNothing);
    });

    // TC-T3 (guard) — a near-full line wraps the inline timestamp atomically,
    // never overflowing (INV-3 "wraps when no room").
    testWidgets('TC-T3 long text wraps the inline timestamp without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          width: 240,
          isIncoming: true,
          showAvatar: false,
          showSenderName: false,
          text: 'Supercalifragilisticexpialidocious',
          time: '9:57 AM',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('9:57 AM'), findsOneWidget);
    });

    // TC-T4 (guard) — deleted bubbles have no body LinkableText to host the
    // suffix span, so they KEEP the footer timestamp (INV-4 / RC-3 caveat).
    testWidgets('TC-T4 deleted bubble keeps the footer timestamp', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          showAvatar: false,
          showSenderName: false,
          isDeleted: true,
          text: 'This message was deleted',
          time: '9:57 AM',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('9:57 AM'), findsOneWidget);
      // Not inlined — the deleted body is a plain Text (no LinkableText).
      expect(
        find.descendant(
          of: find.byType(LinkableText),
          matching: find.text('9:57 AM'),
        ),
        findsNothing,
      );
    });

    // -----------------------------------------------------------------------
    // 137 follow-up — group run avatar rendered OUTSIDE the bubble.
    // -----------------------------------------------------------------------

    // TC-AV1 — with avatarOutsideBubble the run avatar is rendered but NOT
    // inside the bubble balloon (it lives in a left gutter beside it).
    testWidgets(
      'TC-AV1 avatarOutsideBubble renders the avatar outside the bubble',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: true,
            showSenderName: true,
            avatarOutsideBubble: true,
            text: 'hi',
          ),
        );

        // The avatar is still rendered...
        expect(find.byType(UserAvatar), findsOneWidget);
        // ...but NOT as a descendant of the bubble balloon (its ClipRRect).
        // (UserAvatar clips with ClipOval, so the only ClipRRect is the bubble.)
        expect(
          find.descendant(
            of: find.byType(ClipRRect).first,
            matching: find.byType(UserAvatar),
          ),
          findsNothing,
        );
      },
    );

    // TC-AV2 — first-in-run (avatar painted) and continuation (empty gutter)
    // incoming balloons share the SAME bubble left edge, both indented past the
    // reserved gutter.
    testWidgets(
      'TC-AV2 avatarOutsideBubble keeps run balloons aligned past the gutter',
      (tester) async {
        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: true,
            showSenderName: true,
            isFirstInGroup: true,
            isLastInGroup: false,
            avatarOutsideBubble: true,
            text: 'same text',
          ),
        );
        final firstLeft = bubbleLeft(tester);
        final firstAvatarCount = find.byType(UserAvatar).evaluate().length;

        await tester.pumpWidget(
          buildBubble(
            isIncoming: true,
            showAvatar: false,
            showSenderName: false,
            isFirstInGroup: false,
            isLastInGroup: false,
            avatarOutsideBubble: true,
            text: 'same text',
          ),
        );
        final continuationLeft = bubbleLeft(tester);
        final continuationAvatarCount = find.byType(UserAvatar).evaluate().length;

        // First balloon paints the avatar; continuation reserves an empty gutter.
        expect(firstAvatarCount, 1);
        expect(continuationAvatarCount, 0);
        // Both share the same bubble left edge (consistent gutter).
        expect(continuationLeft, closeTo(firstLeft, 1.0));
      },
    );

    // TC-AV3 (preservation) — the default (avatarOutsideBubble:false) keeps the
    // avatar INSIDE the bubble header (136 behavior), so the opt-in is scoped.
    testWidgets('TC-AV3 default keeps the avatar inside the bubble header', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          showAvatar: true,
          showSenderName: true,
          // avatarOutsideBubble defaults false.
          text: 'hi',
        ),
      );

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ClipRRect).first,
          matching: find.byType(UserAvatar),
        ),
        findsOneWidget,
      );
    });

    // TC-AV4 (RTL) — the incoming bubble is pinned to the PHYSICAL-left edge
    // (Alignment.centerLeft, not directional), so the run avatar must also stay
    // on the leading/physical-left side under RTL (Arabic) rather than flipping
    // to the inner/center-facing side.
    testWidgets(
      'TC-AV4 avatar stays on the physical-left of the incoming bubble under RTL',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
              extensions: <ThemeExtension<dynamic>>[
                BackgroundReadableColors.dark,
              ],
            ),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      child: LetterCard(
                        senderPeerId: '12D3KooWTestPeerId1234567890',
                        senderName: 'Alice',
                        text: 'hi',
                        time: '3:30 PM',
                        isIncoming: true,
                        bubbleLayout: true,
                        showAvatar: true,
                        showSenderName: true,
                        avatarOutsideBubble: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final avatarRight = tester.getTopRight(find.byType(UserAvatar)).dx;
        final bubbleLeftEdge = tester
            .getTopLeft(find.byType(ClipRRect).first)
            .dx;
        expect(
          avatarRight,
          lessThanOrEqualTo(bubbleLeftEdge + 1.0),
          reason: 'Under RTL the avatar must remain on the leading (physical-'
              'left) side of the incoming bubble, matching the physical-left '
              'Align — not flip to the inner side.',
        );
      },
    );

    // TC-AV5 — in avatar-outside (group) mode the sender name renders ABOVE the
    // bubble (outside it), not inside the bubble's header.
    testWidgets('TC-AV5 sender name renders above the bubble, not inside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          showAvatar: true,
          showSenderName: true,
          avatarOutsideBubble: true,
          senderName: 'Bob',
          text: 'b',
        ),
      );

      expect(find.text('Bob'), findsOneWidget);
      // The name is NOT inside the bubble balloon (its ClipRRect)...
      expect(
        find.descendant(
          of: find.byType(ClipRRect).first,
          matching: find.text('Bob'),
        ),
        findsNothing,
      );
      // ...and it sits ABOVE the bubble.
      final nameTop = tester.getTopLeft(find.text('Bob')).dy;
      final bubbleTop = tester.getTopLeft(find.byType(ClipRRect).first).dy;
      expect(nameTop, lessThan(bubbleTop));
    });

    // TC-H1 — the group avatar-outside bubble body is vertically compact:
    // smaller body padding and a tighter line height than the 1:1/legacy card
    // (which keep 1.65, so their find.text long-press target stays stable).
    testWidgets('TC-H1 group avatar-outside bubble body is vertically compact', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBubble(
          isIncoming: true,
          showAvatar: false,
          showSenderName: false,
          avatarOutsideBubble: true,
          text: 'hi',
        ),
      );

      final bodyPad = tester
          .widgetList<Padding>(
            find.ancestor(
              of: find.byType(LinkableText),
              matching: find.byType(Padding),
            ),
          )
          .first
          .padding
          .resolve(TextDirection.ltr);
      // Compact: top 8 + bottom 6 = 14 (vs the looser 12 + 8 = 20).
      expect(bodyPad.top + bodyPad.bottom, lessThanOrEqualTo(14));

      final body = tester.widget<LinkableText>(find.byType(LinkableText));
      expect(body.style!.height, lessThan(1.65));
    });

    // TC-AV6 (RTL) — a WIDE sender name must not push the bubble off the gutter
    // under RTL: the name-above Column is pinned LTR like the gutter, so the
    // bubble stays flush just right of the avatar.
    testWidgets(
      'TC-AV6 name-above bubble stays flush to the gutter under RTL',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
              extensions: <ThemeExtension<dynamic>>[
                BackgroundReadableColors.dark,
              ],
            ),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      child: LetterCard(
                        senderPeerId: '12D3KooWTestPeerId1234567890',
                        senderName: 'A very long sender display name indeed',
                        text: 'a',
                        time: '3:30 PM',
                        isIncoming: true,
                        bubbleLayout: true,
                        showAvatar: true,
                        showSenderName: true,
                        avatarOutsideBubble: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final bubbleLeft = tester.getTopLeft(find.byType(ClipRRect).first).dx;
        final avatarRight = tester.getTopRight(find.byType(UserAvatar)).dx;
        // The bubble sits just right of the avatar gutter (small gap), not
        // pushed far right by the wide name.
        expect(bubbleLeft - avatarRight, lessThan(16));
      },
    );
  });

  // TC-13 preservation sentinel: the flag-less default render is unchanged.
  group('bubble layout preservation (TC-13)', () {
    testWidgets(
      'default (no new flags) renders unchanged full-width card',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true));

        // Header avatar + sender name present (legacy full-width card).
        expect(find.byType(UserAvatar), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);

        // No bubble Align wraps the card in default mode.
        expect(
          find.ancestor(
            of: find.byType(ClipRRect),
            matching: find.byType(Align),
          ),
          findsNothing,
        );

        // BorderRadius.circular(24) intact on the ClipRRect.
        final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
        expect(clip.borderRadius, BorderRadius.circular(24));
      },
    );

    // TC-P1 (137 NEW preservation) — the legacy full-width card must NOT pick
    // up the bubble-mode hug / inline-timestamp scoping (INV-5). Guards against
    // a `mainAxisSize.min` / `Flexible` / inline-time change leaking into the
    // shared `_buildHeader` / `_buildBodyChildren` unconditionally.
    testWidgets(
      'TC-P1 legacy full-width card still fills width & keeps footer time',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(isIncoming: true, text: 'bbb'));

        // Fills the available width (legacy full-width card), not hugging 'bbb'.
        final cardWidth =
            tester.getSize(find.byType(ClipRRect).first).width;
        expect(
          cardWidth,
          greaterThan(600),
          reason: 'Legacy card must keep filling width; if bubble hug leaked it '
              'would shrink to hug the short text.',
        );

        // The footer timestamp stays in the footer Row (NOT folded into the
        // body LinkableText as a bubble-mode suffix span).
        expect(find.text('3:30 PM'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(LinkableText),
            matching: find.text('3:30 PM'),
          ),
          findsNothing,
        );
      },
    );
  });

  group('terminal send_failed status (Finding 05 Phase 4)', () {
    testWidgets('renders the same failed error indicator as a failed row', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(isIncoming: false, status: 'send_failed'),
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('offers a working manual retry affordance', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        buildTestWidget(
          isIncoming: false,
          status: 'send_failed',
          text: 'give up',
          onRetryFailedMessage: () => retried = true,
          failedMessageActionKeySuffix: 'sf1',
        ),
      );
      final retryButton = find.byKey(
        const ValueKey('failed-message-retry-sf1'),
      );
      expect(retryButton, findsOneWidget);
      await tester.tap(retryButton);
      expect(retried, isTrue);
    });

    testWidgets(
      'send_failed with failedReasonText renders reason + Delete and no Retry',
      (tester) async {
        var deleted = false;
        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: false,
            status: 'send_failed',
            text: 'give up',
            failedReasonText: "Couldn't send — this group was dissolved",
            onDeleteFailedMessage: () => deleted = true,
            failedMessageActionKeySuffix: 'sf2',
          ),
        );

        // Reason line is its own Text widget (matches find.text directly).
        expect(
          find.text("Couldn't send — this group was dissolved"),
          findsOneWidget,
        );
        // No Retry for a terminal row.
        expect(
          find.byKey(const ValueKey('failed-message-retry-sf2')),
          findsNothing,
        );
        // Delete affordance present and wired.
        final deleteButton = find.byKey(
          const ValueKey('failed-message-delete-sf2'),
        );
        expect(deleteButton, findsOneWidget);
        await tester.tap(deleteButton);
        expect(deleted, isTrue);
      },
    );

    testWidgets(
      'failedReasonText suppresses Retry even when a retry callback is supplied',
      (tester) async {
        var retried = false;
        await tester.pumpWidget(
          buildTestWidget(
            isIncoming: false,
            status: 'send_failed',
            text: 'give up',
            failedReasonText: "Couldn't send — you're no longer in this group",
            onRetryFailedMessage: () => retried = true,
            onDeleteFailedMessage: () {},
            failedMessageActionKeySuffix: 'sf3',
          ),
        );
        expect(
          find.byKey(const ValueKey('failed-message-retry-sf3')),
          findsNothing,
        );
        expect(retried, isFalse);
      },
    );
  });
}
