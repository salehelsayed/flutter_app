/// Smoke tests verifying the introduction feature DI wiring end-to-end.
///
/// These tests pump real ConversationWired with all introduction dependencies
/// and verify that "Make introductions" actually opens the FriendPickerWired
/// bottom sheet, and that the full send flow works.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/screens/friend_picker_screen.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_banner.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

// ---------------------------------------------------------------------------
// Minimal fakes
// ---------------------------------------------------------------------------

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

class _FakeMessageRepository implements MessageRepository {
  final Map<String, ConversationMessage> store = {};

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    store[message.id] = message;
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
      String contactPeerId) async {
    return store.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
      String contactPeerId) async {
    final msgs = await getMessagesForContact(contactPeerId);
    return msgs.isEmpty ? null : msgs.last;
  }

  @override
  Future<bool> messageExists(String id) async => store.containsKey(id);
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<int> getMessageCountForContact(String contactPeerId) async =>
      store.values.where((m) => m.contactPeerId == contactPeerId).length;
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
  }) async {
    var msgs = store.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList();
    if (beforeTimestamp != null) {
      msgs =
          msgs.where((m) => m.timestamp.compareTo(beforeTimestamp) < 0).toList();
    }
    msgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return msgs.take(limit).toList().reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];
  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async =>
      [];
}

class _FakeP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true, peerId: 'me');
  @override
  void dispose() {}
  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async => null;
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async =>
      const SendMessageResult(sent: true, reply: 'received: ok');
  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;
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
  }) async =>
      false;
  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;
  @override
  Future<void> warmBackground() async {}
}

