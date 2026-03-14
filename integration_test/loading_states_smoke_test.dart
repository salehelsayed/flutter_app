import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/secure_storage/fake_secure_key_store.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 80,
    Duration step = const Duration(milliseconds: 50),
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }

    expect(finder, findsOneWidget);
  }

  group('Loading states smoke', () {
    testWidgets('startup to FTE shows shimmer then QR', (tester) async {
      setPhoneViewport(tester);

      final deps = _TestDeps(
        bridge: _DelayedSignBridge(const Duration(milliseconds: 250)),
      );
      addTearDown(deps.dispose);

      deps.bridge.responses.addAll({
        'identity.generate': {
          'ok': true,
          'identity': {
            'peerId': 'generated-peer-id',
            'publicKey': 'generated-public-key',
            'privateKey': 'generated-private-key',
            'mnemonic12':
                'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu',
            'createdAt': '2026-03-09T08:00:00.000Z',
            'updatedAt': '2026-03-09T08:00:00.000Z',
          },
        },
        'mlkem.keygen': {
          'ok': true,
          'publicKey': 'generated-mlkem-public',
          'secretKey': 'generated-mlkem-secret',
        },
        'payload.sign': {'ok': true, 'signature': 'test-sig'},
      });

      await tester.pumpWidget(deps.buildStartupRouter());

      expect(
        find.byKey(const ValueKey('startup-loading-gate')),
        findsOneWidget,
      );

      await pumpUntilFound(tester, find.text("I'm new here"));
      await tester.pump(const Duration(milliseconds: 1300));

      await tester.tap(find.text("I'm new here"));

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('qr-loading-shimmer')),
      );

      expect(find.byType(QrImageView), findsNothing);

      await pumpUntilFound(tester, find.byType(QrImageView));

      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsNothing);
    });

    testWidgets('startup to Feed shows loading skeleton then content', (
      tester,
    ) async {
      setPhoneViewport(tester);

      final delayedMessageRepo = _SlowMessageRepository();
      final deps = _TestDeps(messageRepository: delayedMessageRepo);
      addTearDown(deps.dispose);

      deps.identityRepository.seed(_makeIdentity(includeMlKem: true));
      deps.contactRepository.addTestContact(
        _makeContact(peerId: 'peer-bob', username: 'Bob'),
      );
      await delayedMessageRepo.saveMessage(
        _makeIncomingMessage(
          id: 'msg-bob-1',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-bob',
          text: 'Latest hello from Bob',
        ),
      );

      await tester.pumpWidget(deps.buildStartupRouter());

      expect(
        find.byKey(const ValueKey('startup-loading-gate')),
        findsOneWidget,
      );

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('feed-loading-card-0')),
      );

      expect(find.byKey(const ValueKey('feed-loading-status')), findsOneWidget);
      expect(find.textContaining('Bob'), findsNothing);

      delayedMessageRepo.release();
      await pumpUntilFound(tester, find.textContaining('Bob'));

      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-loading-card-0')), findsNothing);
    });

    testWidgets('group list shows loading then groups', (tester) async {
      setPhoneViewport(tester);

      final slowGroupRepo = _SlowGroupRepository();
      final deps = _TestDeps(groupRepository: slowGroupRepo);
      addTearDown(deps.dispose);

      deps.identityRepository.seed(_makeIdentity(includeMlKem: true));
      await slowGroupRepo.saveGroup(
        _makeGroup(id: 'group-alpha', name: 'Alpha Group'),
      );

      await tester.pumpWidget(deps.buildGroupListApp());

      expect(find.byKey(const ValueKey('group-loading-row-0')), findsOneWidget);
      expect(find.text('Alpha Group'), findsNothing);

      slowGroupRepo.release();
      await pumpUntilFound(tester, find.text('Alpha Group'));

      expect(find.byKey(const ValueKey('group-loading-row-0')), findsNothing);
    });

    testWidgets('share picker shows loading then contacts', (tester) async {
      setPhoneViewport(tester);

      final slowContactRepo = _SlowContactRepository();
      final deps = _TestDeps(contactRepository: slowContactRepo);
      addTearDown(deps.dispose);

      deps.identityRepository.seed(_makeIdentity(includeMlKem: true));
      slowContactRepo.addTestContact(
        _makeContact(peerId: 'peer-alice', username: 'Alice'),
      );

      await tester.pumpWidget(
        deps.buildSharePickerApp(
          const ShareIntent(type: ShareIntentType.text, text: 'Shared hello'),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Alice'), findsNothing);

      slowContactRepo.release();
      await pumpUntilFound(tester, find.text('Alice'));

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

class _TestDeps {
  _TestDeps({
    FakeIdentityRepository? identityRepository,
    InMemoryContactRepository? contactRepository,
    MessageRepository? messageRepository,
    GroupRepository? groupRepository,
    GroupMessageRepository? groupMessageRepository,
    FakeBridge? bridge,
  }) : identityRepository = identityRepository ?? FakeIdentityRepository(),
       contactRepository = contactRepository ?? InMemoryContactRepository(),
       contactRequestRepository = FakeContactRequestRepository(),
       messageRepository = messageRepository ?? InMemoryMessageRepository(),
       mediaAttachmentRepository = InMemoryMediaAttachmentRepository(),
       bridge = bridge ?? FakeBridge(),
       p2pService = FakeP2PService(),
       mediaFileManager = FakeMediaFileManager(),
       secureKeyStore = FakeSecureKeyStore(),
       groupRepository = groupRepository ?? InMemoryGroupRepository(),
       groupMessageRepository =
           groupMessageRepository ?? InMemoryGroupMessageRepository(),
       imageProcessor = ImageProcessor(
         compressFile:
             ({
               required path,
               required quality,
               required keepExif,
               minWidth = 1920,
               minHeight = 1080,
             }) async => null,
         compressVideo:
             ({required path, required compress, onProgress}) async => null,
       ) {
    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: this.contactRepository,
      bridge: this.bridge,
      getOwnPeerId: () => '',
    );

    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: this.messageRepository,
      contactRepo: this.contactRepository,
      bridge: this.bridge,
      getOwnMlKemSecretKey: () async => null,
    );

    groupMessageListener = GroupMessageListener(
      groupRepo: this.groupRepository,
      msgRepo: this.groupMessageRepository,
    );
  }

  final FakeIdentityRepository identityRepository;
  final InMemoryContactRepository contactRepository;
  final FakeContactRequestRepository contactRequestRepository;
  final MessageRepository messageRepository;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  final FakeBridge bridge;
  final FakeP2PService p2pService;
  final FakeMediaFileManager mediaFileManager;
  final FakeSecureKeyStore secureKeyStore;
  final GroupRepository groupRepository;
  final GroupMessageRepository groupMessageRepository;
  final ImageProcessor imageProcessor;

  late final ContactRequestListener contactRequestListener;
  late final ChatMessageListener chatMessageListener;
  late final GroupMessageListener groupMessageListener;

  Widget buildStartupRouter() {
    return MaterialApp(
      home: StartupRouter(
        repository: identityRepository,
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
      ),
    );
  }

  Widget buildGroupListApp() {
    return MaterialApp(
      home: GroupListWired(
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        bridge: bridge,
        identityRepo: identityRepository,
        contactRepo: contactRepository,
        p2pService: p2pService,
      ),
    );
  }

  Widget buildSharePickerApp(ShareIntent shareIntent) {
    return MaterialApp(
      home: ShareTargetPickerWired(
        shareIntent: shareIntent,
        identityRepo: identityRepository,
        contactRepository: contactRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        imageProcessor: imageProcessor,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
      ),
    );
  }

  void dispose() {
    p2pService.dispose();
    bridge.dispose();
  }
}

class _SlowMessageRepository extends InMemoryMessageRepository {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    await _gate.future;
    return super.getMessagesForContact(contactPeerId);
  }
}

class _SlowGroupRepository extends InMemoryGroupRepository {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    await _gate.future;
    return super.getActiveGroups();
  }
}

