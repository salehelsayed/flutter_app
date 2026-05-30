import 'dart:convert';
import 'dart:async';
import 'dart:ui' show VoidCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    hide sendChatMessage, editChatMessage;
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    as chat_use_case
    show sendChatMessage, editChatMessage;
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';

// -- Fake P2P Service --
class FakeP2PService implements P2PService, ReadinessProofRecorder {
  final NodeState _currentState;
  bool sendMessageResult;
  String? sendMessageReply;
  bool? sendMessageAcked;
  String? sendMessageTransport;
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
  int recordSuccessfulSendProofCallCount = 0;
  String? lastReadinessProofSource;
  String? lastReadinessTrigger;
  String? lastReadinessSendPath;

  /// Use [useNullDiscover] to explicitly request null discoverPeer results.
  FakeP2PService({
    NodeState? currentState,
    this.sendMessageResult = true,
    this.sendMessageReply = 'received: ok',
    this.sendMessageAcked,
    this.sendMessageTransport,
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
    if (sendDelay > Duration.zero) {
      await Future<void>.delayed(sendDelay);
    }
    lastSentPeerId = peerId;
    lastSentMessage = message;
    lastSentPayload = message;
    sendCallCount++;
    onSendMessage?.call();
    return SendMessageResult(
      sent: sendMessageResult,
      acked: sendMessageAcked,
      reply: sendMessageReply,
      transport: sendMessageTransport,
    );
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
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
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

  int discoverLocalPeerCallCount = 0;
  Duration? lastDiscoverLocalPeerTimeout;

  /// Optional override for the discover-on-send result. When non-null this is
  /// returned instead of the default `localPeers.contains` behavior; setting it
  /// to true (without seeding [localPeers]) simulates an unknown-but-LAN-present
  /// peer that mDNS resolves at send time (U3).
  bool? discoverLocalPeerResult;

  /// When > 0, [discoverLocalPeer] delays this long before resolving (still
  /// bounded by the caller's timeout) to model a bounded resolve that joins the
  /// race within budget.
  Duration discoverLocalPeerDelay = Duration.zero;

  /// NET-REL-05 U-P3 (sticky): seeds the learned-per-peer transport read at the
  /// top of the race. Null (default) means a cold send — full race, no
  /// head-start (matches today). When set, the matching leg gets a head-start.
  String? lastKnownGoodTransportResult;

  /// NET-REL-05 U-P3: records of `recordSuccessfulTransport` writes so a test
  /// can assert the live transport that delivered was remembered.
  int recordSuccessfulTransportCallCount = 0;
  String? lastRecordedTransport;
  String? lastRecordedTransportPeerId;

  /// NET-REL-05 U-P2 (grace) / U-P5 (budget): per-leg artificial latency so a
  /// test can model a transport landing slightly behind another (grace) or a
  /// leg overrunning its budget. [sendDelay] gates the direct/reuse/relay
  /// `sendMessageWithReply`; [localSendDelay] gates `sendLocalMessage`.
  Duration sendDelay = Duration.zero;
  Duration localSendDelay = Duration.zero;

  @override
  String? lastKnownGoodTransport(String peerId) => lastKnownGoodTransportResult;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {
    recordSuccessfulTransportCallCount++;
    lastRecordedTransport = transport;
    lastRecordedTransportPeerId = peerId;
  }

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async {
    discoverLocalPeerCallCount++;
    lastDiscoverLocalPeerTimeout = timeout;
    if (discoverLocalPeerDelay > Duration.zero) {
      await Future<void>.delayed(discoverLocalPeerDelay);
    }
    final resolved = discoverLocalPeerResult ?? localPeers.contains(peerId);
    // A successful discover-on-send makes the peer reachable for the
    // subsequent sendLocalMessage call, mirroring the production map write.
    if (resolved) {
      localPeers.add(peerId);
    }
    // Negative-control default: not discovered unless the peer is already local.
    return resolved;
  }

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async {
    localSendCallCount++;
    lastLocalSendTimeoutMs = timeoutMs;
    if (localSendDelay > Duration.zero) {
      await Future<void>.delayed(localSendDelay);
    }
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
  bool get hasPendingResumeStarted => false;

  @override
  void markResumeStarted() {}

  @override
  void clearResumeStarted() {}

  @override
  void noteTransportSessionReset({required String trigger}) {}

  @override
  void recordSuccessfulSendProof({
    required String source,
    required String trigger,
    String? sendPath,
  }) {
    recordSuccessfulSendProofCallCount++;
    lastReadinessProofSource = source;
    lastReadinessTrigger = trigger;
    lastReadinessSendPath = sendPath;
  }

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

  /// NET-REL-05 U-P1P4 (concurrent fallback): seeds the prior-attempt the
  /// low-confidence heuristic inspects. Null (default) = no prior attempt =
  /// high-confidence (single-path).
  ConversationMessage? latestMessageForContact;
  int getLatestMessageForContactCallCount = 0;

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    getLatestMessageForContactCallCount++;
    return latestMessageForContact;
  }

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
  Future<int> deleteMessage(String id) async => 0;

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
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await runZoned(
      action,
      zoneSpecification: ZoneSpecification(
        print: (_, parent, zone, line) {
          printed.add(line);
        },
      ),
    );
  } finally {
    debugPrint = originalDebugPrint;
  }
  return printed;
}

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void expectSendFlowEventsOmitMessagePreview(
  List<Map<String, dynamic>> events, {
  required String terminalEvent,
  required Iterable<String> forbiddenFragments,
}) {
  final sendEvents = events
      .where(
        (event) =>
            (event['event'] as String?)?.startsWith('CHAT_MSG_SEND_') ?? false,
      )
      .toList();
  final sendEventNames = sendEvents.map((event) => event['event']).toList();
  expect(sendEventNames, contains('CHAT_MSG_SEND_START'));
  expect(sendEventNames, contains(terminalEvent));

  for (final event in sendEvents) {
    final details = event['details'];
    if (details is Map) {
      expect(
        details.containsKey('textPreview'),
        isFalse,
        reason: '${event['event']} exposed a textPreview detail',
      );
    }
  }

  final serializedPayload = jsonEncode(sendEvents);
  for (final fragment in forbiddenFragments) {
    expect(serializedPayload, isNot(contains(fragment)));
  }
}

const testRecipientMlKemPublicKey = 'recipient-mlkem-public-key';

Future<(SendChatMessageResult, ConversationMessage?)> sendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String action = MessagePayload.actionSend,
  String? editedAt,
  String? messageId,
  String? timestamp,
  String? createdAt,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
  TransportMetrics? transportMetrics,
}) {
  return chat_use_case.sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: targetPeerId,
    text: text,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    action: action,
    editedAt: editedAt,
    messageId: messageId,
    timestamp: timestamp,
    createdAt: createdAt,
    bridge: bridge ?? PassthroughCryptoBridge(),
    recipientMlKemPublicKey:
        recipientMlKemPublicKey ?? testRecipientMlKemPublicKey,
    quotedMessageId: quotedMessageId,
    mediaAttachments: mediaAttachments,
    mediaAttachmentRepo: mediaAttachmentRepo,
    emitTimingEvent: emitTimingEvent,
    transportMetrics: transportMetrics,
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> editChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  required String updatedText,
  required String senderUsername,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool emitTimingEvent = true,
}) {
  return chat_use_case.editChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    originalMessage: originalMessage,
    updatedText: updatedText,
    senderUsername: senderUsername,
    bridge: bridge ?? PassthroughCryptoBridge(),
    recipientMlKemPublicKey:
        recipientMlKemPublicKey ?? testRecipientMlKemPublicKey,
    mediaAttachmentRepo: mediaAttachmentRepo,
    emitTimingEvent: emitTimingEvent,
  );
}

