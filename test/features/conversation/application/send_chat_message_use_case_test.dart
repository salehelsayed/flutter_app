import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../core/bridge/fake_bridge.dart';

// -- Fake P2P Service --
class FakeP2PService implements P2PService {
  NodeState _currentState;
  bool sendMessageResult;
  String? sendMessageReply;
  bool shouldThrow;
  bool storeInInboxResult;

  DiscoveredPeer? discoverPeerResult;
  bool dialPeerResult;

  int discoverCallCount = 0;
  int dialCallCount = 0;
  int sendCallCount = 0;
  int storeInInboxCallCount = 0;

  String? lastSentPeerId;
  String? lastSentMessage;
  String? lastInboxPeerId;
  String? lastInboxMessage;

  // Connected peer support (fast path)
  bool Function(String)? isConnectedToPeerFn;

  // Local peer support
  final Set<String> localPeers = {};
  bool localSendResult = true;
  int localSendCallCount = 0;

  /// Use [useNullDiscover] to explicitly request null discoverPeer results.
  FakeP2PService({
    NodeState? currentState,
    this.sendMessageResult = true,
    this.sendMessageReply = 'received: ok',
    this.shouldThrow = false,
    this.storeInInboxResult = false,
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
    sendCallCount++;
    return SendMessageResult(sent: sendMessageResult, reply: sendMessageReply);
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverCallCount++;
    if (shouldThrow && discoverCallCount == 1) {
      throw Exception('Discover failed');
    }
    return discoverPeerResult;
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
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
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) =>
      isConnectedToPeerFn?.call(peerId) ?? false;

  @override
  bool isLocalPeer(String peerId) => localPeers.contains(peerId);

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async {
    localSendCallCount++;
    lastSentPeerId = peerId;
    lastSentMessage = message;
    return localSendResult;
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
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;

  @override
  Future<void> warmBackground() async {}

  @override
  void dispose() {}
}

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> saved = [];

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
}

// -- Fake Media Attachment Repository --
class FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> saved = [];

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    saved.add(attachment);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
      String messageId) async {
    return saved.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
      List<String> messageIds) async {
    final map = <String, List<MediaAttachment>>{};
    for (final a in saved) {
      if (messageIds.contains(a.messageId)) {
        map.putIfAbsent(a.messageId, () => []).add(a);
      }
    }
    return map;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];
}

