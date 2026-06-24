import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/utils/message_window_cap.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';

class _FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  _FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class _CountingMessageRepository extends InMemoryMessageRepository {
  int markConversationAsReadCalls = 0;

  @override
  Future<int> markConversationAsRead(String contactPeerId) {
    markConversationAsReadCalls++;
    return super.markConversationAsRead(contactPeerId);
  }
}

class _FakeChatListener extends ChatMessageListener {
  final _incoming = StreamController<ConversationMessage>.broadcast();

  _FakeChatListener({required super.messageRepo, required super.contactRepo})
    : super(chatMessageStream: const Stream<ChatMessage>.empty());

  @override
  Stream<ConversationMessage> get incomingMessageStream => _incoming.stream;

  void emitIncoming(ConversationMessage message) => _incoming.add(message);

  @override
  void dispose() {
    _incoming.close();
    super.dispose();
  }
}

const _contactPeerId = '12D3KooWContactPeer123';

ContactModel _makeContact() => ContactModel(
  peerId: _contactPeerId,
  publicKey: 'pub',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig',
  scannedAt: '2026-02-11T10:00:00.000Z',
);

IdentityModel _makeIdentity() => IdentityModel(
  peerId: '12D3KooWMyPeer123',
  publicKey: 'pub',
  privateKey: 'priv',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  username: 'Me',
  createdAt: '2026-02-11T09:00:00.000Z',
  updatedAt: '2026-02-11T09:00:00.000Z',
);

ConversationMessage _incomingMsg({
  required String id,
  required String text,
  required String ts,
}) => ConversationMessage(
  id: id,
  contactPeerId: _contactPeerId,
  senderPeerId: _contactPeerId,
  text: text,
  timestamp: ts,
  status: 'delivered',
  isIncoming: true,
  createdAt: ts,
);

