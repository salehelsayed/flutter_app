import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/conversation/domain/repositories/fake_message_repository.dart';
import '../shared/fakes/fake_notification_service.dart';
import '../shared/fakes/in_memory_inbox_staging_repository.dart';

/// 118 Phase 6 (INTEGRATION): proves the full bridge -> staging -> confirm ->
/// live-direct callback -> real ChatMessageListener -> maybeShowNotification
/// (with the real gate + tone tracker) wiring composes — and that the live
/// notification and the sender ack coexist. Mirrors the main.dart closures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const peerId = 'peer-alice';

  late _FakeBridge bridge;
  late InMemoryInboxStagingRepository stagingRepo;
  late FakeContactRepository contactRepo;
  late FakeMessageRepository messageRepo;
  late FakeNotificationService notificationService;
  late ActiveConversationTracker conversationTracker;
  late RecentRemoteNotificationGate gate;
  late NotificationToneTracker toneTracker;
  late ChatMessageListener listener;
  late DateTime now;
  late int recoveredReplayCount;
  late Directory tempDir;
  late P2PServiceImpl service;

  setUp(() async {
    flowEventLoggingEnabled = false;
    now = DateTime.utc(2026, 6, 13, 12);
    recoveredReplayCount = 0;

    bridge = _FakeBridge();
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );
    bridge.whenCommand(
      'message:confirm',
      (_) => jsonEncode({'ok': true, 'confirmed': true}),
    );
    bridge.whenCommand(
      'node:start',
      (_) => jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      }),
    );
    bridge.whenCommand(
      'inbox:retrieve_pending',
      (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
    );

    stagingRepo = InMemoryInboxStagingRepository();
    contactRepo = FakeContactRepository()
      ..seed([
        const ContactModel(
          peerId: peerId,
          publicKey: 'pk-peer-alice',
          rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-alice',
          username: 'Alice',
          signature: 'sig-peer-alice',
          scannedAt: '2026-06-13T12:00:00.000Z',
        ),
      ]);
    messageRepo = FakeMessageRepository();
    notificationService = FakeNotificationService();
    conversationTracker = ActiveConversationTracker(); // not viewing
    tempDir = await Directory.systemTemp.createTemp('live_direct_notif_int');
    gate = RecentRemoteNotificationGate(filePath: '${tempDir.path}/gate.json');
    toneTracker = NotificationToneTracker(
      clock: () => now,
      window: const Duration(seconds: 30),
    );

    listener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      notificationService: notificationService,
      conversationTracker: conversationTracker,
      notificationToneTracker: toneTracker,
      getAppLifecycleState: () => AppLifecycleState.resumed,
      remoteNotificationGate: gate,
      backgroundNotificationDuplicateGuardDelay: Duration.zero,
    );

    // Mirror main.dart:1664-1681 — three closures over the real listener.
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: stagingRepo,
      replayRecoveredInboxChatMessage: (message, {String? stagedEntryId}) async {
        recoveredReplayCount++;
        final outcome = await listener.processIncomingMessage(
          message,
          suppressNotification: true,
          stagedEntryId: stagedEntryId,
        );
        return mapChatReplayOutcomeToDisposition(outcome);
      },
      replayLiveLanChatMessage: (message, {String? stagedEntryId}) async {
        final outcome = await listener.processIncomingMessage(
          message,
          suppressNotification: false,
          stagedEntryId: stagedEntryId,
        );
        return mapChatReplayOutcomeToDisposition(outcome);
      },
      replayLiveDirectChatMessage: (message, {String? stagedEntryId}) async {
        final outcome = await listener.processIncomingMessage(
          message,
          suppressNotification: false,
          stagedEntryId: stagedEntryId,
        );
        return mapChatReplayOutcomeToDisposition(outcome);
      },
    );
  });

  tearDown(() async {
    service.dispose();
    listener.dispose();
    // The live path writes dedup markers fire-and-forget; let them settle so
    // the temp dir is quiescent before cleanup.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      await gate.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup of an OS temp dir; a late async write is harmless.
    }
  });

  ChatMessage directMessage({
    required String id,
    required String nonce,
    String text = 'Hello',
  }) {
    return ChatMessage(
      from: peerId,
      to: 'self-peer',
      content: jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': id,
          'text': text,
          'senderPeerId': peerId,
          'senderUsername': 'Alice',
          'timestamp': '2026-06-13T12:00:01.000Z',
        },
      }),
      timestamp: '2026-06-13T12:00:01.000Z',
      isIncoming: true,
      transport: 'direct',
      confirmNonce: nonce,
    );
  }

  Future<void> waitFor(
    bool Function() condition, {
    required String reason,
  }) async {
    for (var i = 0; i < 60; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail(reason);
  }

  test(
    'a live direct message notifies once with a tone AND confirms the sender',
    () async {
      bridge.onMessageReceived?.call(
        directMessage(id: 'msg-live-1', nonce: 'nonce-1'),
      );

      await waitFor(
        () => notificationService.shown.isNotEmpty,
        reason: 'live direct message should raise a notification',
      );

      // 1. Exactly one notification, audible (first-in-window).
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.single.silent, isFalse);
      expect(notificationService.shown.single.contactPeerId, peerId);

      // 2. The sender was still confirmed ok:true for the nonce (notify + ack
      //    coexist on the live path).
      final confirms = bridge.payloadsFor('message:confirm');
      expect(confirms, hasLength(1));
      expect(confirms.single, equals({'nonce': 'nonce-1', 'ok': true}));

      // The message was stored and the staged row committed/deleted.
      expect(messageRepo.lastSavedMessage?.id, 'msg-live-1');
      await waitFor(
        () => stagingRepo.entry('direct:nonce-1') == null,
        reason: 'committed live direct entry should be deleted',
      );
      expect(recoveredReplayCount, 0);
    },
  );

  test(
    'a burst from one conversation within the window coalesces to one tone',
    () async {
      bridge.onMessageReceived?.call(
        directMessage(id: 'msg-burst-1', nonce: 'nonce-b1'),
      );
      await waitFor(
        () => notificationService.shown.length == 1,
        reason: 'first burst message should notify',
      );
      expect(notificationService.shown.last.silent, isFalse);

      // Second message in the same conversation, still inside the 30s window.
      now = now.add(const Duration(seconds: 5));
      bridge.onMessageReceived?.call(
        directMessage(id: 'msg-burst-2', nonce: 'nonce-b2'),
      );
      await waitFor(
        () => notificationService.shown.length == 2,
        reason: 'second burst message should still update the notification',
      );
      // Updated silently — at most one tone per conversation per window.
      expect(notificationService.shown.last.silent, isTrue);

      // Both messages were still confirmed to the sender.
      expect(bridge.payloadsFor('message:confirm'), hasLength(2));
    },
  );

  test(
    'a genuine relay-recovered (non-prefixed) sweep entry stays silent',
    () async {
      stagingRepo.seed(
        InboxStagingEntry(
          entryId: 'relay-recovered-1',
          ownerPeerId: 'self-peer',
          senderPeerId: peerId,
          messageType: 'chat_message',
          relayTimestamp: '2026-06-13T12:00:00.000Z',
          envelope: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'msg-recovered-1',
              'text': 'recovered',
              'senderPeerId': peerId,
              'senderUsername': 'Alice',
              'timestamp': '2026-06-13T12:00:00.000Z',
            },
          }),
          stagedAt: '2026-06-13T12:00:01.000Z',
        ),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInbox();
      // Settle any fire-and-forget notification path before asserting absence.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Routed through the SUPPRESSING recovery callback — no notification.
      expect(recoveredReplayCount, 1);
      expect(notificationService.shown, isEmpty);
      expect(messageRepo.lastSavedMessage?.id, 'msg-recovered-1');
    },
  );

  test(
    'a retried-but-live direct: entry swept on resume still notifies '
    '(Phase 1B end-to-end)',
    () async {
      stagingRepo.seed(
        InboxStagingEntry(
          entryId: 'direct:nonce-retry-sweep',
          ownerPeerId: 'self-peer',
          senderPeerId: peerId,
          messageType: 'chat_message',
          relayTimestamp: '2026-06-13T12:00:00.000Z',
          envelope: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'msg-retry-sweep',
              'text': 'retried but live',
              'senderPeerId': peerId,
              'senderUsername': 'Alice',
              'timestamp': '2026-06-13T12:00:00.000Z',
            },
          }),
          stagedAt: '2026-06-13T12:00:01.000Z',
        ),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInbox();

      // Routed through the notify-capable live-direct callback — NOT suppressed.
      // (The notification is fire-and-forget, so wait for it to land.)
      await waitFor(
        () => notificationService.shown.isNotEmpty,
        reason: 'swept direct: entry should still notify (Phase 1B)',
      );
      expect(recoveredReplayCount, 0);
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.single.silent, isFalse);
      expect(stagingRepo.entry('direct:nonce-retry-sweep'), isNull);
    },
  );
}

/// Minimal fake bridge: records commands and returns configured responses.
class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final List<String> calledCommands = [];
  final Map<String, List<Map<String, dynamic>?>> payloadsByCommand = {};
  bool _initialized = false;

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  List<Map<String, dynamic>?> payloadsFor(String cmd) =>
      List.unmodifiable(payloadsByCommand[cmd] ?? const []);

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;

    calledCommands.add(cmd);
    payloadsByCommand.putIfAbsent(cmd, () => []).add(payload);

    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(payload);
    }

    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}