Future<List<String>> capturePrintedLines(Future<void> Function() action) async {
  final printed = <String>[];
  // Override debugPrint to bypass throttling which can cause lines to be
  // delivered asynchronously after the zone completes.
  final origDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) printed.add(message);
  };
  try {
    await runZoned(
      action,
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) {
          printed.add(line);
        },
      ),
    );
  } finally {
    debugPrint = origDebugPrint;
  }
  return printed;
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeBridge defaultEncryptBridge;
  const defaultMlKemKey = 'test-recipient-mlkem-pub-key';

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    defaultEncryptBridge = FakeBridge(initialResponses: {
      'message.encrypt': {
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': 'fake-ct',
        'nonce': 'fake-nonce',
      },
    });
  });

  group('sendChatMessage', () {
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

    test('returns messageTooLong for text exceeding 10000 chars', () async {
      final longText = 'a' * 10001;
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: longText,
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.messageTooLong);
      expect(message, isNull);
      expect(messageRepo.saved, isEmpty);
    });

    test('succeeds for text at exactly 10000 chars', () async {
      final exactText = 'a' * 10000;
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: exactText,
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
    });

    test('strips bidi characters from outgoing text', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello\u200Bworld\u202A!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(messageRepo.saved.length, 1);
      expect(messageRepo.saved.first.text, 'Helloworld!');
    });

    test('strips bidi characters from outgoing senderUsername', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello',
        senderPeerId: 'my-peer',
        senderUsername: 'Me\u200B',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      // With V2 encryption, inner payload is encrypted — verify via bridge call
      final bridgeReq = jsonDecode(defaultEncryptBridge.lastSentMessage!) as Map<String, dynamic>;
      final plaintext = bridgeReq['payload']?['plaintext'] as String? ?? '';
      expect(plaintext, contains('"senderUsername":"Me"'));
      expect(plaintext, isNot(contains('\u200B')));
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
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
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

    test('sends correct V2 JSON envelope via P2P', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(p2pService.lastSentPeerId, 'target-peer');
      expect(p2pService.lastSentMessage, isNotNull);
      final wireJson =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      expect(wireJson['type'], 'chat_message');
      expect(wireJson['version'], '2');
      expect(wireJson['senderPeerId'], 'my-peer');
      expect(wireJson['encrypted'], isNotNull);
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
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.id, fixedMessageId);
      expect(message.timestamp, fixedTimestamp);
      expect(messageRepo.saved.first.id, fixedMessageId);
      expect(messageRepo.saved.first.timestamp, fixedTimestamp);
      // V2 envelope — inner payload is encrypted, check persisted message
      final wireJson =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      expect(wireJson['version'], '2');
      expect(wireJson['encrypted'], isNotNull);
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
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
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
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
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
          text: 'Hello inbox!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'delivered');
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastInboxPeerId, 'target-peer');
        expect(p2pService.lastInboxMessage, isNotNull);
        final wireJson =
            jsonDecode(p2pService.lastInboxMessage!) as Map<String, dynamic>;
        expect(wireJson['type'], 'chat_message');
        expect(wireJson['version'], '2');
      },
    );

    test('returns sendFailed when P2P throws exception', () async {
      final customP2P = _ThrowOnSendP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: customP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.sendFailed);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
    });

    test(
      'returns peerNotFound when discover returns null after 1 attempt',
      () async {
        p2pService = FakeP2PService(useNullDiscover: true);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.peerNotFound);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(p2pService.discoverCallCount, 1);
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'failed');
      },
    );

    test(
      'returns dialFailed when dial returns false after 1 attempt',
      () async {
        p2pService = FakeP2PService(dialPeerResult: false);

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.dialFailed);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(p2pService.dialCallCount, 1);
        expect(messageRepo.saved.length, 1);
      },
    );

    test('flaky discover falls through to inbox with 1 attempt', () async {
      // With maxAttempts=1, discover fails on attempt 1 → inbox fallback
      final flakyP2P = _FlakyDiscoverP2PService(storeInInboxResult: true);

      final (result, message) = await sendChatMessage(
        p2pService: flakyP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(message.transport, 'inbox');
      expect(flakyP2P.discoverCallCount, 1);
    });

    test('success with ack sets status to delivered', () async {
      p2pService = FakeP2PService(sendMessageReply: 'received: ok');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
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
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'sent');
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
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'sent');
    });

    test('sends locally when peer is on local WiFi', () async {
      p2pService.localPeers.add('target-peer');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello local!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'delivered');
      expect(message.transport, 'wifi');
      expect(p2pService.localSendCallCount, 1);
      // Dual-path: relay also attempted for confirmation
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.sendCallCount, 1);
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
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
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

    test('skips local send when peer is not on local WiFi', () async {
      // localPeers is empty by default
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello relay!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      // No local send attempted
      expect(p2pService.localSendCallCount, 0);
      // Relay path used directly
      expect(p2pService.discoverCallCount, 1);
      expect(p2pService.sendCallCount, 1);
    });

    test('quotedMessageId is persisted in saved message', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'This is a reply',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        quotedMessageId: 'original-msg-001',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.quotedMessageId, 'original-msg-001');
      expect(messageRepo.saved.first.quotedMessageId, 'original-msg-001');
    });

    test('quotedMessageId included in encrypted inner payload', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Reply text',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        quotedMessageId: 'quoted-123',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      // V2 envelope — inner payload is encrypted, verify via bridge plaintext
      final bridgeReq = jsonDecode(defaultEncryptBridge.lastSentMessage!) as Map<String, dynamic>;
      final plaintext = bridgeReq['payload']?['plaintext'] as String? ?? '';
      expect(plaintext, contains('"quotedMessageId":"quoted-123"'));
    });

    test('quotedMessageId is null when not provided', () async {
      final (_, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Normal message',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        bridge: defaultEncryptBridge,
        recipientMlKemPublicKey: defaultMlKemKey,
      );

      expect(message, isNotNull);
      expect(message!.quotedMessageId, isNull);
      // V2 envelope — inner payload is encrypted, verify via bridge plaintext
      final bridgeReq = jsonDecode(defaultEncryptBridge.lastSentMessage!) as Map<String, dynamic>;
      final plaintext = bridgeReq['payload']?['plaintext'] as String? ?? '';
      expect(plaintext, isNot(contains('quotedMessageId')));
    });

    group('media attachments', () {
      late FakeMediaAttachmentRepository mediaRepo;

      final testMedia = [
        const MediaAttachment(
          id: 'blob-001',
          messageId: '',
          mime: 'image/jpeg',
          size: 245000,
          mediaType: 'image',
          width: 1920,
          height: 1080,
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
        const MediaAttachment(
          id: 'blob-002',
          messageId: '',
          mime: 'audio/mp3',
          size: 50000,
          mediaType: 'audio',
          durationMs: 30000,
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:00:01.000Z',
        ),
      ];

      setUp(() {
        mediaRepo = FakeMediaAttachmentRepository();
      });

      test('allows empty text when media is attached', () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.text, '');
      });

      test('still rejects empty text without media', () async {
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: null,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendChatMessageResult.invalidMessage);
      });

      test('rejects empty text with empty media list', () async {
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: '',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: [],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendChatMessageResult.invalidMessage);
      });

      test('includes media array in encrypted inner payload', () async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'With image',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        // V2: inner payload is encrypted — verify via bridge plaintext
        final bridgeReq = jsonDecode(defaultEncryptBridge.lastSentMessage!) as Map<String, dynamic>;
        final plaintext = bridgeReq['payload']?['plaintext'] as String? ?? '';
        expect(plaintext, contains('"media"'));
        expect(plaintext, contains('"blob-001"'));
        expect(plaintext, contains('"blob-002"'));
        expect(plaintext, contains('"image/jpeg"'));
      });

      test('omits media from encrypted inner payload when null', () async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'No media',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        // V2: verify inner payload has no media via bridge plaintext
        final bridgeReq = jsonDecode(defaultEncryptBridge.lastSentMessage!) as Map<String, dynamic>;
        final plaintext = bridgeReq['payload']?['plaintext'] as String? ?? '';
        expect(plaintext, isNot(contains('"media"')));
      });

      test('persists media attachments with correct messageId on success',
          () async {
        const fixedId = 'msg-fixed-media-001';

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'With media',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(mediaRepo.saved.length, 2);
        expect(mediaRepo.saved[0].id, 'blob-001');
        expect(mediaRepo.saved[0].messageId, fixedId);
        expect(mediaRepo.saved[1].id, 'blob-002');
        expect(mediaRepo.saved[1].messageId, fixedId);
      });

      test('persists media attachments on inbox fallback', () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;
        const fixedId = 'msg-inbox-media';

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox with media',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(mediaRepo.saved.length, 2);
        expect(mediaRepo.saved[0].messageId, fixedId);
        expect(mediaRepo.saved[1].messageId, fixedId);
      });

      test('persists media attachments even on failure', () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = false;
        const fixedId = 'msg-failed-media';

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Failed with media',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.sendFailed);
        expect(mediaRepo.saved.length, 2);
        expect(mediaRepo.saved[0].messageId, fixedId);
      });

      test('does not persist media when repo is null', () async {
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Media but no repo',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: testMedia,
          mediaAttachmentRepo: null,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        // No crash, no media saved
      });

      test('does not persist when media list is empty', () async {
        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Empty media',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: [],
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(mediaRepo.saved, isEmpty);
      });
    });

    group('transport tagging', () {
      test('local WiFi success sets transport to wifi', () async {
        p2pService.localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'WiFi transport',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'wifi');
        expect(messageRepo.saved.last.transport, 'wifi');
      });

      test('fast path success sets transport to relay', () async {
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Relay fast path',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'relay');
        expect(messageRepo.saved.first.transport, 'relay');
      });

      test('discover-dial-send success sets transport to relay', () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Relay discover',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'relay');
        expect(messageRepo.saved.first.transport, 'relay');
      });

      test('inbox fallback success sets transport to inbox', () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox transport',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'inbox');
        expect(messageRepo.saved.first.transport, 'inbox');
      });

      test('failed message has null transport', () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = false;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Failed transport',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.sendFailed);
        expect(message!.transport, isNull);
        expect(messageRepo.saved.first.transport, isNull);
      });
    });

    group('fast path (connected peer)', () {
      test('connected peer with ACK → delivered, 0 discover, 0 dial, 1 send',
          () async {
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'delivered');
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.sendCallCount, 1);
      });

      test('connected peer without ACK → sent, 0 discover, 0 dial', () async {
        p2pService = FakeP2PService(sendMessageReply: null);
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast no ack!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'sent');
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(p2pService.sendCallCount, 1);
      });

      test('fast path send fails → falls through to discover-dial-send',
          () async {
        final custom = _FastPathFailThenSucceedP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: custom,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Retry hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        // 1 fast path + 1 retry = 2 sends
        expect(custom.sendCallCount, 2);
        expect(custom.discoverCallCount, 1);
        expect(custom.dialCallCount, 1);
      });

      test('fast path send throws → falls through to discover-dial-send',
          () async {
        final custom = _FastPathThrowThenSucceedP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: custom,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Throw then retry!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(custom.sendCallCount, 2);
        expect(custom.discoverCallCount, 1);
        expect(custom.dialCallCount, 1);
      });

      test(
          'fast path fails + all retries fail → inbox fallback, 2 total sends',
          () async {
        final custom = _AllFailButInboxP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: custom,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox fallback!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        // 1 fast path + 1 retry = 2 sends
        expect(custom.sendCallCount, 2);
      });

      test('not connected → skips fast path, normal discover-dial-send',
          () async {
        // Default FakeP2PService has isConnectedToPeer => false
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Normal path!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
        expect(p2pService.sendCallCount, 1);
      });

      test('local WiFi succeeds → falls through to fast path for confirmation',
          () async {
        p2pService.localPeers.add('target-peer');
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Local wins!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'wifi');
        expect(p2pService.localSendCallCount, 1);
        // Dual-path: fast path used for confirmation
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
      });

      test('local WiFi fails + peer connected → fast path succeeds',
          () async {
        p2pService.localPeers.add('target-peer');
        p2pService.localSendResult = false;
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast after local!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(p2pService.localSendCallCount, 1);
        // Fast path used, no discover/dial
        expect(p2pService.sendCallCount, 1);
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
      });

      test('fast path success emits flow events', () async {
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final lines = await capturePrintedLines(() async {
          await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Flow event test',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );
        });

        expect(
          lines.any((l) => l.contains('CHAT_MSG_SEND_FAST_PATH_ATTEMPT')),
          isTrue,
        );
        expect(
          lines.any((l) => l.contains('CHAT_MSG_SEND_FAST_PATH_SUCCESS')),
          isTrue,
        );
      });

      test('fast path failure emits flow events', () async {
        final custom = _FastPathFailThenSucceedP2PService();

        final lines = await capturePrintedLines(() async {
          await sendChatMessage(
            p2pService: custom,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Flow fail test',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );
        });

        expect(
          lines.any((l) => l.contains('CHAT_MSG_SEND_FAST_PATH_ATTEMPT')),
          isTrue,
        );
        expect(
          lines.any((l) => l.contains('CHAT_MSG_SEND_FAST_PATH_FAILED')),
          isTrue,
        );
      });

      test('connected peer with media → media persisted via fast path',
          () async {
        final mediaRepo = FakeMediaAttachmentRepository();
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        const fixedId = 'msg-fast-media';
        final testMedia = [
          const MediaAttachment(
            id: 'blob-fast-001',
            messageId: '',
            mime: 'image/png',
            size: 100000,
            mediaType: 'image',
            width: 800,
            height: 600,
            downloadStatus: 'done',
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
        ];

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast with media!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(p2pService.discoverCallCount, 0);
        expect(p2pService.dialCallCount, 0);
        expect(mediaRepo.saved.length, 1);
        expect(mediaRepo.saved[0].id, 'blob-fast-001');
        expect(mediaRepo.saved[0].messageId, fixedId);
      });

    });

    group('dual-path WiFi + relay', () {
      test('WiFi success + relay ACK → delivered via wifi', () async {
        p2pService.localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Dual path test',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'wifi');
        expect(p2pService.localSendCallCount, 1);
        // Relay also attempted for confirmation
        expect(p2pService.sendCallCount, greaterThan(0));
      });

      test('WiFi success + relay no-ACK → sent via wifi', () async {
        p2pService = FakeP2PService(sendMessageReply: null);
        p2pService.localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'No ACK test',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'sent');
        expect(message.transport, 'wifi');
      });

      test('WiFi success + relay fail 3x + inbox → delivered via inbox',
          () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          storeInInboxResult: true,
        );
        p2pService.localPeers.add('target-peer');
        p2pService.localSendResult = true;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox fallback test',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'inbox');
      });

      test('WiFi success + all fallbacks fail → sent via wifi', () async {
        p2pService = FakeP2PService(
          sendMessageResult: false,
          storeInInboxResult: false,
        );
        p2pService.localPeers.add('target-peer');
        p2pService.localSendResult = true;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'All fail test',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'sent');
        expect(message.transport, 'wifi');
      });

      test('WiFi throws exception → falls through to relay cleanly',
          () async {
        final customP2P = _ThrowOnLocalSendP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: customP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'WiFi error test',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'relay');
        expect(customP2P.localSendCallCount, 1);
        expect(customP2P.discoverCallCount, 1);
      });

      test('WiFi success + fast path ACK → delivered via wifi', () async {
        p2pService.localPeers.add('target-peer');
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Fast path after WiFi',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'wifi');
        expect(p2pService.localSendCallCount, 1);
        expect(p2pService.sendCallCount, 1); // fast path
        expect(p2pService.discoverCallCount, 0);
      });

      test('WiFi success + fast fail + discover ACK → delivered via wifi',
          () async {
        final customP2P = _WiFiThenFastFailThenRelayP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: customP2P,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'WiFi then relay',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(message.transport, 'wifi');
        expect(customP2P.localSendCallCount, 1);
        expect(customP2P.sendCallCount, 2); // fast + discover-dial
        expect(customP2P.discoverCallCount, 1);
      });
    });

    group('WiFi persistence-failure regression', () {
      test(
        'WiFi send succeeds but saveMessage throws — relay fallback persists message',
        () async {
          // Setup: Bob is a local peer, local send succeeds, relay also succeeds
          final throwingRepo = _ThrowOnSaveMessageRepository(throwCount: 1);
          p2pService.localPeers.add('target-peer');

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: throwingRepo,
            targetPeerId: 'target-peer',
            text: 'WiFi save fails once',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );

          // WiFi send succeeded, saveMessage threw on 1st call,
          // wifiSent stays false, relay fallback persisted on 2nd call.
          expect(result, SendChatMessageResult.success);
          expect(message, isNotNull);
          expect(throwingRepo.saveAttemptCount, 2);
          expect(throwingRepo.saved.length, 1);
          expect(throwingRepo.saved.first.transport, 'relay');
        },
      );

      test(
        'WiFi send succeeds but saveMessage always throws — returns sendFailed with null message',
        () async {
          // Setup: WiFi succeeds but every saveMessage call throws.
          // Relay send also fails so we go through all fallbacks.
          final throwingRepo = _ThrowOnSaveMessageRepository(throwCount: 999);
          p2pService = FakeP2PService(
            sendMessageResult: false,
            storeInInboxResult: false,
          );
          p2pService.localPeers.add('target-peer');
          p2pService.localSendResult = true;

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: throwingRepo,
            targetPeerId: 'target-peer',
            text: 'WiFi save always fails',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );

          // After fix: wifiSent stays false because saveMessage throws before
          // the flag is set. All relay/inbox paths fail. The final "persist
          // with failed status" block also throws, caught by the new try-catch,
          // which returns (sendFailed, null).
          expect(result, SendChatMessageResult.sendFailed);
          expect(message, isNull);
          expect(throwingRepo.saved, isEmpty);
        },
      );

      test(
        'WiFi send succeeds but saveMessage throws — media attachments saved by relay fallback',
        () async {
          final throwingRepo = _ThrowOnSaveMessageRepository(throwCount: 1);
          final mediaRepo = FakeMediaAttachmentRepository();
          p2pService.localPeers.add('target-peer');

          const fixedId = 'msg-wifi-media-recovered';
          final testMedia = [
            const MediaAttachment(
              id: 'blob-wifi-001',
              messageId: '',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              width: 1920,
              height: 1080,
              downloadStatus: 'done',
              createdAt: '2026-02-20T10:00:00.000Z',
            ),
          ];

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: throwingRepo,
            targetPeerId: 'target-peer',
            text: 'WiFi media recovered',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: fixedId,
            mediaAttachments: testMedia,
            mediaAttachmentRepo: mediaRepo,
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );

          // After fix: wifiSent stays false because saveMessage throws before
          // the flag is set. Relay path succeeds on 2nd saveMessage call,
          // and since wifiSent is false, media attachments are persisted.
          expect(result, SendChatMessageResult.success);
          expect(message, isNotNull);
          expect(throwingRepo.saved.length, 1);
          expect(mediaRepo.saved.length, 1,
              reason: 'Media attachments are now saved by the relay fallback '
                  'because wifiSent stays false when WiFi persistence fails');
          expect(mediaRepo.saved.first.messageId, fixedId);
        },
      );

      test(
        'WiFi saveMessage throws — relay saves with relay transport',
        () async {
          // throwCount: 1 so WiFi persistence fails, relay succeeds
          final throwingRepo = _ThrowOnSaveMessageRepository(throwCount: 1);
          p2pService.localPeers.add('target-peer');

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: throwingRepo,
            targetPeerId: 'target-peer',
            text: 'WiFi fail relay saves',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );

          expect(result, SendChatMessageResult.success);
          expect(message, isNotNull);
          expect(message!.transport, 'relay');
          expect(throwingRepo.saved.length, 1);
          expect(throwingRepo.saved.first.transport, 'relay');
        },
      );

      test(
        'all paths fail + final persist throws — returns sendFailed with null',
        () async {
          // No WiFi peer, relay fails, inbox fails, saveMessage always throws
          final throwingRepo = _ThrowOnSaveMessageRepository(throwCount: 999);
          p2pService = FakeP2PService(
            sendMessageResult: false,
            storeInInboxResult: false,
          );

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: throwingRepo,
            targetPeerId: 'target-peer',
            text: 'Everything fails',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );

          // Relay send fails 3x, inbox fails, final persist throws →
          // new try-catch returns (sendFailed, null).
          expect(result, SendChatMessageResult.sendFailed);
          expect(message, isNull);
          expect(throwingRepo.saved, isEmpty);
        },
      );

      test(
        'WiFi success with media — media persisted once, not duplicated by relay',
        () async {
          final mediaRepo = FakeMediaAttachmentRepository();
          p2pService.localPeers.add('target-peer');

          const fixedId = 'msg-wifi-media-happy';
          final testMedia = [
            const MediaAttachment(
              id: 'blob-happy-001',
              messageId: '',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              width: 1920,
              height: 1080,
              downloadStatus: 'done',
              createdAt: '2026-02-20T10:00:00.000Z',
            ),
          ];

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'WiFi media happy path',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            messageId: fixedId,
            mediaAttachments: testMedia,
            mediaAttachmentRepo: mediaRepo,
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: defaultMlKemKey,
          );

          expect(result, SendChatMessageResult.success);
          expect(message, isNotNull);
          // Media persisted exactly once (by WiFi path), not duplicated by relay
          expect(mediaRepo.saved.length, 1,
              reason: 'Media should be persisted once by WiFi path, '
                  'relay path skips because wifiSent is true');
          expect(mediaRepo.saved.first.id, 'blob-happy-001');
          expect(mediaRepo.saved.first.messageId, fixedId);
        },
      );
    });

    group('v2 encryption (ML-KEM)', () {
      test(
        'encrypts and sends v2 envelope when bridge and ML-KEM key provided',
        () async {
          final bridge = FakeBridge(initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'fake-kem-base64',
              'ciphertext': 'fake-ciphertext-base64',
              'nonce': 'fake-nonce-base64',
            },
          });

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Encrypted hello!',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: bridge,
            recipientMlKemPublicKey: 'recipient-mlkem-pub-key',
          );

          expect(result, SendChatMessageResult.success);
          expect(message, isNotNull);
          expect(message!.text, 'Encrypted hello!');

          // Verify wire JSON is v2 encrypted envelope
          final wireJson =
              jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
          expect(wireJson['type'], 'chat_message');
          expect(wireJson['version'], '2');
          expect(wireJson['senderPeerId'], 'my-peer');
          expect(wireJson['encrypted'], isNotNull);
          final encrypted =
              wireJson['encrypted'] as Map<String, dynamic>;
          expect(encrypted['kem'], 'fake-kem-base64');
          expect(encrypted['ciphertext'], 'fake-ciphertext-base64');
          expect(encrypted['nonce'], 'fake-nonce-base64');
          // v2 envelope must NOT have a payload key
          expect(wireJson.containsKey('payload'), isFalse);
        },
      );

      test(
        'returns sendFailed with null message when encrypt returns ok=false',
        () async {
          final bridge = FakeBridge(initialResponses: {
            'message.encrypt': {
              'ok': false,
              'errorCode': 'ENCRYPT_FAILED',
              'errorMessage': 'bad key',
            },
          });

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Will fail encrypt',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: bridge,
            recipientMlKemPublicKey: 'bad-key',
          );

          expect(result, SendChatMessageResult.sendFailed);
          expect(message, isNull);
          expect(messageRepo.saved, isEmpty);
          expect(p2pService.sendCallCount, 0);
        },
      );

      test(
        'returns sendFailed with null message when encrypt throws exception',
        () async {
          final bridge = FakeBridge();
          bridge.throwOnSend = true;
          bridge.throwOnSendMessage = 'Encrypt kaboom';

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Will throw on encrypt',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: bridge,
            recipientMlKemPublicKey: 'some-key',
          );

          expect(result, SendChatMessageResult.sendFailed);
          expect(message, isNull);
          expect(messageRepo.saved, isEmpty);
        },
      );

      test(
        'returns encryptionRequired when bridge is null',
        () async {
          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'No bridge',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: null,
            recipientMlKemPublicKey: 'some-mlkem-key',
          );

          expect(result, SendChatMessageResult.encryptionRequired);
          expect(message, isNull);
          expect(messageRepo.saved, isEmpty);
          expect(p2pService.sendCallCount, 0);
        },
      );

      test(
        'returns encryptionRequired when recipientMlKemPublicKey is null',
        () async {
          final bridge = FakeBridge();

          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'No mlkem key',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: bridge,
            recipientMlKemPublicKey: null,
          );

          expect(result, SendChatMessageResult.encryptionRequired);
          expect(message, isNull);
          expect(messageRepo.saved, isEmpty);
          expect(bridge.sendCallCount, 0);
        },
      );

      test(
        'emits CHAT_MSG_SEND_ENCRYPT_FAILED flow event on ok=false',
        () async {
          final bridge = FakeBridge(initialResponses: {
            'message.encrypt': {
              'ok': false,
              'errorCode': 'BAD_KEY',
              'errorMessage': 'invalid public key',
            },
          });

          final lines = await capturePrintedLines(() async {
            await sendChatMessage(
              p2pService: p2pService,
              messageRepo: messageRepo,
              targetPeerId: 'target-peer',
              text: 'Encrypt fail flow',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              bridge: bridge,
              recipientMlKemPublicKey: 'bad-key',
            );
          });

          expect(
            lines.any((line) => line.contains('CHAT_MSG_SEND_ENCRYPT_FAILED')),
            isTrue,
          );
        },
      );

      test(
        'emits CHAT_MSG_SEND_ENCRYPT_ERROR flow event on exception',
        () async {
          final bridge = FakeBridge();
          bridge.throwOnSend = true;
          bridge.throwOnSendMessage = 'bridge crash';

          final lines = await capturePrintedLines(() async {
            await sendChatMessage(
              p2pService: p2pService,
              messageRepo: messageRepo,
              targetPeerId: 'target-peer',
              text: 'Encrypt error flow',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              bridge: bridge,
              recipientMlKemPublicKey: 'some-key',
            );
          });

          expect(
            lines.any((line) => line.contains('CHAT_MSG_SEND_ENCRYPT_ERROR')),
            isTrue,
          );
        },
      );
    });

    group('V2 enforcement', () {
      test('returns encryptionRequired when recipientMlKemPublicKey is null',
          () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: null,
        );

        expect(result, SendChatMessageResult.encryptionRequired);
        expect(message, isNull);
        expect(messageRepo.saved, isEmpty);
        expect(p2pService.sendCallCount, 0);
      });

      test('returns encryptionRequired when bridge is null', () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: null,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.encryptionRequired);
        expect(message, isNull);
        expect(messageRepo.saved, isEmpty);
        expect(p2pService.sendCallCount, 0);
      });

      test('returns encryptionRequired when both bridge and key are null',
          () async {
        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: null,
          recipientMlKemPublicKey: null,
        );

        expect(result, SendChatMessageResult.encryptionRequired);
        expect(message, isNull);
        expect(messageRepo.saved, isEmpty);
      });

      test('emits CHAT_MSG_SEND_ENCRYPTION_REQUIRED flow event when key missing',
          () async {
        final lines = await capturePrintedLines(() async {
          await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            text: 'Hello!',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            bridge: defaultEncryptBridge,
            recipientMlKemPublicKey: null,
          );
        });

        expect(
          lines.any((l) => l.contains('CHAT_MSG_SEND_ENCRYPTION_REQUIRED')),
          isTrue,
        );
      });

      test('does not persist any message to DB on encryptionRequired',
          () async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Hello!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: null,
          recipientMlKemPublicKey: null,
        );

        expect(messageRepo.saved, isEmpty);
      });

      test('sends V2 encrypted envelope over WiFi path', () async {
        p2pService.localPeers.add('target-peer');

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Encrypted WiFi!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'wifi');
        final wireJson =
            jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
        expect(wireJson['version'], '2');
        expect(wireJson['encrypted'], isNotNull);
      });

      test('sends V2 encrypted envelope via inbox fallback', () async {
        p2pService.sendMessageResult = false;
        p2pService.storeInInboxResult = true;

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Encrypted inbox!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          bridge: defaultEncryptBridge,
          recipientMlKemPublicKey: defaultMlKemKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.transport, 'inbox');
        final wireJson =
            jsonDecode(p2pService.lastInboxMessage!) as Map<String, dynamic>;
        expect(wireJson['version'], '2');
        expect(wireJson['encrypted'], isNotNull);
      });
    });
  });
}

