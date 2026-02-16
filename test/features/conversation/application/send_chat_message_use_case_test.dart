import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

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
    String message,
  ) async {
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
}

Future<List<String>> capturePrintedLines(Future<void> Function() action) async {
  final printed = <String>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) {
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

    test(
      'returns peerNotFound when discover returns null after 3 retries',
      () async {
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
        expect(p2pService.discoverCallCount, 3);
        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.status, 'failed');
      },
    );

    test(
      'returns dialFailed when dial returns false after 3 retries',
      () async {
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
        expect(p2pService.dialCallCount, 3);
        expect(messageRepo.saved.length, 1);
      },
    );

    test('succeeds on 2nd attempt after flaky discover', () async {
      // Custom service where discover fails first time, succeeds second
      final flakyP2P = _FlakyDiscoverP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: flakyP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Hello!',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(flakyP2P.discoverCallCount, 2);
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
    });
  });
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
    String message,
  ) async => throw Exception('Send exploded');

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
    String message,
  ) async => const SendMessageResult(sent: true, reply: 'received: ok');

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
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];

  @override
  void dispose() {}
}
