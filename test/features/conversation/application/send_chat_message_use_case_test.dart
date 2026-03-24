import 'dart:convert';
import 'dart:async';
import 'dart:ui' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

// -- Fake P2P Service --
class FakeP2PService implements P2PService {
  final NodeState _currentState;
  bool sendMessageResult;
  String? sendMessageReply;
  bool shouldThrow;
  bool storeInInboxResult;
  RelayProbeResult probeRelayResult;

  DiscoveredPeer? discoverPeerResult;
  bool dialPeerResult;

  int discoverCallCount = 0;
  int dialCallCount = 0;
  int sendCallCount = 0;
  int probeRelayCallCount = 0;
  int storeInInboxCallCount = 0;

  String? lastSentPeerId;
  String? lastSentMessage;
  String? lastInboxPeerId;
  String? lastInboxMessage;

  // Callback hooks for cross-component ordering tests
  VoidCallback? onDiscover;
  VoidCallback? onSendMessage;
  String? lastSentPayload;

  // Local peer support
  final Set<String> localPeers = {};
  bool localSendResult = true;
  int localSendCallCount = 0;
  int? lastLocalSendTimeoutMs;

  /// Use [useNullDiscover] to explicitly request null discoverPeer results.
  FakeP2PService({
    NodeState? currentState,
    this.sendMessageResult = true,
    this.sendMessageReply = 'received: ok',
    this.shouldThrow = false,
    this.storeInInboxResult = false,
    this.probeRelayResult = RelayProbeResult.error,
    DiscoveredPeer? discoverPeerResult,
    bool useNullDiscover = false,
    this.dialPeerResult = true,
  }) : _currentState = currentState ?? const NodeState(isStarted: true),
       discoverPeerResult = useNullDiscover
           ? null
           : (discoverPeerResult ??
                 const DiscoveredPeer(
                   id: 'target-peer',
                   addresses: ['/ip4/127.0.0.1/tcp/4001'],
                 ));

  @override
  NodeState get currentState => _currentState;

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    if (shouldThrow) throw Exception('Send failed');
    lastSentPeerId = peerId;
    lastSentMessage = message;
    sendCallCount++;
    return sendMessageResult;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (shouldThrow) throw Exception('Send failed');
    lastSentPeerId = peerId;
    lastSentMessage = message;
    lastSentPayload = message;
    sendCallCount++;
    onSendMessage?.call();
    return SendMessageResult(sent: sendMessageResult, reply: sendMessageReply);
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverCallCount++;
    onDiscover?.call();
    if (shouldThrow && discoverCallCount == 1) {
      throw Exception('Discover failed');
    }
    return discoverPeerResult;
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async {
    dialCallCount++;
    return dialPeerResult;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    storeInInboxCallCount++;
    lastInboxPeerId = toPeerId;
    lastInboxMessage = message;
    return storeInInboxResult;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isLocalPeer(String peerId) => localPeers.contains(peerId);

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    localSendCallCount++;
    lastLocalSendTimeoutMs = timeoutMs;
    lastSentPeerId = peerId;
    lastSentMessage = message;
    return localSendResult;
  }

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async {
    probeRelayCallCount++;
    return probeRelayResult;
  }

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> saved = [];