/// P2P service where local WiFi send throws, used for dual-path exception test.
class _ThrowOnLocalSendP2PService extends FakeP2PService {
  _ThrowOnLocalSendP2PService() : super() {
    localPeers.add('target-peer');
  }

  @override
  Future<bool> sendLocalMessage(
      String peerId, String message, String fromPeerId) async {
    localSendCallCount++;
    throw Exception('WiFi socket error');
  }
}

/// P2P service: WiFi succeeds, fast path fails, discover-dial succeeds.
class _WiFiThenFastFailThenRelayP2PService implements P2PService {
  int sendCallCount = 0;
  int discoverCallCount = 0;
  int dialCallCount = 0;
  int localSendCallCount = 0;

  @override
  NodeState get currentState => const NodeState(isStarted: true);
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String id) async => true;
  @override
  Future<bool> startNodeCore(String pk, String id) async => false;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => true;

  @override
  bool isLocalPeer(String peerId) => peerId == 'target-peer';

  @override
  Future<bool> sendLocalMessage(
      String peerId, String message, String fromPeerId) async {
    localSendCallCount++;
    return true;
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
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message, {int? timeoutMs}) async {
    sendCallCount++;
    if (sendCallCount == 1) return const SendMessageResult(sent: false);
    return const SendMessageResult(sent: true, reply: 'ack');
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverCallCount++;
    return const DiscoveredPeer(
        id: 'target-peer', addresses: ['/ip4/127.0.0.1/tcp/4001']);
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
    dialCallCount++;
    return true;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
  @override
  Future<bool> registerPushToken(String token, String platform) async => true;
  @override
  Future<void> performImmediateHealthCheck() async {}
  @override
  Future<void> drainOfflineInbox() async {}
  @override
  void dispose() {}
}

