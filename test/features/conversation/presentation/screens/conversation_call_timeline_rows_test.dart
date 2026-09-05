import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/call_timeline_row.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 405: terminal calls render as chat rows in their chronological place.
///
/// The rows are NOT messages: they are never sent, retried or stored in
/// `messages.wire_envelope`. They only share the timeline.
void main() {
  const contactPeerId = '12D3KooWTestPeerId1234567890';

  ConversationMessage makeMessage({
    required String id,
    required String timestamp,
    bool isIncoming = false,
    String text = 'Hello!',
  }) => ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: isIncoming ? contactPeerId : '12D3KooWMyPeerId1234567890',
    text: text,
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: isIncoming,
    createdAt: timestamp,
  );

  ConversationCallTimelineEntry makeCall({
    String callId = 'a2f0a1d6-0000-4000-8000-000000000001',
    required DateTime startedAt,
    ConversationCallDirection direction = ConversationCallDirection.incoming,
    ConversationCallStatus status = ConversationCallStatus.missed,
    Duration? duration,
  }) => ConversationCallTimelineEntry(
    callId: callId,
    contactPeerId: contactPeerId,
    direction: direction,
    status: status,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(seconds: 20)),
    duration: duration,
  );

  Widget buildTestWidget({
    List<ConversationMessage> messages = const <ConversationMessage>[],
    List<ConversationCallTimelineEntry> callEntries =
        const <ConversationCallTimelineEntry>[],
  }) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ConversationScreen(
        contactPeerId: contactPeerId,
        contactUsername: 'Alice',
        connectionDate: 'February 9, 2026',
        ownPeerId: '12D3KooWMyPeerId1234567890',
        messages: messages,
        callEntries: callEntries,
        onSend: (_) {},
        onBack: () {},
        initialLoadDone: true,
      ),
    ),
  );

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('TC-405-20 no call source leaves the chat exactly as it was', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          makeMessage(id: 'm1', timestamp: '2026-02-09T15:29:00.000Z'),
        ],
      ),
    );
    await pumpFrames(tester);

    expect(find.byType(LetterCard), findsOneWidget);
    expect(find.byType(CallTimelineRow), findsNothing);
  });

  testWidgets('TC-405-21 a call renders between the messages it happened '
      'between', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          makeMessage(id: 'm1', timestamp: '2026-02-09T15:29:00.000Z'),
          makeMessage(id: 'm2', timestamp: '2026-02-09T15:31:00.000Z'),
        ],
        callEntries: [makeCall(startedAt: DateTime.utc(2026, 2, 9, 15, 30))],
      ),
    );
    await pumpFrames(tester);

    expect(find.byType(CallTimelineRow), findsOneWidget);

    // The list is reversed, so visual top-to-bottom is chronological.
    final firstMessage = tester.getTopLeft(
      find.byKey(const ValueKey('msg-m1')),
    );
    final call = tester.getTopLeft(find.byType(CallTimelineRow));
    final secondMessage = tester.getTopLeft(
      find.byKey(const ValueKey('msg-m2')),
    );

    expect(firstMessage.dy, lessThan(call.dy));
    expect(call.dy, lessThan(secondMessage.dy));
  });

  testWidgets('TC-405-22 a call on its own day gets a date separator', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          makeMessage(id: 'm1', timestamp: '2026-02-07T15:29:00.000Z'),
        ],
        callEntries: [makeCall(startedAt: DateTime.utc(2026, 2, 9, 15, 30))],
      ),
    );
    await pumpFrames(tester);

    expect(find.byType(CallTimelineRow), findsOneWidget);
    // One separator for the message's day, one for the call's day.
    expect(find.byType(DateSeparator), findsNWidgets(2));
  });

  testWidgets('TC-405-23 a call breaks the message run around it', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          makeMessage(id: 'm1', timestamp: '2026-02-09T15:29:00.000Z'),
          makeMessage(id: 'm2', timestamp: '2026-02-09T15:29:30.000Z'),
        ],
        callEntries: [
          makeCall(startedAt: DateTime.utc(2026, 2, 9, 15, 29, 15)),
        ],
      ),
    );
    await pumpFrames(tester);

    final second = tester.widget<LetterCard>(
      find.descendant(
        of: find.byKey(const ValueKey('msg-m2')),
        matching: find.byType(LetterCard),
      ),
    );
    expect(
      second.isFirstInGroup,
      isTrue,
      reason: 'a call row between two same-sender messages ends the run',
    );
  });

  testWidgets('TC-405-24 a conversation holding only calls is not empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        callEntries: [
          makeCall(
            startedAt: DateTime.utc(2026, 2, 9, 15, 30),
            status: ConversationCallStatus.completed,
            direction: ConversationCallDirection.outgoing,
            duration: const Duration(minutes: 2, seconds: 5),
          ),
        ],
      ),
    );
    await pumpFrames(tester);

    expect(find.byType(EmptyConversationState), findsNothing);
    expect(find.text('Voice call · 2:05'), findsOneWidget);
  });

  testWidgets('TC-405-25 a new call list rebuilds the memoized display items', (
    tester,
  ) async {
    final messages = [
      makeMessage(id: 'm1', timestamp: '2026-02-09T15:29:00.000Z'),
    ];
    await tester.pumpWidget(buildTestWidget(messages: messages));
    await pumpFrames(tester);
    expect(find.byType(CallTimelineRow), findsNothing);

    await tester.pumpWidget(
      buildTestWidget(
        messages: messages,
        callEntries: [makeCall(startedAt: DateTime.utc(2026, 2, 9, 15, 30))],
      ),
    );
    await pumpFrames(tester);

    expect(
      find.byType(CallTimelineRow),
      findsOneWidget,
      reason: 'the display-item memo must treat the call list as an input',
    );
  });

  testWidgets('TC-405-26 a call for another contact never renders', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestWidget(
        messages: [
          makeMessage(id: 'm1', timestamp: '2026-02-09T15:29:00.000Z'),
        ],
        callEntries: [
          ConversationCallTimelineEntry(
            callId: 'a2f0a1d6-0000-4000-8000-000000000009',
            contactPeerId: '12D3KooWSomeoneElse0987654321',
            direction: ConversationCallDirection.incoming,
            status: ConversationCallStatus.missed,
            startedAt: DateTime.utc(2026, 2, 9, 15, 30),
            endedAt: DateTime.utc(2026, 2, 9, 15, 30, 20),
          ),
        ],
      ),
    );
    await pumpFrames(tester);

    expect(find.byType(CallTimelineRow), findsNothing);
  });
}
