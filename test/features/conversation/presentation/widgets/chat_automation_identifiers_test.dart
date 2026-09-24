import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/call_timeline_row.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Beta 2026-09-24: stable accessibility identifiers (Android resource-id,
/// iOS accessibilityIdentifier) for UI automation of the chat surface. The
/// identifiers are added next to the existing labels and never replace them.
void main() {
  const contactPeerId = '12D3KooWTestPeerId1234567890';
  const ownPeerId = '12D3KooWMyPeerId1234567890';

  Widget app(Widget body) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Theme(
      data: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[
          BackgroundReadableColors.dark,
        ],
      ),
      child: Scaffold(body: body),
    ),
  );

  SemanticsData nodeWithIdentifier(WidgetTester tester, String identifier) {
    final finder = find.bySemanticsIdentifier(identifier);
    expect(finder, findsOneWidget, reason: 'missing identifier $identifier');
    final node = tester.getSemantics(finder);
    expect(node.identifier, identifier);
    return node.getSemanticsData();
  }

  testWidgets('BETA-0924-50 header call button carries chat_call_button and '
      'keeps its label', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        app(
          ConversationHeader(
            contactPeerId: contactPeerId,
            contactUsername: 'Alice',
            connectionDate: 'February 9, 2026',
            onBack: () {},
            onCall: () {},
            showCallAction: true,
            callActionEnabled: true,
          ),
        ),
      );

      final data = nodeWithIdentifier(tester, 'chat_call_button');
      expect(data.label, 'Start voice call');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('BETA-0924-51 composer exposes chat_composer, chat_attach, '
      'chat_record_voice, then chat_send once text is typed', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.bottomCenter,
            child: ComposeArea(
              onSend: (_) {},
              onAttach: () {},
              onRecordStart: () {},
              onRecordStop: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final composer = nodeWithIdentifier(tester, 'chat_composer');
      expect(composer.flagsCollection.isTextField, isTrue);
      expect(nodeWithIdentifier(tester, 'chat_attach').label, 'Add attachment');
      expect(
        nodeWithIdentifier(tester, 'chat_record_voice').label,
        'Record voice message',
      );
      expect(find.bySemanticsIdentifier('chat_send'), findsNothing);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      expect(nodeWithIdentifier(tester, 'chat_send').label, 'Send message');
      expect(find.bySemanticsIdentifier('chat_record_voice'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('BETA-0924-52 a call row carries call_row_<callId>', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        app(
          CallTimelineRow(
            entry: ConversationCallTimelineEntry(
              callId: 'a2f0a1d6-0000-4000-8000-000000000052',
              contactPeerId: contactPeerId,
              direction: ConversationCallDirection.incoming,
              status: ConversationCallStatus.missed,
              startedAt: DateTime.utc(2026, 9, 24, 23),
              endedAt: DateTime.utc(2026, 9, 24, 23, 0, 20),
            ),
          ),
        ),
      );

      final data = nodeWithIdentifier(
        tester,
        'call_row_a2f0a1d6-0000-4000-8000-000000000052',
      );
      expect(data.label, contains('Missed voice call'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('BETA-0924-53 each message row carries message_<messageId>', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      ConversationMessage message(String id, String timestamp) =>
          ConversationMessage(
            id: id,
            contactPeerId: contactPeerId,
            senderPeerId: ownPeerId,
            text: 'Hello $id',
            timestamp: timestamp,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConversationScreen(
              contactPeerId: contactPeerId,
              contactUsername: 'Alice',
              connectionDate: 'February 9, 2026',
              ownPeerId: ownPeerId,
              messages: [
                message('m1', '2026-09-24T22:59:00.000Z'),
                message('m2', '2026-09-24T23:01:00.000Z'),
              ],
              onSend: (_) {},
              onBack: () {},
              initialLoadDone: true,
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      for (final id in const <String>['m1', 'm2']) {
        nodeWithIdentifier(tester, 'message_$id');
        final textNode = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Hello $id')),
        );
        expect(
          textNode.identifier == 'message_$id' ||
              _hasAncestorWithIdentifier(textNode, 'message_$id'),
          isTrue,
          reason: 'the message content must sit inside its row identifier',
        );
        expect(find.bySemanticsLabel(RegExp('Hello $id')), findsOneWidget);
      }
    } finally {
      semantics.dispose();
    }
  });
}

bool _hasAncestorWithIdentifier(SemanticsNode node, String identifier) {
  for (var parent = node.parent; parent != null; parent = parent.parent) {
    if (parent.identifier == identifier) return true;
  }
  return false;
}