class _SlowContactRepository extends InMemoryContactRepository {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    await _gate.future;
    return super.getActiveContacts();
  }
}

class _DelayedSignBridge extends FakeBridge {
  _DelayedSignBridge(this.signDelay);

  final Duration signDelay;

  @override
  Future<String> send(String message) async {
    final payload = jsonDecode(message) as Map<String, dynamic>;
    if (payload['cmd'] == 'payload.sign') {
      await Future<void>.delayed(signDelay);
    }
    return super.send(message);
  }
}

ContactModel _makeContact({required String peerId, required String username}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
  );
}

ConversationMessage _makeIncomingMessage({
  required String id,
  required String contactPeerId,
  required String senderPeerId,
  required String text,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    text: text,
    senderPeerId: senderPeerId,
    timestamp: '2026-03-09T08:00:00.000Z',
    isIncoming: true,
    status: 'delivered',
    createdAt: '2026-03-09T08:00:00.000Z',
  );
}

GroupModel _makeGroup({required String id, required String name}) {
  return GroupModel(
    id: id,
    name: name,
    type: GroupType.chat,
    topicName: 'topic-$id',
    createdAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
    createdBy: 'me',
    myRole: GroupRole.admin,
  );
}

IdentityModel _makeIdentity({required bool includeMlKem}) {
  return IdentityModel(
    peerId: 'me',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: includeMlKem ? 'mlkem-public' : null,
    mlKemSecretKey: includeMlKem ? 'mlkem-secret' : null,
    username: 'Me',
    createdAt: '2026-03-09T08:00:00.000Z',
    updatedAt: '2026-03-09T08:00:00.000Z',
  );
}
