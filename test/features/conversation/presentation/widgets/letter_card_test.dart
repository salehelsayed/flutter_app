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
    bool transportStatusGlyph = false,
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
            transportStatusGlyph: transportStatusGlyph,
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

      // 210 TC #1: a group message queued while the sender is offline renders a
      // CLOCK (schedule) glyph — a benign "waiting to send" state derived purely
      // from the persisted 'queued_offline' status — never a tick, an error, the
      // inbox glyph, or the two-tick. Legacy path only (transportStatusGlyph is
      // 1:1-only and is not set for group bubbles).
      testWidgets(
        "status 'queued_offline' renders a clock (schedule) glyph, not a tick",
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'queued_offline'),
          );
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);
          expect(find.byIcon(Icons.inbox_rounded), findsNothing);
        },
      );

      // 210 TC #2 (guard, GREEN on HEAD): the new 'queued_offline' clock must NOT
      // broaden to the in-flight states — 'sending' and 'pending' stay a single
      // tick (online in-doubt / legacy unchanged), never the clock.
      testWidgets(
        "'sending' and 'pending' still render a single tick, never the clock "
        '(210 guard)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'sending'),
          );
          expect(find.byIcon(Icons.done_rounded), findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);

          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'pending'),
          );
          expect(find.byIcon(Icons.done_rounded), findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        },
      );

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

      // 155: a message that reached the inbox reads as a good "in the inbox"
      // state — the inbox glyph, NEVER the two-tick done_all (retired from the
      // UI; the 'delivered' status itself is preserved in the model).
      testWidgets(
        "status 'delivered' renders the inbox glyph and never the two-tick",
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'delivered'),
          );
          expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        },
      );

      // 155: legacy 'queued' rows render the same inbox glyph, never done_all.
      testWidgets(
        "legacy status 'queued' renders the inbox glyph and never the two-tick",
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'queued'),
          );
          expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        },
      );

      testWidgets('shows failed icon when status is failed', (tester) async {
        await tester.pumpWidget(
          buildTestWidget(isIncoming: false, status: 'failed'),
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      });

      // 155 TC-06: terminal group send_failed keeps the error glyph
      // (preservation — the inbox-glyph change must not bleed into the error
      // family).
      testWidgets(
        "status 'send_failed' still renders the error icon, never the inbox glyph",
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'send_failed'),
          );
          expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
          expect(find.byIcon(Icons.inbox_rounded), findsNothing);
        },
      );

      // 184 TC-184-20 (clock→tick): 'pending' is genuinely in-flight — NOT yet
      // in the relay inbox — so it renders a SINGLE tick (the clock→tick change)
      // in the amber "still waiting" hue, and must NOT collapse into the inbox
      // glyph or the two-tick done_all (the pending/inboxed split is the point).
      testWidgets(
        'shows pending icon, color, and semantics when status is pending '
        '(single tick, never the inbox glyph or two-tick)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'pending'),
          );

          final iconFinder = find.byIcon(Icons.done_rounded);
          expect(iconFinder, findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);
          expect(find.byIcon(Icons.inbox_rounded), findsNothing);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);

          final icon = tester.widget<Icon>(iconFinder);
          expect(icon.color, const Color.fromRGBO(255, 200, 100, 0.50));
          expect(
            find.bySemanticsLabel('Message status: pending delivery via inbox'),
            findsOneWidget,
          );
        },
      );

      // 115 Phase 1.4 + 155 — 'inboxed' is relay CUSTODY: the message reached
      // the relay inbox, so it now reads as a good "in the inbox" state — the
      // inbox glyph (TC-01), never done_all (the doc-115 invariant is preserved
      // AND strengthened) and no longer the amber schedule clock (155 split:
      // the clock is reserved for 'pending', which is not yet inboxed).
      testWidgets(
        "status 'inboxed' renders the inbox glyph, never schedule, never done_all",
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'inboxed'),
          );

          final iconFinder = find.byIcon(Icons.inbox_rounded);
          expect(iconFinder, findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
        },
      );

      // 155 TC-04 — core anti-regression sweep: the two-tick done_all is
      // RETIRED from the UI and must never render for ANY outgoing status.
      testWidgets(
        'done_all (two-tick) is never rendered for ANY outgoing status',
        (tester) async {
          const statuses = <String>[
            'sending',
            'sent',
            'pending',
            'inboxed',
            'delivered',
            'queued',
            'failed',
            'send_failed',
          ];
          for (final status in statuses) {
            await tester.pumpWidget(
              buildTestWidget(isIncoming: false, status: status),
            );
            expect(
              find.byIcon(Icons.done_all_rounded),
              findsNothing,
              reason: "done_all must never render for status '$status'",
            );
          }
        },
      );

      // 155 TC-07 — the reached state ('inboxed'/'delivered') carries the new
      // "delivered to inbox" a11y label, not the old pending/delivered labels.
      testWidgets(
        "inboxed/delivered carry the 'delivered to inbox' a11y label",
        (tester) async {
          for (final status in const ['inboxed', 'delivered']) {
            await tester.pumpWidget(
              buildTestWidget(isIncoming: false, status: status),
            );
            expect(
              find.bySemanticsLabel('Message status: delivered to inbox'),
              findsOneWidget,
              reason: "status '$status' must use the new inbox a11y label",
            );
            expect(
              find.bySemanticsLabel(
                'Message status: pending delivery via inbox',
              ),
              findsNothing,
              reason: "status '$status' must NOT use the old pending label",
            );
            expect(
              find.bySemanticsLabel('Message status: delivered'),
              findsNothing,
              reason: "status '$status' must NOT use the old delivered label",
            );
          }
        },
      );

      // 155 TC-08 — the reached state uses the neutral (non-amber) muted color,
      // the same value 'sent' returns; 'pending' alone keeps the amber clock.
      testWidgets(
        'inboxed/delivered use the neutral status color; pending stays amber',
        (tester) async {
          const neutral = Color.fromRGBO(255, 255, 255, 0.25);
          const amber = Color.fromRGBO(255, 200, 100, 0.50);

          for (final status in const ['inboxed', 'delivered']) {
            await tester.pumpWidget(
              buildTestWidget(isIncoming: false, status: status),
            );
            final icon = tester.widget<Icon>(
              find.byIcon(Icons.inbox_rounded),
            );
            expect(
              icon.color,
              neutral,
              reason: "status '$status' must use the neutral muted color",
            );
            expect(icon.color, isNot(amber));
          }

          await tester.pumpWidget(
            buildTestWidget(isIncoming: false, status: 'pending'),
          );
          // 184 (clock→tick): 'pending' renders a single tick, not the clock,
          // but KEEPS the amber "still waiting" hue (only the glyph changed).
          final pendingIcon = tester.widget<Icon>(
            find.byIcon(Icons.done_rounded),
          );
          expect(pendingIcon.color, amber);
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

      // RT-W1 (FDC-13): a relay->direct upgrade renders a DISTINCT glyph
      // (Icons.upgrade), never the plain 'direct' device_hub nor the
      // unrecognized help_outline fallback.
      testWidgets('shows upgrade icon when transport is upgraded', (
        tester,
      ) async {
        await tester.pumpWidget(buildTestWidget(transport: 'upgraded'));
        expect(find.byIcon(Icons.upgrade), findsOneWidget);
        expect(find.byIcon(Icons.device_hub), findsNothing);
        expect(find.byIcon(Icons.help_outline), findsNothing);
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
          // 155: delivered (with reactions) renders the inbox glyph, never the
          // retired two-tick done_all.
          expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_all_rounded), findsNothing);

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

    // 156 QW-1 (TC-01): the bubble fill is already semi-opaque, so the
    // BackdropFilter blur was pure raster cost. Removing it must keep the solid
    // fill (no transparent/blurred bubble).
    testWidgets('renders a solid-fill bubble with NO BackdropFilter', (
      tester,
    ) async {
      await tester.pumpWidget(buildBubble(isIncoming: true));

      expect(
        find.descendant(
          of: find.byType(LetterCard),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );

      // The fill survives: the bubble Container still carries the incoming
      // surfaceRaised color.
      final colors = BackgroundReadableColors.dark;
      final fill = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == colors.surfaceRaised;
      });
      expect((fill.decoration as BoxDecoration).color, colors.surfaceRaised);
    });

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

  // ---------------------------------------------------------------------------
  // 155 — 1:1 transport status glyph (OUTGOING + INCOMING), behind the
  // `transportStatusGlyph` opt-in (set only by the 1:1 conversation screen).
  //
  // The 1:1 screen renders the bubble layout with the header hidden
  // (showAvatar/showSenderName false), so these tests mirror that config
  // EXACTLY — using the legacy full-width card would also paint the header
  // transport icon (`:318-326`) and double-render the glyph. Group keeps v1
  // (flag default false) and is locked by TC-18.
  // ---------------------------------------------------------------------------
  group('155 transport status glyph (1:1)', () {
    Widget buildTransportGlyph({
      bool isIncoming = false,
      String? status,
      String? transport,
      bool transportStatusGlyph = true,
      bool isDeleted = false,
      String text = 'Hello, this is a test message.',
      List<MediaAttachment> media = const [],
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
              width: 400,
              child: SingleChildScrollView(
                child: LetterCard(
                  senderPeerId: '12D3KooWTestPeerId1234567890',
                  senderName: isIncoming ? 'Alice' : 'You',
                  text: text,
                  time: '3:30 PM',
                  isIncoming: isIncoming,
                  status: status,
                  transport: transport,
                  isDeleted: isDeleted,
                  media: media,
                  bubbleLayout: true,
                  showAvatar: false,
                  showSenderName: false,
                  transportStatusGlyph: transportStatusGlyph,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ---- OUTGOING (transportStatusGlyph: true) ----------------------------

    // TC-01
    testWidgets(
      'TC-01 outgoing reached via relay → cell_tower (not inbox_rounded, '
      'not done_all)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(status: 'delivered', transport: 'relay'),
        );
        expect(find.byIcon(Icons.cell_tower), findsOneWidget);
        expect(find.byIcon(Icons.inbox_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      },
    );

    // TC-02
    testWidgets('TC-02 outgoing direct → device_hub', (tester) async {
      await tester.pumpWidget(
        buildTransportGlyph(status: 'sent', transport: 'direct'),
      );
      expect(find.byIcon(Icons.device_hub), findsOneWidget);
    });

    // TC-03
    testWidgets('TC-03 outgoing wifi → wifi', (tester) async {
      await tester.pumpWidget(
        buildTransportGlyph(status: 'delivered', transport: 'wifi'),
      );
      expect(find.byIcon(Icons.wifi), findsOneWidget);
    });

    // TC-04 / 184 TC-184-02 — a 1:1 'inboxed' (relay custody) now renders TWO
    // ticks (done_all), the honest "the system has it" milestone, NOT the inbox
    // glyph. The glyph is a pure function of the persisted status, so a reloaded
    // 'inboxed' row reconstructs the two-tick on reopen (durability).
    testWidgets(
      'TC-184-02 outgoing inboxed (custody) → two ticks done_all (never the '
      'inbox glyph, schedule, or inbox_rounded)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(status: 'inboxed', transport: 'inbox'),
        );
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
        expect(find.byIcon(Icons.inbox), findsNothing);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.byIcon(Icons.inbox_rounded), findsNothing);
      },
    );

    // TC-05
    testWidgets(
      'TC-05 outgoing reached + null transport → single-check fallback',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(status: 'delivered', transport: null),
        );
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.help_outline), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      },
    );

    // TC-06 / 184 TC-184-01 — in-flight (pending/sending) renders a SINGLE tick
    // (the clock→tick change), never the transport glyph and never the two-tick.
    testWidgets(
      'TC-06 outgoing in-flight (pending/sending) → single tick, never '
      'transport glyph or two-tick',
      (tester) async {
        for (final status in const ['pending', 'sending']) {
          await tester.pumpWidget(
            buildTransportGlyph(status: status, transport: 'relay'),
          );
          expect(
            find.byIcon(Icons.done_rounded),
            findsOneWidget,
            reason: "status '$status' must show the single tick",
          );
          expect(
            find.byIcon(Icons.schedule_rounded),
            findsNothing,
            reason: "status '$status' must NOT show the clock",
          );
          expect(
            find.byIcon(Icons.done_all_rounded),
            findsNothing,
            reason: "status '$status' must NOT show the two-tick",
          );
          expect(
            find.byIcon(Icons.cell_tower),
            findsNothing,
            reason: "status '$status' must NOT show the transport glyph",
          );
        }
      },
    );

    // TC-07
    testWidgets(
      'TC-07 outgoing failed/send_failed → error, never transport glyph',
      (tester) async {
        for (final status in const ['failed', 'send_failed']) {
          await tester.pumpWidget(
            buildTransportGlyph(status: status, transport: 'relay'),
          );
          expect(
            find.byIcon(Icons.error_outline_rounded),
            findsOneWidget,
            reason: "status '$status' must show the error glyph",
          );
          expect(find.byIcon(Icons.cell_tower), findsNothing);
        }
      },
    );

    // 184 TC-184-21 — the two-tick done_all contract for the 1:1 path: it is the
    // EXPECTED glyph ONLY for 'inboxed' (relay custody) and must be ABSENT for
    // every other outgoing status (in-flight, reached-live, failed). The legacy
    // path (flag false) never renders done_all — locked by the 155 TC-04 sweep.
    testWidgets(
      'TC-184-21 done_all renders ONLY for 1:1 inboxed, never for other '
      'outgoing statuses',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(status: 'inboxed', transport: 'inbox'),
        );
        expect(
          find.byIcon(Icons.done_all_rounded),
          findsOneWidget,
          reason: '1:1 inboxed (custody) IS the two-tick',
        );

        const others = <(String, String?)>[
          ('sending', 'relay'),
          ('sent', 'direct'),
          ('delivered', 'wifi'),
          ('delivered', 'direct'),
          ('delivered', null),
          ('failed', 'relay'),
          ('send_failed', 'relay'),
        ];
        for (final (status, transport) in others) {
          await tester.pumpWidget(
            buildTransportGlyph(status: status, transport: transport),
          );
          expect(
            find.byIcon(Icons.done_all_rounded),
            findsNothing,
            reason: "done_all must NOT render for 1:1 status '$status'",
          );
        }
      },
    );

    // ---- INCOMING (transportStatusGlyph: true, status null) ---------------

    // TC-08
    testWidgets(
      'TC-08 incoming via inbox → inbox glyph (arrived-while-away)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(isIncoming: true, transport: 'inbox'),
        );
        expect(find.byIcon(Icons.inbox), findsOneWidget);
      },
    );

    // TC-09
    testWidgets('TC-09 incoming direct → device_hub', (tester) async {
      await tester.pumpWidget(
        buildTransportGlyph(isIncoming: true, transport: 'direct'),
      );
      expect(find.byIcon(Icons.device_hub), findsOneWidget);
    });

    // TC-10
    testWidgets('TC-10 incoming relay → cell_tower', (tester) async {
      await tester.pumpWidget(
        buildTransportGlyph(isIncoming: true, transport: 'relay'),
      );
      expect(find.byIcon(Icons.cell_tower), findsOneWidget);
    });

    // TC-11
    testWidgets('TC-11 incoming wifi → wifi', (tester) async {
      await tester.pumpWidget(
        buildTransportGlyph(isIncoming: true, transport: 'wifi'),
      );
      expect(find.byIcon(Icons.wifi), findsOneWidget);
    });

    // TC-12
    testWidgets('TC-12 incoming null transport → no transport glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTransportGlyph(isIncoming: true, transport: null),
      );
      expect(find.byIcon(Icons.inbox), findsNothing);
      expect(find.byIcon(Icons.cell_tower), findsNothing);
      expect(find.byIcon(Icons.device_hub), findsNothing);
      expect(find.byIcon(Icons.wifi), findsNothing);
    });

    // TC-13
    testWidgets(
      'TC-13 incoming unknown transport → no glyph (not help_outline)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(isIncoming: true, transport: 'unknown'),
        );
        expect(find.byIcon(Icons.help_outline), findsNothing);
      },
    );

    // TC-14
    testWidgets('TC-14 incoming system transport → no glyph', (tester) async {
      await tester.pumpWidget(
        buildTransportGlyph(isIncoming: true, transport: 'system'),
      );
      expect(find.byIcon(Icons.help_outline), findsNothing);
      expect(find.byIcon(Icons.cell_tower), findsNothing);
    });

    // TC-15
    testWidgets('TC-15 incoming deleted row → no transport glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTransportGlyph(
          isIncoming: true,
          isDeleted: true,
          transport: 'relay',
          text: 'This message was deleted',
        ),
      );
      expect(find.byIcon(Icons.cell_tower), findsNothing);
    });

    // TC-16
    testWidgets(
      'TC-16 incoming transport glyph renders in BOTH inline and footer '
      'variants',
      (tester) async {
        // Inline variant: real body text → the meta folds inline (gate 2).
        await tester.pumpWidget(
          buildTransportGlyph(
            isIncoming: true,
            transport: 'relay',
            text: 'normal body text',
          ),
        );
        expect(
          find.byIcon(Icons.cell_tower),
          findsOneWidget,
          reason: 'inline variant must render the incoming transport glyph',
        );

        // Footer variant: empty text → the standalone footer meta Row renders
        // (gate 1).
        await tester.pumpWidget(
          buildTransportGlyph(
            isIncoming: true,
            transport: 'relay',
            text: '',
          ),
        );
        expect(
          find.byIcon(Icons.cell_tower),
          findsOneWidget,
          reason: 'footer variant must render the incoming transport glyph',
        );
      },
    );

    // ---- a11y / scoping ---------------------------------------------------

    // TC-17
    testWidgets(
      'TC-17 incoming uses "received via" a11y label; outgoing uses "sent '
      'via" — distinct, never the v1 status-inbox label',
      (tester) async {
        // The bubble attributes sender/time/status into one merged Semantics
        // node, so match the substring (RegExp), mirroring the bubble-layout
        // Semantics test above.
        await tester.pumpWidget(
          buildTransportGlyph(isIncoming: true, transport: 'relay'),
        );
        expect(
          find.bySemanticsLabel(RegExp('Received via cellular relay')),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(RegExp('Sent via cellular relay')),
          findsNothing,
        );

        await tester.pumpWidget(
          buildTransportGlyph(
            isIncoming: false,
            status: 'delivered',
            transport: 'relay',
          ),
        );
        expect(
          find.bySemanticsLabel(RegExp('Sent via cellular relay')),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(RegExp('Received via cellular relay')),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel(RegExp('delivered to inbox')),
          findsNothing,
        );
      },
    );

    // TC-18 — scoping lock: GROUP/legacy (flag false) keeps v1.
    testWidgets(
      'TC-18 flag false keeps v1 — outgoing reached→inbox_rounded (not '
      'transport glyph); incoming→nothing',
      (tester) async {
        // Outgoing delivered, flag FALSE → v1 inbox_rounded, NOT cell_tower
        // (even though a transport is supplied).
        await tester.pumpWidget(
          buildTransportGlyph(
            isIncoming: false,
            status: 'delivered',
            transport: 'relay',
            transportStatusGlyph: false,
          ),
        );
        expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
        expect(find.byIcon(Icons.cell_tower), findsNothing);

        // Incoming with transport, flag FALSE → no transport glyph at all.
        await tester.pumpWidget(
          buildTransportGlyph(
            isIncoming: true,
            transport: 'relay',
            transportStatusGlyph: false,
          ),
        );
        expect(find.byIcon(Icons.cell_tower), findsNothing);
      },
    );

    // ---- FDC-13: relay->direct UPGRADE badge (TC-19..TC-22) ---------------

    // TC-19 (RT-W2) — OUTGOING reached via 'upgraded' renders the distinct
    // upgrade glyph, never device_hub (plain direct), help_outline (fallback),
    // or the inbox glyph.
    testWidgets(
      'TC-19 outgoing reached via upgraded → upgrade icon (not device_hub, '
      'not inbox)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(status: 'delivered', transport: 'upgraded'),
        );
        expect(find.byIcon(Icons.upgrade), findsOneWidget);
        expect(find.byIcon(Icons.device_hub), findsNothing);
        expect(find.byIcon(Icons.help_outline), findsNothing);
        expect(find.byIcon(Icons.inbox_rounded), findsNothing);
      },
    );

    // TC-20 (RT-W3) — OUTGOING 'upgraded' a11y reads the new "Upgraded to
    // direct connection" label, never the plain "Sent via direct connection".
    // The bubble merges sender+time+status into ONE Semantics node, so match
    // by RegExp substring (mirrors TC-17). NOTE: the POSITIVE assert is the
    // RED driver (dropping the _sentViaSemantic 'upgraded' case falls back to
    // the generic label, failing the positive find); the negative "Sent via
    // direct connection" assert is a copy-paste-mislabel guard, not the RED
    // lock (the upgraded sent string is "Upgraded to …", not "Sent via …").
    testWidgets(
      'TC-20 outgoing upgraded a11y → message_sent_via_upgraded (not '
      'via_direct)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(status: 'delivered', transport: 'upgraded'),
        );
        expect(
          find.bySemanticsLabel(RegExp('Upgraded to direct connection')),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(RegExp('Sent via direct connection')),
          findsNothing,
        );
      },
    );

    // TC-21 (RT-W4) — INCOMING via 'upgraded' shows the incoming upgrade
    // glyph (the incoming glyph fires for any non-system/non-unknown
    // transport), never device_hub or help_outline.
    testWidgets(
      'TC-21 incoming via upgraded shows the incoming upgrade glyph',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(isIncoming: true, transport: 'upgraded'),
        );
        expect(find.byIcon(Icons.upgrade), findsOneWidget);
        expect(find.byIcon(Icons.device_hub), findsNothing);
        expect(find.byIcon(Icons.help_outline), findsNothing);
      },
    );

    // TC-22 (RT-W5) — INCOMING 'upgraded' a11y reads the new "Received via
    // upgraded direct connection" label, never the plain "Received via direct
    // connection" (the contiguous phrase is broken by "upgraded").
    testWidgets(
      'TC-22 incoming upgraded a11y → message_received_via_upgraded (not '
      'via_direct)',
      (tester) async {
        await tester.pumpWidget(
          buildTransportGlyph(isIncoming: true, transport: 'upgraded'),
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Received via upgraded direct connection'),
          ),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(RegExp('Received via direct connection')),
          findsNothing,
        );
      },
    );
  });
}
