import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../core/local_discovery/fake_local_p2p_service.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import 'fake_notification_service.dart';
import 'in_memory_inbox_staging_repository.dart';
import 'recording_fake_bridge.dart';

/// 1:1 sibling of `GroupTestUser` (plan 120 Phase G3): encapsulates the full
/// per-user direct-message receiver stack for a 2-party, transport-and-lifecycle
/// aware live-direct-notification simulation.
///
/// Each user owns a [RecordingFakeBridge], a real [ChatMessageListener], a real
/// [P2PServiceImpl] wired with the THREE main.dart-mirroring replay closures
/// (recovery=suppress, live-lan/live-direct=notify), a [FakeNotificationService],
/// a [FakeContactRepository]/[FakeMessageRepository], a [FakeLocalP2PService]
/// (so the durable-LAN commit handler is installed), a shared (per-sim)
/// [RecentRemoteNotificationGate], a real clock-injected [NotificationToneTracker],
/// a mutable lifecycle (`getAppLifecycleState: () => _lifecycle`), and a settable
/// [conversationTracker].
///
/// HEADER NOTE (plan 120 Risk "Simulation drift from main.dart"): this harness
/// MIRRORS the main.dart replay closures rather than booting `main()`, so it
/// CANNOT catch a `main.dart` wiring regression — that is Phase G1's job
/// (`main_replay_disposition_wiring_test.dart`). G1 + G3 are complementary.
class OneToOneTestUser {
  final String peerId;
  final String username;
  final RecordingFakeBridge bridge;
  final FakeLocalP2PService localP2P;
  final InMemoryInboxStagingRepository stagingRepo;
  final FakeContactRepository contactRepo;
  final FakeMessageRepository messageRepo;
  final FakeNotificationService notificationService;
  final NotificationToneTracker toneTracker;
  final RecentRemoteNotificationGate gate;

  /// Mutable so a test can flip the receiver's lifecycle between deliveries
  /// (`resumed`/`paused`/etc.); read live via `getAppLifecycleState`.
  AppLifecycleState lifecycle;

  /// Settable so a test can mark the user as viewing a peer's conversation
  /// (drives the `viewing_conversation` suppression branch).
  ActiveConversationTracker conversationTracker;

  late final ChatMessageListener listener;
  late final P2PServiceImpl service;

  /// Count of routes through the SUPPRESSING recovery callback — a regression
  /// that re-routes a live message through recovery shows up as this going > 0.
  int recoveredReplayCount = 0;

  /// Transports of the messages handed to the notify-capable live callbacks
  /// (mirrors the `expect(message.transport, 'direct')` spy at
  /// `p2p_service_impl_test.dart:1107`). The live path strips `confirmNonce`
  /// but preserves `transport`, so this is the path-pinned proof.
  final List<String?> liveDirectTransports = [];
  final List<String?> liveLanTransports = [];

  OneToOneTestUser._({
    required this.peerId,
    required this.username,
    required this.bridge,
    required this.localP2P,
    required this.stagingRepo,
    required this.contactRepo,
    required this.messageRepo,
    required this.notificationService,
    required this.toneTracker,
    required this.gate,
    required this.lifecycle,
    required this.conversationTracker,
  });

  /// Builds a fully-wired receiver. [gate] is the shared per-sim unique-temp
  /// gate (passed explicitly into the listener via `remoteNotificationGate:` for
  /// determinism, even though `flutter_test_config.dart` also isolates the
  /// module globals). [clock] feeds the tone tracker so a burst stays in-window.
  factory OneToOneTestUser.create({
    required String peerId,
    required String username,
    required RecentRemoteNotificationGate gate,
    required DateTime Function() clock,
    AppLifecycleState lifecycle = AppLifecycleState.resumed,
    Duration toneWindow = const Duration(seconds: 30),
  }) {
    final bridge = RecordingFakeBridge();
    bridge.whenCommand(
      'message:confirm',
      (_) => jsonEncode({'ok': true, 'confirmed': true}),
    );
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );

    final user = OneToOneTestUser._(
      peerId: peerId,
      username: username,
      bridge: bridge,
      localP2P: FakeLocalP2PService(),
      stagingRepo: InMemoryInboxStagingRepository(),
      contactRepo: FakeContactRepository(),
      messageRepo: FakeMessageRepository(),
      notificationService: FakeNotificationService(),
      toneTracker: NotificationToneTracker(clock: clock, window: toneWindow),
      gate: gate,
      lifecycle: lifecycle,
      conversationTracker: ActiveConversationTracker(),
    );

