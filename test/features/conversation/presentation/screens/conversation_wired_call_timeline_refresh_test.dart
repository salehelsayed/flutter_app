import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_call_timeline_source.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/call_timeline_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _contactPeerId = 'call-timeline-contact';

class _ControlledCallTimelineSource implements ConversationCallTimelineSource {
  final initialRead = Completer<List<ConversationCallTimelineEntry>>();
  final _changes = StreamController<void>.broadcast();
  List<ConversationCallTimelineEntry> calls = [];
  int reads = 0;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<ConversationCallTimelineEntry>> listCallsForContact(
    String contactPeerId,
  ) async {
    expect(contactPeerId, _contactPeerId);
    if (reads++ == 0) return initialRead.future;
    return List.of(calls);
  }

  @override
  Future<void> markCallsRead(String contactPeerId) async {}

  void refreshWith(List<ConversationCallTimelineEntry> entries) {
    calls = entries;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

ConversationCallTimelineEntry _call({
  String callId = 'call-1',
  ConversationCallStatus status = ConversationCallStatus.missed,
  Duration? duration,
}) => ConversationCallTimelineEntry(
  callId: callId,
  contactPeerId: _contactPeerId,
  direction: ConversationCallDirection.incoming,
  status: status,
  startedAt: DateTime.utc(2026, 9, 10, 12),
  endedAt: DateTime.utc(2026, 9, 10, 12, 1),
  duration: duration,
);

void main() {
  late _ControlledCallTimelineSource source;
  late ChatMessageListener listener;
  late FakeP2PService p2p;

  setUp(() {
    p2p = FakeP2PService();
  });

  tearDown(() async {
    listener.dispose();
    p2p.dispose();
    await source.dispose();
  });

  // The chat can contain a continuously animated connection indicator.
  Future<void> pumpRefresh(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openChat(WidgetTester tester) async {
    source = _ControlledCallTimelineSource();
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
            scannedAt: '2026-09-10T10:00:00.000Z',
          ),
          identityRepo: identity,
          messageRepo: messages,
          chatMessageListener: listener,
          p2pService: p2p,
          micPermissionGateway: FakeMicPermissionGateway(),
          callTimelineSource: source,
        ),
      ),
    );
    await pumpRefresh(tester);
    expect(source.reads, 1);
  }

  ConversationScreen screen(WidgetTester tester) =>
      tester.widget<ConversationScreen>(find.byType(ConversationScreen));

  testWidgets('delayed empty call history does not rebuild the open chat', (
    tester,
  ) async {
    await openChat(tester);
    final before = screen(tester);

    source.initialRead.complete([]);
    await tester.pump();
    await tester.pump();

    expect(screen(tester), same(before));
    expect(find.byType(CallTimelineRow), findsNothing);
  });

  testWidgets('reloaded equivalent call rows keep the existing chat widget', (
    tester,
  ) async {
    await openChat(tester);
    source.initialRead.complete([_call()]);
    await pumpRefresh(tester);
    final before = screen(tester);
    expect(find.byType(CallTimelineRow), findsOneWidget);

    // Database reads produce new projection objects for the same history.
    final reloaded = _call();
    expect(reloaded, isNot(same(before.callEntries.single)));
    source.refreshWith([reloaded]);
    await tester.pump();
    await tester.pump();

    expect(source.reads, 2);
    expect(screen(tester), same(before));
  });

  testWidgets('changed, added and removed call rows still update live', (
    tester,
  ) async {
    await openChat(tester);
    source.initialRead.complete([_call()]);
    await pumpRefresh(tester);
    expect(find.text('Missed voice call'), findsOneWidget);

    final completed = _call(
      status: ConversationCallStatus.completed,
      duration: const Duration(seconds: 45),
    );
    source.refreshWith([completed]);
    await pumpRefresh(tester);
    expect(screen(tester).callEntries.single, same(completed));
    expect(find.text('Missed voice call'), findsNothing);

    source.refreshWith([completed, _call(callId: 'call-2')]);
    await pumpRefresh(tester);
    expect(find.byType(CallTimelineRow), findsNWidgets(2));

    source.refreshWith([]);
    await pumpRefresh(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(screen(tester).callEntries, isEmpty);
    expect(find.byType(CallTimelineRow), findsNothing);
  });
}
