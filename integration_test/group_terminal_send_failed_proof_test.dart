/// Real-device proof for 144 — group terminal send-failure inline bubble +
/// reliable read-only banner.
///
/// The terminal keep-bubble / read-only-latch LOGIC is plain Dart and fully
/// host-proven (`group_conversation_wired_test.dart`). The one genuine
/// host↔device gap for 144 is *rendering* the NEW presentation surface on real
/// iOS: the per-message "Couldn't send — …" reason line, the Delete-only
/// (no-Retry) failed-action row, the read-only composer banner that replaces
/// the compose area, real-iOS Arabic RTL shaping of the reason via
/// `detectTextDirection`, and the retry-exhausted-vs-terminal split. This proof
/// renders the REAL `GroupConversationScreen` (where `buildLetterCard` wires
/// `failedReasonText`/`onDeleteFailedMessage` and `_buildReadOnlyBanner` lives)
/// on a booted simulator and asserts those behaviors under real iOS.
///
/// Proves on-device:
///   * Terminal `send_failed` bubble keeps the body + shows the reason line +
///     Delete, and NEVER a Retry control (dissolved / removed reasons, en).
///   * The read-only banner physically replaces the composer (no TextField),
///     with the reason-correct copy.
///   * Delete stays hit-testable in the real viewport while read-only and fires.
///   * Arabic reason renders right-to-left under real iOS bidi.
///   * A retry-exhausted `send_failed` in a still-writable group shows NO
///     terminal reason / Retry, keeps Delete for cleanup, and keeps the
///     composer (separation, INV-4).
@Tags(['device'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const ownPeerId = 'peer-self';

  GroupModel chatGroup() => GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.utc(2026, 2, 1, 10),
    createdBy: ownPeerId,
    myRole: GroupRole.member,
  );

  GroupMessage ownMessage({
    required String id,
    required String status,
    String text = 'Hey team',
  }) => GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: ownPeerId,
    senderUsername: 'Me',
    text: text,
    timestamp: DateTime(2026, 2, 9, 14, 5),
    createdAt: DateTime(2026, 2, 9, 14, 5),
    isIncoming: false,
    status: status,
  );

  Widget conversationApp({
    required Locale locale,
    required List<GroupMessage> messages,
    required bool canWrite,
    String? readOnlyBannerText,
    String? failedTerminalReasonText,
    ValueChanged<String>? onDeleteFailedTerminalMessage,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GroupConversationScreen(
          group: chatGroup(),
          messages: messages,
          ownPeerId: ownPeerId,
          onSend: (_) {},
          onBack: () {},
          canWrite: canWrite,
          initialLoadDone: true,
          readOnlyBannerText: readOnlyBannerText,
          failedTerminalReasonText: failedTerminalReasonText,
          onDeleteFailedTerminalMessage: onDeleteFailedTerminalMessage,
        ),
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  bool rectWithin(Rect inner, Rect outer) =>
      inner.top >= outer.top - 1 &&
      inner.bottom <= outer.bottom + 1 &&
      inner.overlaps(outer);

  group('144 terminal send-failed bubble + read-only banner (real iOS)', () {
    testWidgets(
      'dissolved: failed bubble keeps body + reason + Delete, no Retry, banner '
      'replaces composer',
      (tester) async {
        var deletedId = '';
        await tester.pumpWidget(
          conversationApp(
            locale: const Locale('en'),
            messages: [ownMessage(id: 'sf-1', status: 'send_failed')],
            canWrite: false,
            readOnlyBannerText:
                'This group has been dissolved. History stays available, but '
                'new messages are disabled.',
            failedTerminalReasonText:
                "Couldn't send — this group was dissolved",
            onDeleteFailedTerminalMessage: (id) => deletedId = id,
          ),
        );
        await pumpFrames(tester);

        // Body retained + reason line rendered on real iOS.
        expect(find.text('Hey team'), findsOneWidget);
        expect(
          find.text("Couldn't send — this group was dissolved"),
          findsOneWidget,
        );

        // Non-retryable: Delete present, Retry absent.
        final deleteButton = find.byKey(
          const ValueKey('failed-message-delete-sf-1'),
        );
        expect(deleteButton, findsOneWidget);
        expect(
          find.byKey(const ValueKey('failed-message-retry-sf-1')),
          findsNothing,
        );

        // Read-only banner physically replaces the composer.
        final banner = find.byKey(const ValueKey('group-read-only-banner'));
        expect(banner, findsOneWidget);
        expect(
          find.descendant(
            of: banner,
            matching: find.text(
              'This group has been dissolved. History stays available, but '
              'new messages are disabled.',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);

        // Delete is hit-testable in the real viewport and fires.
        final listRect = tester.getRect(
          find.byKey(const ValueKey('group-messages')),
        );
        expect(rectWithin(tester.getRect(deleteButton), listRect), isTrue);
        await tester.tap(deleteButton);
        await pumpFrames(tester);
        expect(deletedId, 'sf-1');
      },
    );

    testWidgets('removed: reason + banner copy are the "not active" strings', (
      tester,
    ) async {
      await tester.pumpWidget(
        conversationApp(
          locale: const Locale('en'),
          messages: [ownMessage(id: 'sf-2', status: 'send_failed')],
          canWrite: false,
          readOnlyBannerText:
              "You can read this group's history, but you are not an active "
              'member.',
          failedTerminalReasonText:
              "Couldn't send — you're no longer in this group",
          onDeleteFailedTerminalMessage: (_) {},
        ),
      );
      await pumpFrames(tester);

      expect(
        find.text("Couldn't send — you're no longer in this group"),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('group-read-only-banner')),
          matching: find.text(
            "You can read this group's history, but you are not an active "
            'member.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('failed-message-delete-sf-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('failed-message-retry-sf-2')),
        findsNothing,
      );
    });

    testWidgets('ar: terminal reason renders right-to-left under real iOS bidi', (
      tester,
    ) async {
      const arabicReason = 'تعذّر الإرسال — تم حل هذه المجموعة';
      await tester.pumpWidget(
        conversationApp(
          locale: const Locale('ar'),
          messages: [ownMessage(id: 'sf-ar', status: 'send_failed')],
          canWrite: false,
          readOnlyBannerText: 'تعذّر الإرسال',
          failedTerminalReasonText: arabicReason,
          onDeleteFailedTerminalMessage: (_) {},
        ),
      );
      await pumpFrames(tester);

      final reason = find.byKey(
        const ValueKey('failed-message-reason-sf-ar'),
      );
      expect(reason, findsOneWidget);
      expect(tester.widget<Text>(reason).data, arabicReason);
      // detectTextDirection must resolve Arabic to RTL on the real device.
      expect(tester.widget<Text>(reason).textDirection, TextDirection.rtl);
    });

    testWidgets(
      'retry-exhausted send_failed in a writable group: no terminal reason / '
      'Retry, Delete cleanup and composer kept (separation)',
      (tester) async {
        await tester.pumpWidget(
          conversationApp(
            locale: const Locale('en'),
            messages: [ownMessage(id: 'sf-rx', status: 'send_failed')],
            canWrite: true,
            // No terminal failure latched.
            failedTerminalReasonText: null,
            onDeleteFailedTerminalMessage: (_) {},
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Hey team'), findsOneWidget);
        expect(find.textContaining("Couldn't send"), findsNothing);
        expect(
          find.byKey(const ValueKey('failed-message-reason-sf-rx')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-message-delete-sf-rx')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('failed-message-retry-sf-rx')),
          findsNothing,
        );
        // Composer stays writable; no read-only banner.
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
        expect(find.byType(TextField), findsOneWidget);
      },
    );
  });
}
