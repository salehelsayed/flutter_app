import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/call_timeline_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 405: the chat row that renders one terminal call.
///
/// The call-history table, the projector and the timeline source all shipped
/// with VC2-02, but nothing ever drew a row. Copy is direction-aware because
/// the same stored status means different things to each side: a caller who
/// cancels stores `cancelled` locally and the callee stores `missed`, and a
/// `declined` row is "you declined" on the callee and "call declined" on the
/// caller.
void main() {
  ConversationCallTimelineEntry makeEntry({
    ConversationCallDirection direction = ConversationCallDirection.incoming,
    ConversationCallStatus status = ConversationCallStatus.completed,
    Duration? duration,
  }) => ConversationCallTimelineEntry(
    callId: 'a2f0a1d6-0000-4000-8000-000000000001',
    contactPeerId: '12D3KooWTestPeerId1234567890',
    direction: direction,
    status: status,
    startedAt: DateTime.utc(2026, 2, 9, 15, 30),
    endedAt: DateTime.utc(2026, 2, 9, 15, 32, 5),
    duration: duration,
  );

  Future<void> pumpRow(
    WidgetTester tester,
    ConversationCallTimelineEntry entry,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CallTimelineRow(entry: entry)),
      ),
    );
    await tester.pump();
  }

  group('formatCallDuration', () {
    test('TC-405-01 renders under a minute with a leading zero minute', () {
      expect(formatCallDuration(const Duration(seconds: 7)), '0:07');
      expect(formatCallDuration(Duration.zero), '0:00');
    });

    test('TC-405-02 renders minutes and seconds under one hour', () {
      expect(
        formatCallDuration(const Duration(minutes: 2, seconds: 5)),
        '2:05',
      );
      expect(
        formatCallDuration(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
    });

    test('TC-405-03 renders hours with padded minutes and seconds', () {
      expect(
        formatCallDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatCallDuration(const Duration(hours: 10)), '10:00:00');
    });
  });

  group('CallTimelineRow copy', () {
    testWidgets('TC-405-04 an answered call shows its talk duration', (
      tester,
    ) async {
      await pumpRow(
        tester,
        makeEntry(
          status: ConversationCallStatus.completed,
          duration: const Duration(minutes: 2, seconds: 5),
        ),
      );
      expect(find.text('Voice call · 2:05'), findsOneWidget);
    });

    testWidgets('TC-405-05 an answered call with no duration shows no dot', (
      tester,
    ) async {
      await pumpRow(
        tester,
        makeEntry(
          direction: ConversationCallDirection.outgoing,
          status: ConversationCallStatus.completed,
        ),
      );
      expect(find.text('Voice call'), findsOneWidget);
    });

    testWidgets('TC-405-06 a cancelled incoming call reads as missed', (
      tester,
    ) async {
      await pumpRow(
        tester,
        makeEntry(status: ConversationCallStatus.cancelled),
      );
      expect(find.text('Missed voice call'), findsOneWidget);
    });

    testWidgets('TC-405-07 a cancelled outgoing call reads as cancelled', (
      tester,
    ) async {
      await pumpRow(
        tester,
        makeEntry(
          direction: ConversationCallDirection.outgoing,
          status: ConversationCallStatus.cancelled,
        ),
      );
      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('TC-405-08 a missed call is direction aware', (tester) async {
      await pumpRow(tester, makeEntry(status: ConversationCallStatus.missed));
      expect(find.text('Missed voice call'), findsOneWidget);

      await pumpRow(
        tester,
        makeEntry(
          direction: ConversationCallDirection.outgoing,
          status: ConversationCallStatus.missed,
        ),
      );
      expect(find.text('No answer'), findsOneWidget);
    });

    testWidgets('TC-405-09 a declined call names who declined', (tester) async {
      await pumpRow(tester, makeEntry(status: ConversationCallStatus.declined));
      expect(find.text('You declined'), findsOneWidget);

      await pumpRow(
        tester,
        makeEntry(
          direction: ConversationCallDirection.outgoing,
          status: ConversationCallStatus.declined,
        ),
      );
      expect(find.text('Call declined'), findsOneWidget);
    });

    testWidgets('TC-405-10 a busy call is direction aware', (tester) async {
      await pumpRow(tester, makeEntry(status: ConversationCallStatus.busy));
      expect(find.text('Missed voice call'), findsOneWidget);

      await pumpRow(
        tester,
        makeEntry(
          direction: ConversationCallDirection.outgoing,
          status: ConversationCallStatus.busy,
        ),
      );
      expect(find.text('Contact was busy'), findsOneWidget);
    });

    testWidgets('TC-405-11 a failed call reads the same both ways', (
      tester,
    ) async {
      await pumpRow(tester, makeEntry(status: ConversationCallStatus.failed));
      expect(find.text('Call failed'), findsOneWidget);

      await pumpRow(
        tester,
        makeEntry(
          direction: ConversationCallDirection.outgoing,
          status: ConversationCallStatus.failed,
        ),
      );
      expect(find.text('Call failed'), findsOneWidget);
    });

    testWidgets('TC-405-12 a duration never appears on a call that never '
        'connected', (tester) async {
      await pumpRow(
        tester,
        makeEntry(
          status: ConversationCallStatus.missed,
          duration: const Duration(minutes: 2, seconds: 5),
        ),
      );
      expect(find.text('Missed voice call'), findsOneWidget);
      expect(find.textContaining('2:05'), findsNothing);
    });
  });
}