void main() {
  late _CountingMessageRepository messageRepo;
  late InMemoryContactRepository contactRepo;
  late _FakeChatListener chatListener;
  late FakeP2PService p2pService;
  late _FakeIdentityRepository identityRepo;

  setUp(() {
    ConversationWired.debugSortInvocationCount = 0;
    messageRepo = _CountingMessageRepository();
    contactRepo = InMemoryContactRepository();
    chatListener = _FakeChatListener(
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );
    p2pService = FakeP2PService();
    identityRepo = _FakeIdentityRepository(_makeIdentity());
  });

  Widget buildWidget() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ConversationWired(
      contact: _makeContact(),
      identityRepo: identityRepo,
      messageRepo: messageRepo,
      chatMessageListener: chatListener,
      p2pService: p2pService,
      micPermissionGateway: FakeMicPermissionGateway(),
    ),
  );

  Future<void> pumpFrames(WidgetTester tester, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // TC-159-06 — a burst of M messageChanges events applies ONE batched
  // upsert/sort, and all M messages (including the trailing one) render.
  testWidgets(
    'TC-159-06 1:1 M-event messageChanges burst → ONE batched sort, all incl trailing',
    (tester) async {
      await messageRepo.saveMessage(
        _incomingMsg(id: 'seed', text: 'Seed', ts: '2026-05-04T14:00:00.000Z'),
      );
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);
      expect(find.text('Seed'), findsOneWidget);

      const burst = 20;
      ConversationWired.debugSortInvocationCount = 0;
      for (var i = 0; i < burst; i++) {
        // saveMessage emits on messageChanges (the durable belt-and-suspenders
        // stream 131 widened to accept incoming inserts).
        await messageRepo.saveMessage(
          _incomingMsg(
            id: 'burst-$i',
            text: 'burst-$i',
            ts: '2026-05-04T14:${(10 + i).toString().padLeft(2, '0')}:00.000Z',
          ),
        );
      }
      await pumpFrames(tester, count: 30);

      expect(
        ConversationWired.debugSortInvocationCount,
        1,
        reason: 'M synchronous per-event sorts must collapse into ONE batch',
      );
      // All M ids applied (data-level: the lazy reverse ListView only BUILDS the
      // newest few, so assert the model carries every id — no dropped event).
      final ids = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .messages
          .map((m) => m.id)
          .toSet();
      for (var i = 0; i < burst; i++) {
        expect(ids.contains('burst-$i'), isTrue, reason: 'burst-$i applied');
      }
      // Trailing-edge flush: the last (newest, on-screen) event surfaced (131).
      expect(find.text('burst-${burst - 1}'), findsOneWidget);
    },
  );

  // TC-159-06b — cross-sub union: an id delivered ONLY on the live stream and an
  // id delivered ONLY on the repo-change stream BOTH survive the coalescer.
  testWidgets(
    'TC-159-06b cross-sub union — live-only id and repo-only id both render',
    (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      // id-A: live stream ONLY (no saveMessage → no messageChanges emit).
      chatListener.emitIncoming(
        _incomingMsg(id: 'id-A', text: 'A', ts: '2026-05-04T14:05:00.000Z'),
      );
      // id-B: repo-change stream ONLY (saveMessage emits messageChanges).
      await messageRepo.saveMessage(
        _incomingMsg(id: 'id-B', text: 'B', ts: '2026-05-04T14:06:00.000Z'),
      );
      await pumpFrames(tester, count: 30);

      final visible = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .messages
          .map((m) => m.id)
          .toSet();
      expect(visible.contains('id-A'), isTrue, reason: 'live-only id survived');
      expect(visible.contains('id-B'), isTrue, reason: 'repo-only id survived');
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    },
  );

  // TC-159-06c — a coalesced live-stream burst runs the per-event side effects
  // (markAsRead) ONCE per flush against the post-batch state, not per event, and
  // the trailing live-edge message surfaces.
  testWidgets(
    'TC-159-06c coalesced 1:1 burst marks read once-per-flush + surfaces live edge',
    (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      final readBefore = messageRepo.markConversationAsReadCalls;

      const burst = 6;
      for (var i = 0; i < burst; i++) {
        chatListener.emitIncoming(
          _incomingMsg(
            id: 'live-$i',
            text: 'live-$i',
            ts: '2026-05-04T15:${(10 + i).toString().padLeft(2, '0')}:00.000Z',
          ),
        );
      }
      await pumpFrames(tester, count: 30);

      // All M applied (data-level), incl. the trailing/newest live edge.
      final ids = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .messages
          .map((m) => m.id)
          .toSet();
      for (var i = 0; i < burst; i++) {
        expect(ids.contains('live-$i'), isTrue, reason: 'live-$i applied');
      }
      // The trailing (newest, on-screen) live-edge message rendered.
      expect(find.text('live-${burst - 1}'), findsOneWidget);
      // markAsRead fired ONCE for the whole batch — not dropped, not N times.
      expect(
        messageRepo.markConversationAsReadCalls - readBefore,
        1,
        reason: 'markAsRead must run once-per-flush, not once-per-queued-event',
      );
    },
  );

  // TC-159-09 (wired) — the live-append path caps the in-memory window to kMax
  // newest-first, evicting the oldest and flagging more older history.
  testWidgets(
    'TC-159-09 wired live-append caps to kMax newest-first + flags older history',
    (tester) async {
      await tester.pumpWidget(buildWidget());
      await pumpFrames(tester);

      const over = kMaxInMemoryMessages + 5;
      for (var i = 0; i < over; i++) {
        chatListener.emitIncoming(
          _incomingMsg(
            id: 'm-${i.toString().padLeft(4, '0')}',
            text: 'm-$i',
            ts: DateTime.utc(2026, 1, 1)
                .add(Duration(minutes: i))
                .toIso8601String(),
          ),
        );
      }
      await pumpFrames(tester, count: 30);

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      expect(
        screen.messages.length,
        kMaxInMemoryMessages,
        reason: 'live-append window is capped newest-first',
      );
      final ids = screen.messages.map((m) => m.id).toSet();
      // Newest (live edge) retained, oldest evicted.
      expect(ids.contains('m-${(over - 1).toString().padLeft(4, '0')}'), isTrue);
      expect(ids.contains('m-0000'), isFalse);
      // An eviction flags more older history as re-fetchable (1:1 self-heal).
      expect(screen.hasMoreOlderMessages, isTrue);
    },
  );
}