Map<String, dynamic> decodeWirePayload(String wireJson) {
  final envelope = jsonDecode(wireJson) as Map<String, dynamic>;
  final payload = envelope['payload'];
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
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

        final payload = decodeWirePayload(p2pService.lastSentMessage!);
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

        final payload = decodeWirePayload(p2pService.lastSentMessage!);
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

    test('returns encryptionRequired when bridge is missing', () async {
      final (result, message) = await chat_use_case.sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.encryptionRequired);
      expect(message, isNull);
      expect(p2pService.sendCallCount, 0);
      expect(p2pService.localSendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(messageRepo.saved, isEmpty);
      expect(messageRepo.wireEnvelopeUpdates, isEmpty);
    });

    test(
      'returns encryptionRequired when recipient ML-KEM key is missing',
      () async {
        final (result, message) = await chat_use_case.sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: FakeBridge(),
        );

        expect(result, SendChatMessageResult.encryptionRequired);
        expect(message, isNull);
        expect(p2pService.sendCallCount, 0);
        expect(p2pService.localSendCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.saved, isEmpty);
        expect(messageRepo.wireEnvelopeUpdates, isEmpty);
      },
    );

    test('sends v2 encrypted envelope without plaintext payload', () async {
      final bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'opaque-kem',
            'ciphertext': 'opaque-chat-ciphertext',
            'nonce': 'opaque-nonce',
          },
        },
      );

      final (result, _) = await chat_use_case.sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Secret relay text',
        senderPeerId: 'my-peer',
        senderUsername: 'Private Me',
        bridge: bridge,
        recipientMlKemPublicKey: testRecipientMlKemPublicKey,
      );

      expect(result, SendChatMessageResult.success);
      final envelope =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      expect(envelope['type'], 'chat_message');
      expect(envelope['version'], '2');
      expect(envelope.containsKey('payload'), isFalse);
      expect(envelope['encrypted'], isA<Map<String, dynamic>>());
      expect(p2pService.lastSentMessage, isNot(contains('Secret relay text')));
      expect(p2pService.lastSentMessage, isNot(contains('Private Me')));
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

    test(
      'removes stale upload_pending placeholder rows before saving final attachments',
      () async {
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        const messageId = 'msg-stable-cleanup-001';

        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'placeholder-upload-pending',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/pending.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Photo',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: messageId,
          timestamp: '2026-01-01T00:00:00.000Z',
          mediaAttachments: const [
            MediaAttachment(
              id: 'uploaded-final-id',
              messageId: '',
              mime: 'image/jpeg',
              size: 2048,
              mediaType: 'image',
              localPath: '/tmp/final.jpg',
              downloadStatus: 'done',
              createdAt: '2026-01-01T00:00:00.000Z',
            ),
          ],
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendChatMessageResult.success);
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
        );
        expect(attachments.length, 1);
        expect(attachments.single.id, 'uploaded-final-id');
        expect(attachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
      },
    );

    test(
      'sends GIF-only media with image/gif preserved in the wire envelope',
      () async {
        final attachment = MediaAttachment(
          id: 'gif-attachment',
          messageId: '',
          mime: 'image/gif',
          size: 4096,
          mediaType: 'image',
          localPath: '/tmp/funny.gif',
          downloadStatus: 'done',
          createdAt: '2026-03-15T11:00:00.000Z',
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: [attachment],
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.media, hasLength(1));
        expect(message.media.single.mime, 'image/gif');
        expect(message.media.single.isAnimated, isTrue);

        final payload = decodeWirePayload(p2pService.lastSentMessage!);
        final media = payload['media'] as List<dynamic>;
        expect(media, hasLength(1));
        expect((media.single as Map<String, dynamic>)['mime'], 'image/gif');
      },
    );

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
      final envelope =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      final payload = decodeWirePayload(p2pService.lastSentMessage!);
      expect(envelope['type'], 'chat_message');
      expect(envelope['version'], '2');
      expect(envelope.containsKey('payload'), isFalse);
      expect(payload['text'], 'Hello!');
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
      final payload = decodeWirePayload(p2pService.lastSentMessage!);
      expect(payload['id'], fixedMessageId);
      expect(payload['timestamp'], fixedTimestamp);
    });

    test('editChatMessage preserves the original row contract', () async {
      const original = ConversationMessage(
        id: 'msg-edit-001',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Original text',
        timestamp: '2026-02-11T10:00:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-02-11T10:00:01.000Z',
        quotedMessageId: 'quoted-001',
      );

      final (result, message) = await editChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        originalMessage: original,
        updatedText: 'Edited text',
        senderUsername: 'Me',
      );

      final payload = decodeWirePayload(p2pService.lastSentMessage!);

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.id, original.id);
      expect(message.timestamp, original.timestamp);
      expect(message.createdAt, original.createdAt);
      expect(message.quotedMessageId, original.quotedMessageId);
      expect(message.editedAt, isNotNull);
      expect(messageRepo.saved.first.createdAt, original.createdAt);
      expect(messageRepo.saved.first.editedAt, isNotNull);
      expect(payload['id'], original.id);
      expect(payload['timestamp'], original.timestamp);
      expect(payload['quotedMessageId'], original.quotedMessageId);
      expect(payload['action'], MessagePayload.actionEdit);
      expect(payload['editedAt'], isNotNull);
    });

    test('editChatMessage rejects failed outgoing messages', () async {
      const failed = ConversationMessage(
        id: 'msg-failed-edit-001',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Recover me',
        timestamp: '2026-02-11T10:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-02-11T10:00:01.000Z',
      );

      final (result, message) = await editChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        originalMessage: failed,
        updatedText: 'Recover me again',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(message, isNull);
      expect(p2pService.sendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(messageRepo.saved, isEmpty);
      expect(messageRepo.wireEnvelopeUpdates, isEmpty);
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
      'emits CHAT_MSG_SEND_TIMING with elapsed outcome and attachment flag',
      () async {
        final events = await captureFlowEvents(() async {
          await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Timing proof',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'CHAT_MSG_SEND_TIMING',
        );
        expect(timing['details']['outcome'], 'success');
        expect(timing['details']['elapsedMs'], isA<int>());
        expect(timing['details']['hasAttachments'], isFalse);
      },
    );

    test('send flow events omit message-derived previews', () async {
      const directBody =
          'TOM001_DIRECT_BODY_FRAGMENT_ALPHA private direct message';
      final directP2P = FakeP2PService();
      final directRepo = FakeMessageRepository();
      final directEvents = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: directP2P,
          messageRepo: directRepo,
          targetPeerId: 'target-peer',
          text: directBody,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'direct');
      });
      expectSendFlowEventsOmitMessagePreview(
        directEvents,
        terminalEvent: 'CHAT_MSG_SEND_SUCCESS',
        forbiddenFragments: const [directBody, 'TOM001_DIRECT_BODY_FRAGMENT'],
      );

      const inboxBody =
          'TOM001_INBOX_FALLBACK_BODY_FRAGMENT_BETA private inbox message';
      final inboxP2P = FakeP2PService(
        sendMessageResult: false,
        storeInInboxResult: true,
      );
      final inboxRepo = FakeMessageRepository();
      final inboxEvents = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: inboxP2P,
          messageRepo: inboxRepo,
          targetPeerId: 'target-peer',
          text: inboxBody,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'inbox');
      });
      expectSendFlowEventsOmitMessagePreview(
        inboxEvents,
        terminalEvent: 'CHAT_MSG_SEND_SUCCESS',
        forbiddenFragments: const [
          inboxBody,
          'TOM001_INBOX_FALLBACK_BODY_FRAGMENT',
        ],
      );

      const failedBody =
          'TOM001_FAILED_BODY_FRAGMENT_GAMMA private failed message';
      final failedP2P = FakeP2PService(sendMessageResult: false);
      final failedRepo = FakeMessageRepository();
      final failedEvents = await captureFlowEvents(() async {
        final (result, message) = await sendChatMessage(
          p2pService: failedP2P,
          messageRepo: failedRepo,
          targetPeerId: 'target-peer',
          text: failedBody,
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        expect(result, SendChatMessageResult.sendFailed);
        expect(message!.status, 'failed');
      });
      expectSendFlowEventsOmitMessagePreview(
        failedEvents,
        terminalEvent: 'CHAT_MSG_SEND_FAILED',
        forbiddenFragments: const [failedBody, 'TOM001_FAILED_BODY_FRAGMENT'],
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
        expect(p2pService.recordSuccessfulSendProofCallCount, 1);
        expect(p2pService.lastReadinessProofSource, 'chat_send_inbox');
        expect(p2pService.lastReadinessTrigger, 'user_action');
        expect(p2pService.lastReadinessSendPath, 'inbox');
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
      expect(p2pService.recordSuccessfulSendProofCallCount, 1);
      expect(p2pService.lastReadinessProofSource, 'chat_send_direct');
      expect(p2pService.lastReadinessTrigger, 'user_action');
      expect(p2pService.lastReadinessSendPath, 'direct');
    });

    test('success without ack keeps sent when inbox handoff fails', () async {
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

    test(
      'success with empty reply keeps sent when inbox handoff fails',
      () async {
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
      },
    );

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
      expect(p2pService.recordSuccessfulSendProofCallCount, 1);
      expect(p2pService.lastReadinessProofSource, 'chat_send_local');
      expect(p2pService.lastReadinessSendPath, 'local');
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

    // U-P2-ttl / doc U2: a stale discovered peer is treated as NOT local by
    // the read-time freshness filter (getLocalPeer/isLocalPeer return false).
    // The send path must therefore skip the local leg entirely and let the
    // direct leg carry the message WITHOUT burning the 1500ms local budget.
    test(
      'stale peer skips local send and does not burn the local budget',
      () async {
        // Mirror production: a stale entry makes isLocalPeer() return false, so
        // localPeers stays empty here (the freshness filter already dropped it).
        p2pService = FakeP2PService();
        expect(p2pService.isLocalPeer('target-peer'), isFalse);

        final sw = Stopwatch()..start();
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello stale!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );
        sw.stop();

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        // No local send attempted for a stale (non-fresh) peer.
        expect(p2pService.localSendCallCount, 0);
        // Direct leg carried it — never reports the outbound 'local' label.
        expect(message!.transport, isNot('local'));
        // Far under interactiveLocalBudget (1500ms): no stale host:port burn.
        expect(
          sw.elapsedMilliseconds,
          lessThan(interactiveLocalBudget.inMilliseconds),
        );
      },
    );
  });

  // ─── NET-REL-01 (LAN/WiFi reliability) — labeled coverage ──────────
  // U1 happy / U2 TTL-degraded / U3 discover-on-send / U-N1 negative control.
  // These pin the exact transport label so a future regression that hard-codes
  // 'local' (U1) or drops the discover-on-send leg (U3) is caught, while U-N1
  // proves U1 is not just always reporting 'local'.
  group('NET-REL-01 LAN transport', () {
    // U1 — happy path: peer already in localPeers → the message uses the LAN
    // path (transport=='local'), the local leg fires exactly once, and the
    // relay probe is never reached because local wins the race.
    test('U1 happy: discovered local peer delivers via local transport',
        () async {
      // useNullDiscover makes the parallel direct leg miss, so only the local
      // leg can win — proving 'local' is the path actually taken.
      p2pService = FakeP2PService(useNullDiscover: true)
        ..localPeers.add('target-peer');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello on the LAN',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'local');
      expect(p2pService.localSendCallCount, 1);
      expect(p2pService.probeRelayCallCount, 0);
      // Already-local: no discover-on-send resolve needed.
      expect(p2pService.discoverLocalPeerCallCount, 0);
    });

    // U2 — TTL / degraded: a stale entry is dropped by the read-time freshness
    // filter, so isLocalPeer is false and discoverLocalPeer also fails (the peer
    // is genuinely gone). The local leg must NOT deliver and must NOT burn the
    // full 1500ms budget before the direct leg carries it. (Complements the
    // 'stale peer skips local send' test above, which covers the already-local
    // false path; here we assert the discover-on-send leg also fails fast.)
    test('U2 TTL-degraded: stale/absent peer fails local fast, direct carries',
        () async {
      // Not in localPeers and discover-on-send resolves false (peer departed).
      p2pService = FakeP2PService()..discoverLocalPeerResult = false;
      expect(p2pService.isLocalPeer('target-peer'), isFalse);

      final sw = Stopwatch()..start();
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello departed peer',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // Discover-on-send was attempted but resolved false, so no LAN send.
      expect(p2pService.discoverLocalPeerCallCount, 1);
      expect(p2pService.localSendCallCount, 0);
      expect(message!.transport, isNot('local'));
      // The discover-on-send leg returns false promptly — it must not consume
      // the full local budget before the direct leg wins.
      expect(
        sw.elapsedMilliseconds,
        lessThan(interactiveLocalBudget.inMilliseconds),
      );
    });

    // U3 — discover-on-send: peer is unknown at send time (not in localPeers)
    // but IS present on the LAN. The bounded resolve succeeds within budget, so
    // the local leg joins the race and delivers via 'local'.
    test('U3 discover-on-send: unknown-but-LAN-present peer joins via local',
        () async {
      // Direct leg misses (useNullDiscover) so only the freshly-resolved local
      // leg can win. discoverLocalPeerResult=true models mDNS resolving at send
      // time; a small bounded delay proves it still lands inside the budget.
      p2pService = FakeP2PService(useNullDiscover: true)
        ..discoverLocalPeerResult = true
        ..discoverLocalPeerDelay = const Duration(milliseconds: 50);
      // Precondition: peer is NOT already known as local.
      expect(p2pService.isLocalPeer('target-peer'), isFalse);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello just-foregrounded peer',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // Bounded resolve ran, then the local leg delivered within budget.
      expect(p2pService.discoverLocalPeerCallCount, 1);
      expect(
        p2pService.lastDiscoverLocalPeerTimeout,
        interactiveLocalBudget,
      );
      expect(p2pService.localSendCallCount, 1);
      expect(message!.transport, 'local');
    });

    // U-N1 — NEGATIVE CONTROL: peer NOT on the LAN and the LAN send is forced to
    // fail. discover-on-send resolves false, the local leg is never reached, and
    // the message is delivered by a non-local transport. This is what proves U1
    // isn't hard-coding 'local'.
    test('U-N1 negative control: non-LAN peer never uses local transport',
        () async {
      p2pService = FakeP2PService()
        ..discoverLocalPeerResult = false // not discoverable on the LAN
        ..localSendResult = false; // and the LAN send would fail anyway
      expect(p2pService.isLocalPeer('target-peer'), isFalse);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello over relay/direct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // The won transport is anything but local (direct/relay/inbox).
      expect(message!.transport, isNot('local'));
      expect(
        const ['direct', 'relay', 'inbox'],
        contains(message.transport),
      );
      // sendLocalMessage was never reached: the LAN leg lost the race outright.
      expect(p2pService.localSendCallCount, 0);
      // The direct leg carried the message.
      expect(p2pService.sendCallCount, 1);
    });
  });

  group('Phase 3 — relay probe recovery', () {
    test(
      'relay probe success persists relay when send result transport says relay',
      () async {
        p2pService = FakeP2PService(
          useNullDiscover: true,
          sendMessageTransport: 'relay',
        );
        p2pService.probeRelayResult = RelayProbeResult.connected;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through relay probe',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'relay');
      },
    );

    test(
      'relay probe falls back to state inference only when send transport is absent',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: [
                  '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit',
                ],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          useNullDiscover: true,
          sendMessageTransport: null,
        );
        p2pService.probeRelayResult = RelayProbeResult.connected;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello with inferred relay fallback',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(message.transport, 'relay');
      },
    );

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
      'probe-connected send with lost ACK hands off to inbox immediately',
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
        expect(message.wireEnvelope, isNull);
        expect(p2pService.probeRelayCallCount, 1);
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
      },
    );
  });

  // ─── Phase 1: Interactive Send Path Tests ─────────────────────────
  group('Phase 1 — interactive send path', () {
    test(
      'direct discover path persists actual send transport when Go returns relay',
      () async {
        p2pService = FakeP2PService(sendMessageTransport: 'relay');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through actual relay',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.sendCallCount, 1);
      },
    );

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
        expect(message!.transport, 'direct');
        // Should have sent without discover/dial (connection reuse)
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.probeRelayCallCount, 0);
      },
    );

    test(
      'existing relay-backed connection persists relay transport on the reuse fast path',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: [
                  '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit',
                ],
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
          text: 'Hello through reused relay',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
      },
    );

    test(
      'explicit send transport beats conflicting mixed peer state on the reuse fast path',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/192.168.1.20/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: [
                  '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit',
                ],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
          sendMessageTransport: 'direct',
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through actual direct stream',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'direct');
      },
    );

    test(
      'existing local peer persists local transport on the reuse fast path',
      () async {
        p2pService = FakeP2PService(
          currentState: NodeState(
            isStarted: true,
            connections: [
              const p2p.ConnectionState(
                peerId: 'target-peer',
                multiaddrs: ['/ip4/192.168.1.20/tcp/4001'],
                direction: 'outbound',
                status: 'connected',
              ),
            ],
          ),
        )..localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through reused local',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'local');
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
      },
    );

    test(
      'existing connected peer hands off an unacked send to inbox on the same attempt',
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
        expect(message.wireEnvelope, isNull);
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

    test('storeInInbox is called when P2P succeeds without ACK', () async {
      p2pService = FakeP2PService(
        sendMessageResult: true,
        sendMessageReply: '',
        storeInInboxResult: true,
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
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(message.transport, 'inbox');
      expect(message.wireEnvelope, isNull);
      expect(p2pService.storeInInboxCallCount, 1);
    });

    test(
      'explicit acked=false hands off to inbox-backed delivered when available',
      () async {
        p2pService = FakeP2PService(
          sendMessageResult: true,
          sendMessageAcked: false,
          sendMessageReply: '',
          sendMessageTransport: 'direct',
          storeInInboxResult: true,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Explicit unacked send',
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

  group('NET-REL-04 — per-leg send-attempt census', () {
    test(
      'direct leg failure is recorded even when the relay probe delivers '
      '(the delivered-only mix cannot show this)',
      () async {
        // Direct race leg fails (discover miss → peer_not_found), then the
        // relay probe connects and delivers.
        p2pService = FakeP2PService(useNullDiscover: true);
        p2pService.probeRelayResult = RelayProbeResult.connected;
        final metrics = TransportMetrics();

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello through probe',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          transportMetrics: metrics,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');

        // The direct attempt failed, the relay probe attempt succeeded.
        expect(metrics.attemptCounts()['direct'], 1);
        expect(metrics.attemptFailureCounts()['direct'], 1);
        expect(metrics.attemptCounts()['relay_probe'], 1);
        expect(metrics.attemptFailureCounts()['relay_probe'], 0);
        // The terminal rung is relay_probe, not failed.
        expect(metrics.rungDistribution()['relay_probe'], 1);
        expect(metrics.rungDistribution()['failed'], 0);
        // Inbox was never reached.
        expect(metrics.attemptCounts()['inbox'], 0);
      },
    );

    test('connection reuse success records exactly one successful reuse attempt '
        'and no race-leg attempts', () async {
      p2pService = FakeP2PService(
        sendMessageResult: true,
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
      final metrics = TransportMetrics();

      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Reuse hello',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        transportMetrics: metrics,
      );

      expect(result, SendChatMessageResult.success);
      expect(metrics.attemptCounts()['reuse'], 1);
      expect(metrics.attemptFailureCounts()['reuse'], 0);
      expect(metrics.attemptCounts()['direct'], 0);
      expect(metrics.attemptCounts()['local'], 0);
      expect(metrics.rungDistribution()['reuse'], 1);
    });

    test('total send failure records failed attempts for every leg it tried',
        () async {
      // No reuse (not connected), discover miss, relay probe errors, inbox
      // store fails → terminal failure.
      p2pService = FakeP2PService(useNullDiscover: true);
      p2pService.probeRelayResult = RelayProbeResult.error;
      p2pService.storeInInboxResult = false;
      final metrics = TransportMetrics();

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Doomed send',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        transportMetrics: metrics,
      );

      expect(result, isNot(SendChatMessageResult.success));
      expect(message!.status, 'failed');
      expect(metrics.attemptFailureCounts()['direct'], 1);
      expect(metrics.attemptFailureCounts()['relay_probe'], 1);
      expect(metrics.attemptFailureCounts()['inbox'], 1);
      expect(metrics.rungDistribution()['failed'], 1);
      // No transport bucket incremented for a failed send.
      expect(metrics.totalTransportSamples, 0);
    });
  });

  // ─── NET-REL-05 — send orchestration (grace, sticky, concurrent, dedup) ──
  //
  // Each happy case is paired with the negative control the doc names so a weak
  // test cannot pass falsely. U1/U-N1 prove the grace window prefers the better
  // transport WITHOUT hanging on a failed leg. U2/U-N2 prove the learned-sticky
  // head-start saves discovery work WITHOUT trapping the send on a dead path or
  // honoring a stale preference. U3/U-N3 prove the concurrent inbox fires for a
  // low-confidence send only, NOT a blanket dual-write. U4/U-N4 prove send-side
  // single-row dedup (same id → 1, different ids → 2). U5 + its budget control
  // prove the offline tail is bounded and a budget is actually ENFORCED.
  group('NET-REL-05 send orchestration', () {
    // U1 — grace window (happy): local and direct BOTH succeed; direct lands
    // first (local is delayed slightly, but well within the 150ms grace), yet
    // the better-ranked 'local' transport is preferred. Proves the grace
    // window honors local > direct, not pure first-wins.
    test('U1 grace: local lands within grace of direct → transport == local',
        () async {
      p2pService = FakeP2PService()
        ..localPeers.add('target-peer')
        // Direct resolves immediately; local lands ~40ms later — inside the
        // 150ms grace window, so it must still preempt the worse direct leg.
        ..localSendDelay = const Duration(milliseconds: 40);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Grace prefers local',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // Direct succeeded first but local won the grace → local is committed.
      expect(message!.transport, 'local');
      expect(p2pService.localSendCallCount, 1);
      expect(p2pService.sendCallCount, 1);
    });

    // U-N1 — grace NEGATIVE control: local FAILS, direct succeeds. The grace
    // timer must NOT be armed to wait out the (now impossible) local win — the
    // send commits 'direct' promptly with no hung wait. Proves U1's preference
    // logic does not block on a leg that can never land.
    test('U-N1 grace neg: local fails → direct chosen with no hung wait',
        () async {
      p2pService = FakeP2PService()
        ..localPeers.add('target-peer')
        ..localSendResult = false; // local leg fails outright

      final sw = Stopwatch()..start();
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Local fails, direct carries',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'direct');
      expect(p2pService.localSendCallCount, 1);
      // No grace wait: the resolved/failed local leg clears the only leg that
      // could outrank direct, so the completer settles immediately. Far under
      // the grace window (150ms) — proves it is not parked on a timer.
      expect(sw.elapsedMilliseconds, lessThan(120));
    });

    // U2 — sticky/learned (happy): a peer last delivered over 'direct'. The
    // learned head-start lets the direct leg win the close tie while the local
    // leg is held back, so when local is NOT on the LAN there is no wasted
    // local discovery and the message is delivered via the learned transport.
    test('U2 sticky: learned direct delivers via direct, fewer local attempts',
        () async {
      // Cold baseline: no learned transport, peer not local. The local
      // discover-on-send leg fires once (cold).
      final coldP2P = FakeP2PService()..discoverLocalPeerResult = false;
      final (coldResult, coldMessage) = await sendChatMessage(
        p2pService: coldP2P,
        messageRepo: FakeMessageRepository(),
        targetPeerId: 'target-peer',
        text: 'Cold send',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      expect(coldResult, SendChatMessageResult.success);
      expect(coldMessage!.transport, 'direct');
      final coldDiscoverLocal = coldP2P.discoverLocalPeerCallCount;
      expect(coldDiscoverLocal, 1, reason: 'cold send pays local discovery');

      // Sticky run: learned == 'direct'. The direct leg is WIN-eligible
      // immediately and is decisive (isLearnedWin), so direct commits without
      // ever depending on the local leg — and the learned transport delivers.
      final stickyP2P = FakeP2PService()
        ..discoverLocalPeerResult = false
        ..lastKnownGoodTransportResult = 'direct';

      final (result, message) = await sendChatMessage(
        p2pService: stickyP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Sticky direct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'direct');
      expect(stickyP2P.discoverCallCount, 1);
      expect(stickyP2P.dialCallCount, 1);
      // Sticky 'direct' wins immediately on the learned leg — the local leg's
      // win-eligibility is gated, so the learned transport is honored without
      // burning a SECOND discovery beyond the cold baseline.
      expect(stickyP2P.discoverCallCount, lessThanOrEqualTo(coldDiscoverLocal));
    });

    // U2 (write half) — the LIVE transport that delivered is RECORDED so the
    // next send can be weighted toward it. Proves the memory layer is written
    // on a successful live (acked) delivery.
    test('U2 sticky write: a delivered live send records its transport',
        () async {
      p2pService = FakeP2PService(sendMessageTransport: 'direct');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Record me',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
      expect(p2pService.recordSuccessfulTransportCallCount, 1);
      expect(p2pService.lastRecordedTransport, 'direct');
      expect(p2pService.lastRecordedTransportPeerId, 'target-peer');
    });

    // U-N2 — sticky NEGATIVE control (a): the learned transport FAILS. The full
    // race must still run and deliver — the head-start gates win-eligibility
    // only, never the leg's work, so a dead learned leg can never trap the
    // send. Here learned == 'direct' but the direct leg fails (discover miss);
    // the local leg becomes eligible after the head-start and delivers.
    test('U-N2 sticky neg: learned transport fails → full race still delivers',
        () async {
      p2pService = FakeP2PService(useNullDiscover: true) // direct leg fails
        ..localPeers.add('target-peer') // local can carry it
        ..lastKnownGoodTransportResult = 'direct';

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Dead learned leg',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // The learned (direct) leg failed; the surviving local leg delivered.
      expect(message!.transport, 'local');
      expect(p2pService.localSendCallCount, 1);
    });

    // U-N2 — sticky NEGATIVE control (b): a fake that reports NO learned
    // transport (the production behavior for an expired/stale preference, which
    // returns null) runs the FULL cold race — discover fires exactly once. This
    // pins that a null/ignored preference does not change the race shape.
    test('U-N2 sticky neg: absent/expired preference runs the full cold race',
        () async {
      p2pService = FakeP2PService(); // lastKnownGoodTransportResult == null
      expect(p2pService.lastKnownGoodTransport('target-peer'), isNull);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Stale ignored',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // Full race ran exactly as a cold send would.
      expect(p2pService.discoverCallCount, 1);
    });

    // U3 — concurrent durable fallback (happy): a LOW-confidence send (peer not
    // connected/local AND a recent prior outgoing attempt terminally failed)
    // fires the inbox copy CONCURRENTLY with the live race. Assert BOTH fired:
    // the live send (sendCallCount == 1) AND the concurrent inbox
    // (storeInInboxCallCount == 1). The live send wins the label here.
    test('U3 concurrent: low-confidence send fires inbox AND live in parallel',
        () async {
      p2pService = FakeP2PService(); // direct live send succeeds with ack
      messageRepo.latestMessageForContact = ConversationMessage(
        id: 'prior-attempt-id',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Earlier failed message',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        status: 'failed', // terminal failure → low confidence
        isIncoming: false,
        createdAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 5))
            .toIso8601String(),
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Low-confidence retry',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // BOTH paths fired: the concurrent durable copy AND the live send.
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.sendCallCount, 1);
      // The live race won the transport label (concurrent inbox is a durability
      // side-effect, not the label).
      expect(message!.transport, 'direct');
    });

    // U-N3 — concurrent NEGATIVE control: a HIGH-confidence send (no prior
    // failed/inbox attempt) does NOT fire the inbox. Proves the change is not a
    // blanket dual-write of every send (acceptance #5). The live send succeeds
    // with no inbox call at all.
    test('U-N3 concurrent neg: high-confidence send does NOT fire inbox',
        () async {
      p2pService = FakeP2PService();
      // No prior attempt → high confidence.
      expect(messageRepo.latestMessageForContact, isNull);

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'High-confidence send',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
      expect(message.transport, 'direct');
      // Strictly single-path: no concurrent inbox.
      expect(p2pService.storeInInboxCallCount, 0);
    });

    // U-N3 (gate detail) — a prior attempt that is STALE (older than the 30s
    // low-confidence window) stays high-confidence: no concurrent inbox. Proves
    // the recency gate, not merely the presence of a failed prior attempt.
    test('U-N3 concurrent neg: stale prior failure stays high-confidence',
        () async {
      p2pService = FakeP2PService();
      messageRepo.latestMessageForContact = ConversationMessage(
        id: 'old-attempt-id',
        contactPeerId: 'target-peer',
        senderPeerId: 'my-peer',
        text: 'Ancient failed message',
        timestamp: '2020-01-01T00:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        // Well outside kLowConfidenceWindow (30s).
        createdAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Send after an old failure',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.transport, 'direct');
      // Stale prior failure → still single-path.
      expect(p2pService.storeInInboxCallCount, 0);
    });

    // U4 — dedup (happy): the same messageId winning on more than one path
    // persists exactly ONE outgoing row. Local + direct both succeed for the
    // same id; only one message is saved.
    test('U4 dedup: same messageId across paths persists exactly one row',
        () async {
      p2pService = FakeP2PService()..localPeers.add('target-peer');
      const fixedId = 'msg-nr05-dedup-001';

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Dedup one row',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: fixedId,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(messageRepo.saved, hasLength(1));
      expect(messageRepo.saved.single.id, fixedId);
    });

    // U-N4 — dedup NEGATIVE control: two DIFFERENT messageIds persist TWO rows.
    // Proves the single-row behavior is keyed on identity, not swallowing
    // distinct messages.
    test('U-N4 dedup neg: two different messageIds persist two rows', () async {
      p2pService = FakeP2PService();

      final (r1, m1) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'First distinct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-nr05-distinct-A',
      );
      final (r2, m2) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Second distinct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-nr05-distinct-B',
      );

      expect(r1, SendChatMessageResult.success);
      expect(r2, SendChatMessageResult.success);
      expect(messageRepo.saved, hasLength(2));
      expect(
        messageRepo.saved.map((m) => m.id),
        containsAll(<String>['msg-nr05-distinct-A', 'msg-nr05-distinct-B']),
      );
      expect(m1!.id, isNot(m2!.id));
    });

    // U5 — worst-case timeline (offline peer): discover misses, the relay probe
    // returns NO_RESERVATION (peer offline), so the tail goes STRAIGHT to inbox
    // and durable custody is taken. Assert the bounded sequential tail: probe
    // fired once, NO post-probe live send (NO_RESERVATION short-circuits), and
    // inbox took custody → delivered.
    test('U5 worst-case: offline peer → NO_RESERVATION → durable inbox custody',
        () async {
      p2pService = FakeP2PService(
        useNullDiscover: true, // direct leg: peer_not_found (relay-eligible)
        storeInInboxResult: true, // inbox accepts custody
      );
      p2pService.probeRelayResult = RelayProbeResult.noReservation;

      final sw = Stopwatch()..start();
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Offline peer durable',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(message.transport, 'inbox');
      // Probe ran once and detected offline; no post-probe live send fired
      // (NO_RESERVATION skips the relay send loop straight to inbox).
      expect(p2pService.probeRelayCallCount, 1);
      expect(p2pService.sendCallCount, 0);
      // Inbox took custody exactly once.
      expect(p2pService.storeInInboxCallCount, 1);
      // The whole offline path stays comfortably bounded.
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    // U5 — budget ENFORCEMENT (negative control): a deliberately slow local leg
    // (overruns the 1500ms interactiveLocalBudget) must be CUT at its budget,
    // not allowed to run to completion. The fast direct leg carries the
    // message, and the local timeout is the budget — proving the cutoff fires,
    // not luck. Patterned after the lastLocalSendTimeoutMs assertion.
    test('U5 budget: a slow local leg is cut at the local budget', () async {
      p2pService = FakeP2PService()
        ..localPeers.add('target-peer')
        // Local send overruns the 1500ms budget by a wide margin.
        ..localSendDelay = const Duration(seconds: 5);

      final sw = Stopwatch()..start();
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Slow local cut at budget',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      sw.stop();

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // The over-budget local leg lost — direct carried it.
      expect(message!.transport, 'direct');
      // The local leg was invoked with the local budget as its timeout
      // (enforced cutoff), and the overall send did NOT wait out the 5s local
      // send (it is cut well before that).
      expect(
        p2pService.lastLocalSendTimeoutMs,
        interactiveLocalBudget.inMilliseconds,
      );
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
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
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => throw Exception('Inbox store exploded');

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
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async =>
      false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

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
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

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
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async =>
      false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

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
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

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
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async =>
      false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

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
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

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
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async =>
      true;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

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