/// P2P service where fast path send fails (sent=false) then retry succeeds.
class _FastPathFailThenSucceedP2PService implements P2PService {
  int sendCallCount = 0;
  int discoverCallCount = 0;
  int dialCallCount = 0;

  @override
  NodeState get currentState => const NodeState(isStarted: true);
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String id) async => true;
  @override
  Future<bool> startNodeCore(String pk, String id) async => false;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message, {int? timeoutMs}) async {
    sendCallCount++;
    if (sendCallCount == 1) return const SendMessageResult(sent: false);
    return const SendMessageResult(sent: true, reply: 'ack');
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverCallCount++;
    return const DiscoveredPeer(
        id: 'target-peer', addresses: ['/ip4/127.0.0.1/tcp/4001']);
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
    dialCallCount++;
    return true;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
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
          String peerId, String message, String fromPeerId) async =>
      false;
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
  void dispose() {}
}

/// P2P service where fast path send throws, then retry succeeds.
class _FastPathThrowThenSucceedP2PService implements P2PService {
  int sendCallCount = 0;
  int discoverCallCount = 0;
  int dialCallCount = 0;

  @override
  NodeState get currentState => const NodeState(isStarted: true);
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String id) async => true;
  @override
  Future<bool> startNodeCore(String pk, String id) async => false;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message, {int? timeoutMs}) async {
    sendCallCount++;
    if (sendCallCount == 1) throw Exception('stream reset');
    return const SendMessageResult(sent: true, reply: 'ack');
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverCallCount++;
    return const DiscoveredPeer(
        id: 'target-peer', addresses: ['/ip4/127.0.0.1/tcp/4001']);
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async {
    dialCallCount++;
    return true;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
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
          String peerId, String message, String fromPeerId) async =>
      false;
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
  void dispose() {}
}

