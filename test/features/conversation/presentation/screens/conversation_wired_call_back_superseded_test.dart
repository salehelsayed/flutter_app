import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/call/application/call_history_access.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_call_timeline_source.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// A chat "Call back" on an incoming call the user did not take follows the
/// Calls page rule: only the contact's newest call may start a fresh call, and
/// without durable history the row refuses.
const _contactPeerId = 'call-back-contact';
final _older = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
final _newer = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
const _superseded =
    'A newer call with this contact exists. Call back from the latest one.';

/// One terminal call as both its durable history row and its chat projection.
({CallHistoryEntry history, ConversationCallTimelineEntry row}) _call(
  CallId id,
  DateTime startedAt, {
  bool incomingMissed = true,
}) {
  final endedAt = startedAt.add(const Duration(seconds: 30));
  return (
    history: CallHistoryEntry(
      callId: id,
      contactAccountPeerId: _contactPeerId,
      direction: incomingMissed
          ? CallDirection.incoming
          : CallDirection.outgoing,
      terminalReason: incomingMissed
          ? CallEndReason.noAnswer
          : CallEndReason.localHangup,
      status: incomingMissed
          ? CallHistoryStatus.missed
          : CallHistoryStatus.completed,
      startedAt: startedAt,
      connectedAt: incomingMissed ? null : startedAt,
      endedAt: endedAt,
      transportRoute: null,
      createdAt: startedAt,
      updatedAt: startedAt,
    ),
    row: ConversationCallTimelineEntry(
      callId: id.value,
      contactPeerId: _contactPeerId,
      direction: incomingMissed
          ? ConversationCallDirection.incoming
          : ConversationCallDirection.outgoing,
      status: incomingMissed
          ? ConversationCallStatus.missed
          : ConversationCallStatus.completed,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: incomingMissed ? null : const Duration(seconds: 30),
    ),
  );
}

class _TimelineSource implements ConversationCallTimelineSource {
  _TimelineSource(this.rows);

  final List<ConversationCallTimelineEntry> rows;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<ConversationCallTimelineEntry>> listCallsForContact(
    String contactPeerId,
  ) async => rows;

  @override
  Future<void> markCallsRead(String contactPeerId) async {}

  Future<void> dispose() => _changes.close();
}

/// The production source also serves the durable history the guard reads.
class _HistoryTimelineSource extends _TimelineSource
    implements CallHistoryAccess {
  _HistoryTimelineSource(super.rows, this.recent);

  /// Newest first, as the repository returns it.
  final List<CallHistoryEntry> recent;

  @override
  Future<CallHistoryEntry?> findCall(CallId id) async =>
      recent.where((e) => e.callId == id).firstOrNull;

  @override
  Future<List<CallHistoryEntry>> recentCallsForContact(String peerId) async => [
    for (final e in recent)
      if (e.contactAccountPeerId == peerId) e,
  ];
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
  late _TimelineSource source;
  late _Capability capability;
  late ChatMessageListener listener;
  late FakeP2PService p2p;

  final t0 = DateTime.utc(2026, 10, 13, 12);
  final older = _call(_older, t0);
  final newer = _call(_newer, t0.add(const Duration(hours: 1)));

  setUp(() {
    p2p = FakeP2PService();
    capability = _Capability();
  });

  tearDown(() async {
    listener.dispose();
    p2p.dispose();
    await source.dispose();
  });

  // The chat can contain a continuously animated connection indicator.
  Future<void> pumpChat(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openChat(WidgetTester tester, _TimelineSource timeline) async {
    source = timeline;
    final messages = InMemoryMessageRepository();
    listener = ChatMessageListener(
      chatMessageStream: const Stream.empty(),
      messageRepo: messages,
      contactRepo: FakeContactRepository(),
    );
    final identity = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationWired(
          contact: ContactModel(
            peerId: _contactPeerId,
            publicKey: 'pub',
            rendezvous: '/dns4/relay/tcp/443/p2p/relay',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-10-13T10:00:00.000Z',
          ),
          identityRepo: identity,
          messageRepo: messages,
          chatMessageListener: listener,
          p2pService: p2p,
          micPermissionGateway: FakeMicPermissionGateway(),
          callTimelineSource: source,
          outgoingCallCapability: capability,
        ),
      ),
    );
    await pumpChat(tester);
  }

  Finder callBack(CallId id) => find.descendant(
    of: find.byKey(ValueKey('call-${id.value}')),
    matching: find.byTooltip('Call back'),
  );

  Future<void> tapCallBack(WidgetTester tester, CallId id) async {
    await tester.tap(callBack(id));
    await pumpChat(tester);
  }

  testWidgets(
    'older incoming missed chat row refuses and points at the newer call',
    (tester) async {
      await openChat(
        tester,
        _HistoryTimelineSource(
          [older.row, newer.row],
          [newer.history, older.history],
        ),
      );
      await tapCallBack(tester, _older);
      expect(capability.starts, isEmpty);
      expect(find.text(_superseded), findsOneWidget);
    },
  );

  testWidgets('newest incoming missed chat row starts a fresh call', (
    tester,
  ) async {
    await openChat(
      tester,
      _HistoryTimelineSource(
        [older.row, newer.row],
        [newer.history, older.history],
      ),
    );
    await tapCallBack(tester, _newer);
    expect(capability.starts, [_contactPeerId]);
    expect(find.text(_superseded), findsNothing);
  });

  testWidgets('older outgoing chat row still calls', (tester) async {
    final outgoing = _call(_older, t0, incomingMissed: false);
    await openChat(
      tester,
      _HistoryTimelineSource(
        [outgoing.row, newer.row],
        [newer.history, outgoing.history],
      ),
    );
    await tapCallBack(tester, _older);
    expect(capability.starts, [_contactPeerId]);
    expect(find.text(_superseded), findsNothing);
  });

  testWidgets(
    'incoming missed chat row refuses when no history can prove it is newest',
    (tester) async {
      await openChat(tester, _TimelineSource([newer.row]));
      await tapCallBack(tester, _newer);
      expect(capability.starts, isEmpty);
      expect(find.text(_superseded), findsOneWidget);
    },
  );
}
