import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/presentation/screens/calls_page.dart';

final _id = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
final _other = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
CallHistoryListRow row(CallId id, String? name) => CallHistoryListRow(
  CallHistoryEntry(
    callId: id,
    contactAccountPeerId: 'synthetic-contact',
    direction: CallDirection.incoming,
    terminalReason: CallEndReason.noAnswer,
    status: CallHistoryStatus.missed,
    startedAt: DateTime.utc(2026, 10, 13),
    connectedAt: null,
    endedAt: DateTime.utc(2026, 10, 13, 0, 0, 30),
    transportRoute: null,
    createdAt: DateTime.utc(2026, 10, 13),
    updatedAt: DateTime.utc(2026, 10, 13),
  ),
  name,
);

class _Browser implements CallHistoryBrowser {
  final requests =
      <({bool missed, String search, CallHistoryCursor? cursor})>[];
  CallHistoryPage page = CallHistoryPage(
    rows: [row(_id, 'Alice')],
    total: 42,
    missed: 3,
  );
  Future<CallHistoryPage>? pending;
  bool fail = false;
  @override
  Future<CallHistoryPage> browse({
    bool missedOnly = false,
    String search = '',
    CallHistoryCursor? cursor,
    int pageSize = 50,
  }) async {
    requests.add((missed: missedOnly, search: search, cursor: cursor));
    if (fail) throw StateError('synthetic failure');
    final future = pending;
    pending = null;
    return future ?? page;
  }
}

class _Capability implements OutgoingCallCapability {
  final starts = <String>[];
  @override
  bool get isOutgoingCallAvailable => true;
  @override
  Stream<bool> get outgoingCallAvailabilityChanges => const Stream.empty();
  @override
  Future<bool> isOutgoingCallAvailableFor(String id) async => true;
  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String id, {
    OutgoingCallStartRequest? request,
  }) async {
    starts.add(id);
    return OutgoingCallStartResult.started;
  }
}

void main() {
  late _Browser browser;
  late StreamController<void> changes;
  late _Capability owner;
  bool allowed = true;
  setUp(() {
    browser = _Browser();
    changes = StreamController.broadcast(sync: true);
    owner = _Capability();
    allowed = true;
  });
  tearDown(() async {
    await changes.close();
  });
  Widget app() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: CallsPage(
      browser: browser,
      changes: changes.stream,
      redial: CallRedialController(
        capability: () => owner,
        contactAllowed: (_) async => allowed,
      ),
    ),
  );
  testWidgets(
    'All/Missed counts come from history, filters and local search requery, redial uses current preflight',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('All (42)'), findsOneWidget);
      expect(find.text('Missed (3)'), findsOneWidget);
      await tester.tap(find.text('Missed (3)'));
      await tester.pumpAndSettle();
      expect(browser.requests.last.missed, isTrue);
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(browser.requests.last.search, 'Renamed');
      await tester.tap(find.byTooltip('Call back'));
      await tester.pumpAndSettle();
      expect(owner.starts, ['synthetic-contact']);
      allowed = false;
      await tester.tap(find.byTooltip('Call back'));
      await tester.pumpAndSettle();
      expect(owner.starts, hasLength(1));
    },
  );
  testWidgets(
    'paging renders each call once; refresh reflects rename/removal without clearing unread elsewhere',
    (tester) async {
      browser.page = CallHistoryPage(
        rows: [row(_id, 'Alice')],
        total: 2,
        missed: 2,
        next: CallHistoryCursor(DateTime.utc(2026, 10, 13), _id),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      browser.page = CallHistoryPage(
        rows: [row(_id, 'Alice'), row(_other, null)],
        total: 2,
        missed: 2,
      );
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(browser.requests.last.cursor?.callId, _id);
      expect(find.byKey(ValueKey('history-${_id.value}')), findsOneWidget);
      expect(find.byKey(ValueKey('history-${_other.value}')), findsOneWidget);
      expect(find.text('Unknown contact'), findsOneWidget);
      browser.page = CallHistoryPage(
        rows: [row(_id, 'Renamed')],
        total: 1,
        missed: 1,
      );
      changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Renamed'), findsOneWidget);
    },
  );
  testWidgets(
    'empty, failure, explicit refresh and stale query completion remain truthful',
    (tester) async {
      browser.fail = true;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Calls could not be loaded'), findsOneWidget);
      browser.fail = false;
      browser.page = const CallHistoryPage(rows: [], total: 0, missed: 0);
      await tester.tap(find.byTooltip('Refresh calls'));
      await tester.pumpAndSettle();
      expect(find.text('No calls found'), findsOneWidget);
      final stale = Completer<CallHistoryPage>();
      browser.pending = stale.future;
      await tester.tap(find.byTooltip('Refresh calls'));
      await tester.pump();
      browser.page = CallHistoryPage(
        rows: [row(_other, 'Current')],
        total: 1,
        missed: 1,
      );
      await tester.enterText(find.byType(TextField), 'Current');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      stale.complete(
        CallHistoryPage(rows: [row(_id, 'Stale')], total: 1, missed: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stale'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('history-${_other.value}')),
          matching: find.text('Current'),
        ),
        findsOneWidget,
      );
    },
  );
}