/// P2P service where all sends fail but inbox store succeeds.
class _AllFailButInboxP2PService implements P2PService {
  int sendCallCount = 0;

  @override
  NodeState get currentState => const NodeState(isStarted: true);
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String id) async => true;
  @override
  Future<bool> startNodeCore(String pk, String id) async => false;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message, {int? timeoutMs}) async {
    sendCallCount++;
    return const SendMessageResult(sent: false);
  }

  @override
  Future<bool> sendMessage(String peerId, String message) async => false;
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    return const DiscoveredPeer(
        id: 'target-peer', addresses: ['/ip4/127.0.0.1/tcp/4001']);
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => true;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
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
          String peerId, String message, String fromPeerId) async =>
      false;
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
  Future<DiscoveredPeer?> discoverPeer(String peerId) async =>
      const DiscoveredPeer(
        id: 'target-peer',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;

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
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;

  @override
  Future<void> warmBackground() async {}

  @override
  void dispose() {}
}

/// P2P service where discover fails on first attempt, succeeds on subsequent.
class _FlakyDiscoverP2PService implements P2PService {
  int discoverCallCount = 0;
  int storeInInboxCallCount = 0;
  bool storeInInboxResult;

  _FlakyDiscoverP2PService({this.storeInInboxResult = false});

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
  Future<DiscoveredPeer?> discoverPeer(String peerId) async {
    discoverCallCount++;
    if (discoverCallCount == 1) return null;
    return const DiscoveredPeer(
      id: 'target-peer',
      addresses: ['/ip4/127.0.0.1/tcp/4001'],
    );
  }

  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    storeInInboxCallCount++;
    return storeInInboxResult;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;

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
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;

  @override
  Future<void> warmBackground() async {}

  @override
  void dispose() {}
}

/// Message repository where the first [throwCount] saveMessage calls throw,
/// then subsequent calls succeed normally.
class _ThrowOnSaveMessageRepository extends FakeMessageRepository {
  final int throwCount;
  int saveAttemptCount = 0;

  _ThrowOnSaveMessageRepository({this.throwCount = 1});

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saveAttemptCount++;
    if (saveAttemptCount <= throwCount) {
      throw Exception('DB write failed');
    }
    await super.saveMessage(message);
  }
}