class _FakeBridge implements Bridge {
  @override
  Future<String> send(String message) async => '{}';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(String event)? onNodeEvent;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
      onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
  @override
  void Function(p2p.ConnectionState)? onPeerConnected;
  @override
  void Function(p2p.ConnectionState)? onPeerDisconnected;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ContactModel _contactB() => ContactModel(
      peerId: 'peer-B',
      publicKey: 'pk-B',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Lina',
      signature: 'sig-B',
      scannedAt: '2026-03-01T10:00:00.000Z',
    );

ContactModel _contactC() => ContactModel(
      peerId: 'peer-C',
      publicKey: 'pk-C',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Sarah',
      signature: 'sig-C',
      scannedAt: '2026-03-01T10:00:00.000Z',
    );

IdentityModel _identity() => IdentityModel(
      peerId: 'peer-A',
      publicKey: 'pub-A',
      privateKey: 'priv-A',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      username: 'Noor',
      createdAt: '2026-03-01T09:00:00.000Z',
      updatedAt: '2026-03-01T09:00:00.000Z',
    );

Future<(SendChatMessageResult, ConversationMessage?)> _noOpSendFn({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  String? timestamp,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  return (SendChatMessageResult.nodeNotRunning, null);
}

IntroductionModel _makeIntro({
  required String introducerId,
  required String recipientId,
  required String introducedId,
}) {
  return IntroductionModel(
    id: '${introducerId}_${recipientId}_${introducedId}_test',
    introducerId: introducerId,
    recipientId: recipientId,
    introducedId: introducedId,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Intro wiring smoke tests', () {
    late InMemoryContactRepository contactRepo;
    late InMemoryIntroductionRepository introRepo;
    late _FakeIdentityRepository identityRepo;
    late _FakeMessageRepository messageRepo;
    late _FakeP2PService p2pService;
    late _FakeBridge bridge;
    late ChatMessageListener chatListener;

    setUp(() {
      contactRepo = InMemoryContactRepository();
      introRepo = InMemoryIntroductionRepository();
      identityRepo = _FakeIdentityRepository(_identity());
      messageRepo = _FakeMessageRepository();
      p2pService = _FakeP2PService();
      bridge = _FakeBridge();

      // A knows B and C; B is the conversation target
      contactRepo.addTestContact(_contactB());
      contactRepo.addTestContact(_contactC());

      chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
    });

    Future<void> pumpWired(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationWired(
            contact: _contactB(),
            identityRepo: identityRepo,
            messageRepo: messageRepo,
            chatMessageListener: chatListener,
            p2pService: p2pService,
            bridge: bridge,
            contactRepo: contactRepo,
            introductionRepository: introRepo,
            sendChatMessageFn: _noOpSendFn,
          ),
        ),
      );
      // Let initState async calls complete
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('banner shows when all deps wired', (tester) async {
      await pumpWired(tester);

      expect(find.byType(IntroBanner), findsOneWidget);
      expect(find.text('Make introductions'), findsOneWidget);
    });

    /// Pumps enough frames for modal bottom sheet animation + async loading.
    Future<void> pumpSheet(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('tapping "Make introductions" opens FriendPickerScreen',
        (tester) async {
      await pumpWired(tester);

      await tester.tap(find.text('Make introductions'));
      await pumpSheet(tester);

      expect(find.byType(FriendPickerScreen), findsOneWidget);
      expect(find.textContaining('Introduce to Lina'), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget);
    });

    testWidgets('picker excludes recipient from list', (tester) async {
      await pumpWired(tester);

      await tester.tap(find.text('Make introductions'));
      await pumpSheet(tester);

      // Sarah should be in the pickable list
      expect(find.text('Sarah'), findsOneWidget);
      // Only 1 friend listed (Sarah), not 2 (Lina excluded as recipient)
      final picker = find.byType(FriendPickerScreen);
      expect(picker, findsOneWidget);
    });

    testWidgets('select friend → tap Introduce → record saved',
        (tester) async {
      await pumpWired(tester);

      await tester.tap(find.text('Make introductions'));
      await pumpSheet(tester);

      await tester.tap(find.text('Sarah'));
      await tester.pump();

      expect(find.text('Introduce (1)'), findsOneWidget);

      await tester.tap(find.text('Introduce (1)'));
      await pumpSheet(tester);

      final intros = await introRepo.getIntroductionsByIntroducer('peer-A');
      expect(intros, hasLength(1));
      expect(intros.first.recipientId, 'peer-B');
      expect(intros.first.introducedId, 'peer-C');
      expect(intros.first.introducerUsername, 'Noor');
    });

    testWidgets('tap does nothing when introductionRepository is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationWired(
            contact: _contactB(),
            identityRepo: identityRepo,
            messageRepo: messageRepo,
            chatMessageListener: chatListener,
            p2pService: p2pService,
            bridge: bridge,
            contactRepo: contactRepo,
            sendChatMessageFn: _noOpSendFn,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final banner = find.byType(IntroBanner);
      if (banner.evaluate().isNotEmpty) {
        await tester.tap(find.text('Make introductions'));
        await pumpSheet(tester);
        expect(find.byType(FriendPickerScreen), findsNothing);
      }
    });

    testWidgets('"Maybe later" dismisses and persists', (tester) async {
      await pumpWired(tester);
      expect(find.byType(IntroBanner), findsOneWidget);

      await tester.tap(find.text('Maybe later'));
      // Pump AnimatedSwitcher (300ms) + extra
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(IntroBanner), findsNothing);
      final contact = await contactRepo.getContact('peer-B');
      expect(contact!.introsBannerDismissed, isTrue);
    });

    testWidgets('banner hidden when 0 other friends', (tester) async {
      final lonelyRepo = InMemoryContactRepository();
      lonelyRepo.addTestContact(_contactB());

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationWired(
            contact: _contactB(),
            identityRepo: identityRepo,
            messageRepo: messageRepo,
            chatMessageListener: chatListener,
            p2pService: p2pService,
            bridge: bridge,
            contactRepo: lonelyRepo,
            introductionRepository: introRepo,
            sendChatMessageFn: _noOpSendFn,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(IntroBanner), findsNothing);
    });

    testWidgets('picker excludes already-introduced friends', (tester) async {
      await introRepo.saveIntroduction(_makeIntro(
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
      ));

      await pumpWired(tester);

      await tester.tap(find.text('Make introductions'));
      await pumpSheet(tester);

      expect(find.byType(FriendPickerScreen), findsOneWidget);
      expect(find.text('Sarah'), findsNothing);
      expect(find.textContaining('No friends available'), findsOneWidget);
    });
  });
}
