import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

class FakeP2PService implements P2PService {
  final _messageController = StreamController<ChatMessage>.broadcast();

  void inject(ChatMessage message) => _messageController.add(message);

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => _messageController.stream;

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
  }) async => const SendMessageResult(sent: true);

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
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
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

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
  }) async => false;

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
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() => _messageController.close();
}

ChatMessage _makeMessage(String type, {bool isIncoming = true}) {
  return ChatMessage(
    from: 'peer-a',
    to: 'peer-b',
    content: jsonEncode({
      'type': type,
      'version': '1',
      'payload': {'data': 'test'},
    }),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: isIncoming,
  );
}

void main() {
  late FakeP2PService p2pService;
  late IncomingMessageRouter router;

  setUp(() {
    p2pService = FakeP2PService();
    router = IncomingMessageRouter(p2pService: p2pService);
    router.start();
  });

  tearDown(() {
    router.dispose();
    p2pService.dispose();
  });

  group('IncomingMessageRouter', () {
    test(
      'router diagnostics never include transport identity or wire preview',
      () {
        final source = File(
          'lib/core/services/incoming_message_router.dart',
        ).readAsStringSync();

        expect(source, isNot(contains("'from': message.from")));
        expect(source, isNot(contains("'contentPreview':")));
      },
    );

    test('routes contact_request messages to contactRequestStream', () async {
      final received = router.contactRequestStream.first;

      p2pService.inject(_makeMessage('contact_request'));

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.from, 'peer-a');
      expect(msg.content, contains('"type":"contact_request"'));
    });

    test('routes chat_message messages to chatMessageStream', () async {
      final received = router.chatMessageStream.first;

      p2pService.inject(_makeMessage('chat_message'));

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.from, 'peer-a');
      expect(msg.content, contains('"type":"chat_message"'));
    });

    test(
      'routes call_signal to exactly one dedicated stream and nowhere else',
      () async {
        final calls = <ChatMessage>[];
        final chats = <ChatMessage>[];
        final contacts = <ChatMessage>[];
        final groups = <ChatMessage>[];
        final posts = <ChatMessage>[];
        final unknown = <ChatMessage>[];
        router.callSignalStream.listen(calls.add);
        router.chatMessageStream.listen(chats.add);
        router.contactRequestStream.listen(contacts.add);
        router.groupInviteStream.listen(groups.add);
        router.postCreateStream.listen(posts.add);
        router.unknownMessageStream.listen(unknown.add);

        p2pService.inject(_makeMessage('call_signal'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(calls, hasLength(1));
        expect(chats, isEmpty);
        expect(contacts, isEmpty);
        expect(groups, isEmpty);
        expect(posts, isEmpty);
        expect(unknown, isEmpty);
      },
    );

    test(
      'routes group_membership_update messages to groupMembershipUpdateStream',
      () async {
        final received = router.groupMembershipUpdateStream.first;

        p2pService.inject(_makeMessage('group_membership_update'));

        final msg = await received.timeout(const Duration(seconds: 1));
        expect(msg.from, 'peer-a');
        expect(msg.content, contains('"type":"group_membership_update"'));
      },
    );

    // 115 P2.1 — REWRITTEN from 'ignores legacy delivery_receipt messages':
    // the type-name drop made cross-device delivery receipts impossible and
    // left relay-inbox custody permanently unconfirmable (doc 115 G-C).
    test(
      "routes 'delivery_receipt' envelopes to deliveryReceiptStream instead of dropping them",
      () async {
        final contactRequests = <ChatMessage>[];
        final chatMessages = <ChatMessage>[];
        final unknowns = <ChatMessage>[];
        final receipts = <ChatMessage>[];

        router.contactRequestStream.listen(contactRequests.add);
        router.chatMessageStream.listen(chatMessages.add);
        router.unknownMessageStream.listen(unknowns.add);
        router.deliveryReceiptStream.listen(receipts.add);

        p2pService.inject(_makeMessage('delivery_receipt'));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(receipts, hasLength(1));
        expect(receipts.single.content, contains('"type":"delivery_receipt"'));
        expect(contactRequests, isEmpty);
        expect(chatMessages, isEmpty);
        expect(unknowns, isEmpty);
      },
    );

    // Slice 2 / UDM-G — the active key-pull a behind-epoch member sends to the
    // admin. Old peers without this case route the type to unknownMessageStream
    // (harmless drop); the admin's responder needs it on its own typed stream.
    test(
      'routes group_key_repair_request to groupKeyRepairRequestStream',
      () async {
        final repairRequests = <ChatMessage>[];
        final unknowns = <ChatMessage>[];
        final keyUpdates = <ChatMessage>[];

        router.groupKeyRepairRequestStream.listen(repairRequests.add);
        router.unknownMessageStream.listen(unknowns.add);
        router.groupKeyUpdateStream.listen(keyUpdates.add);

        p2pService.inject(_makeMessage('group_key_repair_request'));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(repairRequests, hasLength(1));
        expect(
          repairRequests.single.content,
          contains('"type":"group_key_repair_request"'),
        );
        expect(unknowns, isEmpty);
        expect(keyUpdates, isEmpty);
      },
    );

    test('routes unknown types to unknownMessageStream', () async {
      final received = router.unknownMessageStream.first;

      p2pService.inject(_makeMessage('some_future_type'));

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.from, 'peer-a');
    });

    test('routes unparseable content to unknownMessageStream', () async {
      final received = router.unknownMessageStream.first;

      p2pService.inject(
        ChatMessage(
          from: 'peer-a',
          to: 'peer-b',
          content: 'not valid json',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.content, 'not valid json');
    });

    test('ignores outgoing messages', () async {
      final contactRequests = <ChatMessage>[];
      final chatMessages = <ChatMessage>[];
      final unknowns = <ChatMessage>[];

      router.contactRequestStream.listen(contactRequests.add);
      router.chatMessageStream.listen(chatMessages.add);
      router.unknownMessageStream.listen(unknowns.add);

      // Inject an outgoing message (isIncoming: false)
      p2pService.inject(_makeMessage('contact_request', isIncoming: false));

      // Then inject an incoming one to verify the stream works
      p2pService.inject(_makeMessage('chat_message'));

      await Future.delayed(const Duration(milliseconds: 50));

      // Only the incoming chat_message should have been routed
      expect(contactRequests, isEmpty);
      expect(chatMessages.length, 1);
      expect(unknowns, isEmpty);
    });

    test('routes multiple messages to correct streams', () async {
      final contactRequests = <ChatMessage>[];
      final chatMessages = <ChatMessage>[];
      final unknowns = <ChatMessage>[];

      router.contactRequestStream.listen(contactRequests.add);
      router.chatMessageStream.listen(chatMessages.add);
      router.unknownMessageStream.listen(unknowns.add);

      p2pService.inject(_makeMessage('contact_request'));
      p2pService.inject(_makeMessage('chat_message'));
      p2pService.inject(_makeMessage('chat_message'));
      p2pService.inject(_makeMessage('unknown_type'));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(contactRequests.length, 1);
      expect(chatMessages.length, 2);
      expect(unknowns.length, 1);
    });

    test('routes message_reaction to reactionStream', () async {
      final received = router.reactionStream.first;

      p2pService.inject(_makeMessage('message_reaction'));

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.from, 'peer-a');
      expect(msg.content, contains('"type":"message_reaction"'));
    });

    test('routes message_deletion to messageDeletionStream', () async {
      final received = router.messageDeletionStream.first;

      p2pService.inject(_makeMessage('message_deletion'));

      final msg = await received.timeout(const Duration(seconds: 1));
      expect(msg.from, 'peer-a');
      expect(msg.content, contains('"type":"message_deletion"'));
    });

    // --- Cycle 3.1: group_invite routing ---
    test('routes group_invite messages to groupInviteStream', () async {
      final chatMessages = <ChatMessage>[];
      final contactRequests = <ChatMessage>[];
      final unknowns = <ChatMessage>[];
      final groupInvites = <ChatMessage>[];

      router.chatMessageStream.listen(chatMessages.add);
      router.contactRequestStream.listen(contactRequests.add);
      router.unknownMessageStream.listen(unknowns.add);
      router.groupInviteStream.listen(groupInvites.add);

      p2pService.inject(_makeMessage('group_invite'));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(groupInvites.length, 1);
      expect(groupInvites.first.content, contains('"type":"group_invite"'));
      expect(chatMessages, isEmpty);
      expect(contactRequests, isEmpty);
      expect(unknowns, isEmpty);
    });

    // --- Cycle 3.2: v2 group_invite routing ---
    test(
      'routes v2 group_invite envelope (type in top-level) to groupInviteStream',
      () async {
        final groupInvites = <ChatMessage>[];
        router.groupInviteStream.listen(groupInvites.add);

        // V2 envelope has type at top level
        p2pService.inject(
          ChatMessage(
            from: 'peer-a',
            to: 'peer-b',
            content: jsonEncode({
              'type': 'group_invite',
              'version': '2',
              'senderPeerId': 'peer-a',
              'encrypted': {
                'kem': 'fakeKem',
                'ciphertext': 'fakeCt',
                'nonce': 'fakeNonce',
              },
            }),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(groupInvites.length, 1);
        expect(groupInvites.first.content, contains('"type":"group_invite"'));
      },
    );

    test('routes group_invite_revocation to groupInviteStream', () async {
      final groupInvites = <ChatMessage>[];
      final unknowns = <ChatMessage>[];
      router.groupInviteStream.listen(groupInvites.add);
      router.unknownMessageStream.listen(unknowns.add);

      p2pService.inject(
        ChatMessage(
          from: 'peer-a',
          to: 'peer-b',
          content: jsonEncode({
            'type': 'group_invite_revocation',
            'version': '1',
            'id': 'invite-1',
            'senderPeerId': 'peer-a',
            'encrypted': {
              'kem': 'fakeKem',
              'ciphertext': 'fakeCt',
              'nonce': 'fakeNonce',
            },
          }),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(groupInvites, hasLength(1));
      expect(
        groupInvites.first.content,
        contains('"type":"group_invite_revocation"'),
      );
      expect(unknowns, isEmpty);
    });

    test('routes group_invite_decline_ack to groupInviteStream', () async {
      final groupInvites = <ChatMessage>[];
      final unknowns = <ChatMessage>[];
      router.groupInviteStream.listen(groupInvites.add);
      router.unknownMessageStream.listen(unknowns.add);

      p2pService.inject(
        ChatMessage(
          from: 'peer-a',
          to: 'peer-b',
          content: jsonEncode({
            'type': 'group_invite_decline_ack',
            'version': '1',
            'id': 'invite-1',
            'senderPeerId': 'peer-a',
            'encrypted': {
              'kem': 'fakeKem',
              'ciphertext': 'fakeCt',
              'nonce': 'fakeNonce',
            },
          }),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(groupInvites, hasLength(1));
      expect(
        groupInvites.first.content,
        contains('"type":"group_invite_decline_ack"'),
      );
      expect(unknowns, isEmpty);
    });

    for (final type in ['group_config_request', 'group_config_response']) {
      test('routes $type to groupInviteStream', () async {
        final groupInvites = <ChatMessage>[];
        final unknowns = <ChatMessage>[];
        router.groupInviteStream.listen(groupInvites.add);
        router.unknownMessageStream.listen(unknowns.add);

        p2pService.inject(
          ChatMessage(
            from: 'peer-a',
            to: 'peer-b',
            content: jsonEncode({
              'type': type,
              'version': '1',
              'id': 'grp-1',
              'senderPeerId': 'peer-a',
              'encrypted': {
                'kem': 'fakeKem',
                'ciphertext': 'fakeCt',
                'nonce': 'fakeNonce',
              },
            }),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        expect(groupInvites, hasLength(1));
        expect(groupInvites.first.content, contains('"type":"$type"'));
        expect(unknowns, isEmpty);
      });
    }

    test(
      'message_reaction not routed to chatMessageStream or unknownMessageStream',
      () async {
        final chatMessages = <ChatMessage>[];
        final unknowns = <ChatMessage>[];
        final reactions = <ChatMessage>[];

        router.chatMessageStream.listen(chatMessages.add);
        router.unknownMessageStream.listen(unknowns.add);
        router.reactionStream.listen(reactions.add);

        p2pService.inject(_makeMessage('message_reaction'));

        await Future.delayed(const Duration(milliseconds: 50));

        expect(reactions.length, 1);
        expect(chatMessages, isEmpty);
        expect(unknowns, isEmpty);
      },
    );
  });
}