    user.listener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: user.messageRepo,
      contactRepo: user.contactRepo,
      notificationService: user.notificationService,
      conversationTracker: user.conversationTracker,
      notificationToneTracker: user.toneTracker,
      getAppLifecycleState: () => user.lifecycle,
      remoteNotificationGate: gate,
      backgroundNotificationDuplicateGuardDelay: Duration.zero,
    );

    // Mirror main.dart's three replay closures over the real listener:
    // recovery SUPPRESSES, live-lan and live-direct NOTIFY. Routed through the
    // real listener.processIncomingMessage + mapChatReplayOutcomeToDisposition.
    user.service = P2PServiceImpl(
      bridge: bridge,
      localP2PService: user.localP2P,
      inboxStagingRepository: user.stagingRepo,
      replayRecoveredInboxChatMessage: (message, {String? stagedEntryId}) async {
        user.recoveredReplayCount++;
        final outcome = await user.listener.processIncomingMessage(
          message,
          suppressNotification: true,
          stagedEntryId: stagedEntryId,
        );
        return mapChatReplayOutcomeToDisposition(outcome);
      },
      replayLiveLanChatMessage: (message, {String? stagedEntryId}) async {
        user.liveLanTransports.add(message.transport);
        final outcome = await user.listener.processIncomingMessage(
          message,
          suppressNotification: false,
          stagedEntryId: stagedEntryId,
        );
        return mapChatReplayOutcomeToDisposition(outcome);
      },
      replayLiveDirectChatMessage: (message, {String? stagedEntryId}) async {
        user.liveDirectTransports.add(message.transport);
        final outcome = await user.listener.processIncomingMessage(
          message,
          suppressNotification: false,
          stagedEntryId: stagedEntryId,
        );
        return mapChatReplayOutcomeToDisposition(outcome);
      },
    );

    return user;
  }

  /// Registers [other] as a known contact so the listener resolves a username
  /// and does not reject the sender as unknown.
  void knowsContact(OneToOneTestUser other) {
    contactRepo.seed([
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous:
            '/dns4/rendezvous.example.com/tcp/4001/p2p/${other.peerId}',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: '2026-06-13T12:00:00.000Z',
      ),
    ]);
  }

  void dispose() {
    service.dispose();
    listener.dispose();
    localP2P.dispose();
  }
}

/// Routes a live 1:1 message from one [OneToOneTestUser] to another over a
/// chosen transport, exercising the real receiver pipeline (staging -> confirm
/// -> live-direct/-lan callback -> real listener -> maybeShowNotification).
///
/// Transport set is intentionally minimal (`direct`/`relay`/`wifi`); chaos /
/// reorder is out of scope (that is `ChaosP2PNetwork`'s domain).
class DirectMessageRouter {
  static int _nonceSeq = 0;

  /// Delivers [text] from [from] to [to]. For `transport in {direct, relay}`
  /// this mints a `confirmNonce` + v1 `chat_message` envelope and calls
  /// `to.bridge.onMessageReceived(ChatMessage(... transport, confirmNonce))`
  /// (the deferred-direct-ack staging path). For `transport == wifi` it drives
  /// the receiver's durable-LAN commit handler with a [LocalChatMessage]
  /// carrying a LAN ack nonce, which stages `lan:<nonce>` and routes through
  /// `replayLiveLanChatMessage`.
  ///
  /// Returns the (`id`, `nonce`) pair: `id` is the envelope-payload message id
  /// (for the live-wins dedup marker assertion) and `nonce` is the minted
  /// confirm/LAN-ack nonce (the staged entry id is `direct:<nonce>` / `lan:<nonce>`
  /// and the `message:confirm` payload carries it).
  static Future<({String id, String nonce})> deliver(
    OneToOneTestUser from,
    OneToOneTestUser to,
    String text, {
    required String transport,
    String? messageId,
    String timestamp = '2026-06-13T12:00:01.000Z',
  }) async {
    final nonce = 'nonce-${_nonceSeq++}';
    final id = messageId ?? 'msg-${from.peerId}-$nonce';
    final content = jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': id,
        'text': text,
        'senderPeerId': from.peerId,
        'senderUsername': from.username,
        'timestamp': timestamp,
      },
    });

    if (transport == 'wifi') {
      final localMsg = LocalChatMessage(
        from: from.peerId,
        to: to.peerId,
        content: content,
        timestamp: DateTime.parse(timestamp),
        isIncoming: true,
      );
      final handler = to.localP2P.inboundChatCommitHandler;
      if (handler == null) {
        throw StateError(
          'LAN commit handler was not installed on the receiver',
        );
      }
      await handler(localMsg, nonce: nonce);
      return (id: id, nonce: nonce);
    }

    if (transport != 'direct' && transport != 'relay') {
      throw ArgumentError.value(
        transport,
        'transport',
        'expected one of: direct, relay, wifi',
      );
    }

    final onMessageReceived = to.bridge.onMessageReceived;
    if (onMessageReceived == null) {
      throw StateError('bridge.onMessageReceived was not installed');
    }
    onMessageReceived(
      ChatMessage(
        from: from.peerId,
        to: to.peerId,
        content: content,
        timestamp: timestamp,
        isIncoming: true,
        transport: transport,
        confirmNonce: nonce,
      ),
    );
    return (id: id, nonce: nonce);
  }
}