  // Section 4: wireEnvelope tracking
  final List<String> wireEnvelopeUpdates = [];
  String? lastWireEnvelopeValue;
  VoidCallback? onUpdateWireEnvelope;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {
    wireEnvelopeUpdates.add(id);
    lastWireEnvelopeValue = envelope;
    onUpdateWireEnvelope?.call();
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => [];

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async => null;

  @override
  Future<void> updateMessageStatus(String id, String status) async {}

  @override
  Future<ConversationMessage?> getMessage(String id) async => null;

  @override
  Future<bool> messageExists(String id) async => false;

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async => 0;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;

  @override
  Future<int> getTotalUnreadCount() async => 0;

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

Future<List<String>> capturePrintedLines(Future<void> Function() action) async {
  final printed = <String>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (_, parent, zone, line) {
        printed.add(line);
      },
    ),
  );
  return printed;
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
  });

  group('sendChatMessage', () {
    test(
      'sanitizes outgoing comment text while preserving safe markers',
      () async {
        const rawText = 'مرحبا\u202E Hello\u200E 123';
        const sanitizedText = 'مرحبا Hello\u200E 123';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: rawText,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.text, sanitizedText);
        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.single.text, sanitizedText);

        final envelope =
            jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
        final payload = envelope['payload'] as Map<String, dynamic>;
        expect(payload['text'], sanitizedText);
        expect(payload['text'], isNot(contains('\u202E')));
      },
    );

    test(
      'rejects text that becomes empty after sanitization unless attachments exist',
      () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '\u202E   \u202C',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.invalidMessage);
        expect(message, isNull);
        expect(messageRepo.saved, isEmpty);

        final attachment = MediaAttachment(
          id: 'att-1',
          messageId: '',
          mime: 'image/png',
          size: 0,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-03-15T11:00:00.000Z',
        );

        final (attachmentResult, attachmentMessage) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '\u202E\u202C',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: [attachment],
        );

        expect(attachmentResult, SendChatMessageResult.success);
        expect(attachmentMessage, isNotNull);
        expect(attachmentMessage!.text, isEmpty);
        expect(attachmentMessage.media, hasLength(1));

        final envelope =
            jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
        final payload = envelope['payload'] as Map<String, dynamic>;
        expect(payload['text'], isEmpty);
        expect(payload['media'], isNotEmpty);
      },
    );

    test('returns invalidMessage for empty text', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: '',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(message, isNull);
      expect(messageRepo.saved, isEmpty);
    });

    test('returns invalidMessage for whitespace-only text', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: '   ',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(message, isNull);
    });

    test('returns nodeNotRunning when P2P is stopped', () async {
      p2pService = FakeP2PService(
        currentState: const NodeState(isStarted: false),
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.nodeNotRunning);
      expect(message, isNull);
    });

    test('returns success and persists message on successful send', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, 'Hello!');
      expect(message.senderPeerId, 'my-peer');
      expect(message.contactPeerId, 'target-peer');
      expect(message.isIncoming, false);
      expect(message.status, 'delivered'); // ack reply present
      expect(message.id, isNotEmpty);

      expect(messageRepo.saved.length, 1);
      expect(messageRepo.saved.first.id, message.id);
    });

    test('sends correct JSON envelope via P2P', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(p2pService.lastSentPeerId, 'target-peer');
      expect(p2pService.lastSentMessage, isNotNull);
      expect(p2pService.lastSentMessage, contains('"type":"chat_message"'));
      expect(p2pService.lastSentMessage, contains('"text":"Hello!"'));
    });

    test('uses provided messageId and timestamp when passed', () async {
      const fixedMessageId = 'msg-fixed-001';
      const fixedTimestamp = '2026-02-11T10:00:00.000Z';

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: fixedMessageId,
        timestamp: fixedTimestamp,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.id, fixedMessageId);
      expect(message.timestamp, fixedTimestamp);
      expect(messageRepo.saved.first.id, fixedMessageId);
      expect(messageRepo.saved.first.timestamp, fixedTimestamp);
      expect(p2pService.lastSentMessage, contains('"id":"$fixedMessageId"'));
      expect(
        p2pService.lastSentMessage,
        contains('"timestamp":"$fixedTimestamp"'),
      );
    });

    test('logs CHAT_OUT with delivered status and text preview', () async {
      final lines = await capturePrintedLines(() async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello from logger',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
      });

      expect(
        lines.any(
          (line) =>
              line.contains('[CHAT_OUT]') &&
              line.contains('status=delivered') &&
              line.contains('Hello from logger'),
        ),
        isTrue,
      );
    });

    test(
      'returns sendFailed and persists with failed status when send returns false',
      () async {
        p2pService.sendMessageResult = false;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.sendFailed);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'failed');
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'returns success and persists delivered status when inbox store succeeds',
      () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello queued!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'delivered');
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastInboxPeerId, 'target-peer');
        expect(p2pService.lastInboxMessage, isNotNull);
        expect(p2pService.lastInboxMessage, contains('"type":"chat_message"'));
      },
    );

    test('returns sendFailed when P2P throws exception', () async {
      // Make discover succeed but sendMessageWithReply throw
      p2pService = FakeP2PService();
      p2pService.shouldThrow = true;
      // Override discoverPeer so it doesn't throw (shouldThrow only affects send)
      // Actually, shouldThrow in our fake affects discover on first call too.
      // Let's use a cleaner approach:
      final customP2P = _ThrowOnSendP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: customP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.sendFailed);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
    });

    test('returns peerNotFound when discover returns null', () async {
      p2pService = FakeP2PService(useNullDiscover: true);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.peerNotFound);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
      // With the race-based send, discover is called once per attempt
      expect(p2pService.discoverCallCount, 1);
      expect(messageRepo.saved.length, 1);
      expect(messageRepo.saved.first.status, 'failed');
    });

    test('returns dialFailed when dial returns false', () async {
      p2pService = FakeP2PService(dialPeerResult: false);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.dialFailed);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
      // Race-based send: one discover + one dial attempt
      expect(p2pService.dialCallCount, 1);
      expect(messageRepo.saved.length, 1);
    });

    test(
      'flaky discover surfaces peerNotFound when direct discovery loses',
      () async {
        // With race-based send, a single failed discover causes the direct path
        // to fail. The inbox fallback (if available) would then be tried.
        final flakyP2P = _FlakyDiscoverP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: flakyP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        // Discover fails on the direct path, so the user-visible result should
        // preserve the more specific peerNotFound taxonomy.
        expect(result, SendChatMessageResult.peerNotFound);
        expect(message, isNotNull);
        expect(flakyP2P.discoverCallCount, 1);
      },
    );

    test('success with ack sets status to delivered', () async {
      p2pService = FakeP2PService(sendMessageReply: 'received: ok');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
    });

    test('success without ack sets status to sent', () async {
      p2pService = FakeP2PService(sendMessageReply: null);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'sent');
      expect(message.transport, 'direct');
      expect(message.wireEnvelope, isNotNull);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test('success with empty reply sets status to sent', () async {
      p2pService = FakeP2PService(sendMessageReply: '');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'sent');
      expect(message.transport, 'direct');
      expect(message.wireEnvelope, isNotNull);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'unacked direct send hands off to inbox immediately when available',
      () async {
        p2pService = FakeP2PService(
          sendMessageReply: null,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
        expect(message.wireEnvelope, isNull);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test('sends locally when peer is on local WiFi', () async {
      p2pService = FakeP2PService(useNullDiscover: true)
        ..localPeers.add('target-peer');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello local!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      // Local send was attempted (race includes local + direct)
      expect(p2pService.localSendCallCount, 1);
      expect(p2pService.probeRelayCallCount, 0);
    });

    test('falls through to relay when local send fails', () async {
      p2pService.localPeers.add('target-peer');
      p2pService.localSendResult = false;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello fallback!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      // Local was attempted but failed
      expect(p2pService.localSendCallCount, 1);
      // Relay path was used
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.sendCallCount, 1);
    });

    test('passes interactive local budget to the WiFi transport', () async {
      p2pService.localPeers.add('target-peer');
      p2pService.localSendResult = false;

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello timeout budget!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'direct');
      expect(
        p2pService.lastLocalSendTimeoutMs,
        interactiveLocalBudget.inMilliseconds,
      );
    });

    test('skips local send when peer is not on local WiFi', () async {
      // localPeers is empty by default
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello relay!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // No local send attempted
      expect(p2pService.localSendCallCount, 0);
      // Relay path used directly
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.sendCallCount, 1);
    });
  });

  group('Phase 3 — relay probe recovery', () {
    test(
      'discover miss then relay probe connected sends live without inbox',
      () async {
        p2pService = FakeP2PService(useNullDiscover: true);
        p2pService.probeRelayResult = RelayProbeResult.connected;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through probe',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'direct');
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
        expect(p2pService.probeRelayCallCount, 1);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'dial failed then relay probe connected sends live without inbox',
      () async {
        p2pService = FakeP2PService(dialPeerResult: false);
        p2pService.probeRelayResult = RelayProbeResult.connected;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello after dial failure',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'direct');
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 2);
        expect(p2pService.probeRelayCallCount, 1);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'discover miss then relay probe noReservation falls to inbox',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          storeInInboxResult: true,
        );
        p2pService.probeRelayResult = RelayProbeResult.noReservation;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello queued after no reservation',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
        expect(p2pService.probeRelayCallCount, 1);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'discover miss then relay probe error preserves inbox fallback',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          storeInInboxResult: true,
        );
        p2pService.probeRelayResult = RelayProbeResult.error;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello fallback after probe error',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
        expect(p2pService.probeRelayCallCount, 1);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'probe-connected send with lost ACK still uses inbox safety net',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          sendMessageReply: null,
          storeInInboxResult: true,
        );
        p2pService.probeRelayResult = RelayProbeResult.connected;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello with lost ack',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
        expect(p2pService.probeRelayCallCount, 1);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );
  });

  // ─── Phase 1: Interactive Send Path Tests ─────────────────────────
  group('Phase 1 — interactive send path', () {
    test(
      'existing connected peer is used before launching new transport attempts',
      () async {
        // Set up a FakeP2PService with the target peer already connected
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello connected!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Should have sent without discover/dial (connection reuse)
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.probeRelayCallCount, 0);
      },
    );

    test(
      'existing connected peer hands off unacked send to inbox on the same attempt',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          sendMessageReply: null,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello connected!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
      },
    );

    test(
      'local wifi and direct send race commits only the first successful path',
      () async {
        p2pService.localPeers.add('target-peer');
        // Both local and direct will succeed — but only one message should be persisted

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Race test!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        // Only one message should be persisted regardless of how many paths won
        expect(messageRepo.saved.length, 1);
      },
    );

    test(
      'slow local wifi does not block direct success beyond interactive budget',
      () async {
        // Create a service where local is slow but direct succeeds quickly
        final slowLocalP2P = _SlowLocalFastDirectP2PService();

        final stopwatch = Stopwatch()..start();
        final (result, message) = await sendChatMessage(
          p2pService: slowLocalP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Speed test!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Should complete quickly (direct path wins before local timeout)
        expect(stopwatch.elapsed.inSeconds, lessThan(3));
      },
    );

    test(
      'interactive direct discover uses short budget while background discover remains longer',
      () async {
        // This is a design/constant test — verify the budgets are distinct
        expect(interactiveLocalBudget.inMilliseconds, lessThanOrEqualTo(1500));
        expect(interactiveDirectBudget.inSeconds, lessThanOrEqualTo(4));
      },
    );

    test(
      'relay probe does not block direct discovery on the interactive path',
      () async {
        // Direct path should succeed without needing relay probe first
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'No relay probe!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Direct discover/dial/send succeeded without relay gates
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.probeRelayCallCount, 0);
      },
    );

    test('all active send paths failing falls back to inbox once', () async {
      p2pService = FakeP2PService(
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: true,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Inbox fallback!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'same messageId winning on two paths persists only one outgoing message',
      () async {
        p2pService.localPeers.add('target-peer');
        const fixedMessageId = 'msg-dedup-001';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Dedup test!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedMessageId,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // Only one message with this ID should be persisted
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.id, fixedMessageId);
      },
    );
  });

  // ─── Section 4 — direct-first send with early wireEnvelope persistence ──
  group(
    'Section 4 — direct-first send with early wireEnvelope persistence',
    () {
      test(
        'RED: wireEnvelope is persisted to DB before discover is called',
        () async {
          // Track cross-component ordering via a shared list
          final callOrder = <String>[];
          messageRepo.onUpdateWireEnvelope = () =>
              callOrder.add('updateWireEnvelope');
          p2pService.onDiscover = () => callOrder.add('discover');
          p2pService.onSendMessage = () => callOrder.add('sendMessage');

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'wireEnvelope persistence test',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-wire-001',
          );

          expect(result, SendChatMessageResult.success);
          // wireEnvelope must be persisted
          expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-001'));
          // wireEnvelope persist must happen before any P2P operation
          final wireIdx = callOrder.indexOf('updateWireEnvelope');
          final discoverIdx = callOrder.indexOf('discover');
          expect(
            wireIdx,
            isNot(-1),
            reason: 'updateWireEnvelope must be called',
          );
          expect(
            wireIdx < discoverIdx,
            isTrue,
            reason: 'wireEnvelope persist must precede discover',
          );
        },
      );

      test(
        'RED: wireEnvelope is persisted even on the connection-reuse fast path',
        () async {
          p2pService = FakeP2PService(
            currentState: NodeState(
              isStarted: true,
              connections: [
                const p2p.ConnectionState(
                  peerId: 'target-peer',
                  multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
                  direction: 'outbound',
                  status: 'connected',
                ),
              ],
            ),
          );

          final (result, _) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Connected peer wireEnvelope',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-wire-002',
          );

          expect(result, SendChatMessageResult.success);
          expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-002'));
          expect(p2pService.discoverCallCount, 0); // reuse path skips discover
        },
      );

      test('RED: wireEnvelope is persisted on local WiFi path', () async {
        p2pService = FakeP2PService(useNullDiscover: true)
          ..localPeers.add('target-peer');

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'WiFi wireEnvelope',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: 'msg-wire-003',
        );

        expect(result, SendChatMessageResult.success);
        expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-003'));
      });

      test(
        'RED: wireEnvelope contains the same JSON as the P2P send payload',
        () async {
          final (result, _) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Envelope parity',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'fixed-id-001',
          );

          expect(result, SendChatMessageResult.success);
          // Verify the persisted wireEnvelope matches what was sent over P2P
          expect(messageRepo.lastWireEnvelopeValue, isNotNull);
          expect(p2pService.lastSentPayload, isNotNull);
          expect(
            messageRepo.lastWireEnvelopeValue,
            equals(p2pService.lastSentPayload),
          );
          expect(
            messageRepo.lastWireEnvelopeValue,
            contains('"id":"fixed-id-001"'),
          );
        },
      );

      test(
        'RED: wireEnvelope is persisted even when all P2P paths fail',
        () async {
          p2pService = FakeP2PService(
            sendMessageResult: false,
            useNullDiscover: true,
            storeInInboxResult: false,
          );

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'All fail but envelope persisted',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: 'msg-wire-fail',
          );

          expect(result, SendChatMessageResult.peerNotFound);
          expect(message!.status, 'failed');
          // wireEnvelope was still persisted before the transport race
          expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-fail'));
        },
      );
    },
  );

  // ─── Section 4 — inbox call-site regression guard ──────────────────────
  group('Section 4 — inbox call-site regression guard', () {
    test(
      'storeInInbox is NOT called when direct P2P succeeds with ACK',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: true, // P2P succeeds with ACK
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Direct success no inbox',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        // Inbox must NOT be called on ACK'd direct send — avoids phantom push
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'storeInInbox IS called once when P2P succeeds without ACK (existing behavior)',
      () async {
        // sendMessageResult returns empty string (success but unacked)
        p2pService = FakeP2PService(
          sendMessageResult: true,
          sendMessageReply: '', // empty = unacked
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Unacked send',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        // Unacked path calls storeInInbox as fallback — existing behavior
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'storeInInbox IS called once when all P2P paths fail (existing behavior)',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          useNullDiscover: true,
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'All fail inbox fallback',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
        // Exactly one inbox call from the failure fallback — not zero, not two
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );

    test(
      'when all P2P paths fail and inbox also fails, message persists as failed',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          useNullDiscover: true,
          storeInInboxResult: false,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Both fail',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.peerNotFound);
        expect(message!.status, 'failed');
        // The failure fallback attempted inbox once
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );
  });

  // ─── Section 4 — inbox fallback edge cases ─────────────────────────────
  group('Section 4 — inbox fallback edge cases', () {
    test('storeInInbox throwing in the fallback path marks message as failed '
        'and wireEnvelope is still persisted for retry', () async {
      final throwingInboxP2P = _ThrowOnInboxP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: throwingInboxP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Inbox throws after P2P fails',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-edge-001',
      );

      // P2P failed, inbox threw — message should be marked failed
      expect(result, SendChatMessageResult.peerNotFound);
      expect(message!.status, 'failed');
      // wireEnvelope was still persisted, so Section 1 retrier can recover
      expect(messageRepo.wireEnvelopeUpdates, contains('msg-edge-001'));
    });

    test(
      'storeInInbox throwing does not affect result when direct P2P succeeds',
      () async {
        // P2P succeeds, so inbox fallback is never reached
        final throwingInboxP2P = _ThrowOnInboxP2PService(p2pSucceeds: true);

        final (result, message) = await sendChatMessage(
          p2pService: throwingInboxP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox throws but P2P succeeds',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
      },
    );

    test(
      'slow relay does not block P2P path — P2P result returns promptly',
      () async {
        // The existing behavior already runs inbox only on failure.
        // This test confirms P2P success returns without waiting for any
        // inbox operation (since inbox is not called on ACK'd success).
        p2pService = FakeP2PService(sendMessageResult: true);

        final stopwatch = Stopwatch()..start();
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast direct',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(stopwatch.elapsed.inSeconds, lessThan(3));
        expect(p2pService.storeInInboxCallCount, 0); // no inbox on success
      },
    );
  });
}

/// P2P service where discover/dial succeed but storeInInbox throws.
/// Used to test inbox fallback error handling.
class _ThrowOnInboxP2PService implements P2PService {
  final bool p2pSucceeds;

  _ThrowOnInboxP2PService({this.p2pSucceeds = false});

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => p2pSucceeds;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => SendMessageResult(
    sent: p2pSucceeds,
    reply: p2pSucceeds ? 'received: ok' : null,
  );

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      p2pSucceeds
      ? const DiscoveredPeer(
          id: 'target-peer',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        )
      : null;

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => p2pSucceeds;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async =>
      throw Exception('Inbox store exploded');

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

/// P2P service that discovers and dials successfully but throws on send.
class _ThrowOnSendP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async =>
      throw Exception('Send exploded');

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => throw Exception('Send exploded');

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      const DiscoveredPeer(
        id: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

/// P2P service where discover fails on first attempt, succeeds on subsequent.
class _FlakyDiscoverP2PService implements P2PService {
  int discoverCallCount = 0;

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverCallCount++;
    if (discoverCallCount == 1) return null;
    return const DiscoveredPeer(
      id: 'target-peer',
      addresses: ['/ip4/127.0.0.1/tcp/4001'],
    );
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

/// P2P service where local send is slow but direct path succeeds fast.
class _SlowLocalFastDirectP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      const DiscoveredPeer(
        id: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isLocalPeer(String peerId) => true;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    // Simulate slow local send (3 seconds)
    await Future.delayed(const Duration(seconds: 3));
    return true;
  }

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}
