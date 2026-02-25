import 'dart:async';
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
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

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
      );

      // The payload in the wire message should have the sanitized username
      expect(p2pService.lastSentMessage, contains('"senderUsername":"Me"'));
      expect(
        p2pService.lastSentMessage,
        isNot(contains('\u200B')),
      );
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

    test('sends locally when peer is on local WiFi', () async {
      p2pService.localPeers.add('target-peer');

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
      expect(p2pService.localSendCallCount, 1);
      // Should NOT have attempted relay path
      expect(p2pService.discoverCallCount, 0);
      expect(p2pService.dialCallCount, 0);
      expect(p2pService.sendCallCount, 0);
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

    test('quotedMessageId is persisted in saved message', () async {
      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'This is a reply',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        quotedMessageId: 'original-msg-001',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.quotedMessageId, 'original-msg-001');
      expect(messageRepo.saved.first.quotedMessageId, 'original-msg-001');
    });

    test('quotedMessageId included in wire JSON envelope', () async {
      await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Reply text',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        quotedMessageId: 'quoted-123',
      );

      expect(p2pService.lastSentMessage, contains('"quotedMessageId":"quoted-123"'));
    });

    test('quotedMessageId is null when not provided', () async {
      final (_, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Normal message',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(message, isNotNull);
      expect(message!.quotedMessageId, isNull);
      // No quotedMessageId key in wire JSON
      expect(p2pService.lastSentMessage, isNot(contains('quotedMessageId')));
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

      test('includes media array in wire JSON', () async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'With image',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          mediaAttachments: testMedia,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(p2pService.lastSentMessage, contains('"media"'));
        expect(p2pService.lastSentMessage, contains('"blob-001"'));
        expect(p2pService.lastSentMessage, contains('"blob-002"'));
        expect(p2pService.lastSentMessage, contains('"image/jpeg"'));
      });

      test('omits media from wire JSON when null', () async {
        await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'No media',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(p2pService.lastSentMessage, isNot(contains('"media"')));
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
        );

        expect(result, SendChatMessageResult.success);
        expect(mediaRepo.saved, isEmpty);
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
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(custom.sendCallCount, 2);
        expect(custom.discoverCallCount, 1);
        expect(custom.dialCallCount, 1);
      });

      test(
          'fast path fails + all retries fail → inbox fallback, 4 total sends',
          () async {
        final custom = _AllFailButInboxP2PService();

        final (result, message) = await sendChatMessage(
          p2pService: custom,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Inbox fallback!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        // 1 fast path + 3 retries = 4 sends
        expect(custom.sendCallCount, 4);
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
        );

        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(p2pService.discoverCallCount, 1);
        expect(p2pService.dialCallCount, 1);
        expect(p2pService.sendCallCount, 1);
      });

      test('local WiFi succeeds → no fast path, no discover/dial', () async {
        p2pService.localPeers.add('target-peer');
        p2pService.isConnectedToPeerFn = (id) => id == 'target-peer';

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          text: 'Local wins!',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
        );

        expect(result, SendChatMessageResult.success);
        expect(message!.status, 'delivered');
        expect(p2pService.localSendCallCount, 1);
        // Fast path not reached since local succeeded
        expect(p2pService.sendCallCount, 0);
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
  });
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
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message) async {
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
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message) async {
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
  bool isConnectedToPeer(String peerId) => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
      String peerId, String message) async {
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
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;

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
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => false;

  @override
  Future<void> warmBackground() async {}

  @override
  void dispose() {}
}
