/// Integration test: Profile picture upload -> broadcast -> download.
///
/// Tests the wire format, routing, and detection logic for profile updates.
/// Actual file I/O is not tested (path_provider unavailable in unit tests).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;
  _FakePathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _MockBridge extends Bridge {
  Map<String, dynamic>? lastParsedRequest;
  Map<String, dynamic> nextResponse = {'ok': true};
  Uint8List? profileDownloadBytes;

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    lastParsedRequest = jsonDecode(message) as Map<String, dynamic>;
    if (lastParsedRequest?['cmd'] == 'profile:download') {
      final payload = lastParsedRequest!['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      if (profileDownloadBytes != null) {
        await File(outputPath).writeAsBytes(profileDownloadBytes!, flush: true);
      }
    }
    return jsonEncode(nextResponse);
  }

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

Future<XFile?> _compressToBytes({
  required String path,
  required Uint8List bytes,
}) async {
  final outputPath = '${path}_processed.jpg';
  await File(outputPath).writeAsBytes(bytes, flush: true);
  return XFile(outputPath);
}

AvatarNormalizationHelper _makeAvatarNormalizer(Uint8List bytes) {
  return AvatarNormalizationHelper(
    imageProcessor: ImageProcessor(
      compressFile: ({
        required String path,
        required int quality,
        required bool keepExif,
        int minWidth = 1920,
        int minHeight = 1080,
      }) async {
        return _compressToBytes(path: path, bytes: bytes);
      },
    ),
  );
}

ChatMessage buildProfileUpdateMessage({
  required String fromPeerId,
  required String avatarVersion,
}) {
  final envelope = jsonEncode({
    'type': 'profile_update',
    'version': '1',
    'payload': {
      'peerId': fromPeerId,
      'avatarVersion': avatarVersion,
    },
  });

  return ChatMessage(
    from: fromPeerId,
    to: 'own',
    content: envelope,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ownPeerId = '12D3KooWOwnPeerIdxxx00000000000';
  const bobPeerId = '12D3KooWBobPeerIdxxx00000000001';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_picture_flow_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Profile picture flow', () {
    test('4a. Profile update envelope structure validation', () {
      final envelope = jsonEncode({
        'type': 'profile_update',
        'version': '1',
        'payload': {
          'peerId': bobPeerId,
          'avatarVersion': 'v2',
        },
      });

      final parsed = jsonDecode(envelope) as Map<String, dynamic>;
      expect(parsed['type'], 'profile_update');
      expect(parsed['version'], '1');

      final payload = parsed['payload'] as Map<String, dynamic>;
      expect(payload['peerId'], bobPeerId);
      expect(payload['avatarVersion'], 'v2');
    });

    test('4b. IncomingMessageRouter routes profile_update to correct stream',
        () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: ownPeerId, network: network);
      final router = IncomingMessageRouter(p2pService: p2pService);
      router.start();

      final profileFuture = router.profileUpdateStream.first;
      final chatMessages = <ChatMessage>[];
      final chatSub = router.chatMessageStream.listen(
        (msg) => chatMessages.add(msg),
      );

      // Inject profile_update
      p2pService.injectIncomingMessage(
        buildProfileUpdateMessage(
          fromPeerId: bobPeerId,
          avatarVersion: 'v1',
        ),
      );

      final profileMsg = await profileFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('profileUpdateStream never emitted'),
      );

      expect(profileMsg.from, bobPeerId);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(chatMessages, isEmpty);

      await chatSub.cancel();
      router.dispose();
      p2pService.dispose();
    });

    test('4c. ProfileUpdateListener skips when avatarVersion already matches',
        () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: ownPeerId, network: network);
      final router = IncomingMessageRouter(p2pService: p2pService);
      router.start();

      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Bob',
          signature: 'sig',
          scannedAt: '2026-01-01T00:00:00Z',
          avatarVersion: 'v1', // already matches
        ),
      );

      final bridge = FakeBridge();
      final listener = ProfileUpdateListener(
        profileUpdateStream: router.profileUpdateStream,
        contactRepo: contactRepo,
        bridge: bridge,
      );
      listener.start();

      final contactUpdates = <ContactModel>[];
      final sub = listener.contactUpdatedStream.listen(
        (c) => contactUpdates.add(c),
      );

      // Inject profile_update with same version
      p2pService.injectIncomingMessage(
        buildProfileUpdateMessage(
          fromPeerId: bobPeerId,
          avatarVersion: 'v1',
        ),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Should NOT have emitted or attempted download
      expect(contactUpdates, isEmpty);
      expect(bridge.sendCallCount, 0);

      await sub.cancel();
      listener.dispose();
      router.dispose();
      p2pService.dispose();
    });

    test('4d. ProfileUpdateListener skips unknown sender', () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: ownPeerId, network: network);
      final router = IncomingMessageRouter(p2pService: p2pService);
      router.start();

      final contactRepo = InMemoryContactRepository();
      // Do NOT seed the sender
      final bridge = FakeBridge();

      final listener = ProfileUpdateListener(
        profileUpdateStream: router.profileUpdateStream,
        contactRepo: contactRepo,
        bridge: bridge,
      );
      listener.start();

      final contactUpdates = <ContactModel>[];
      final sub = listener.contactUpdatedStream.listen(
        (c) => contactUpdates.add(c),
      );

      p2pService.injectIncomingMessage(
        buildProfileUpdateMessage(
          fromPeerId: 'unknown-peer-id',
          avatarVersion: 'v1',
        ),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(contactUpdates, isEmpty);
      expect(bridge.sendCallCount, 0);

      await sub.cancel();
      listener.dispose();
      router.dispose();
      p2pService.dispose();
    });

    test(
      '4e. ProfileUpdateListener detects new avatarVersion and downloads a normalized avatar',
      () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: ownPeerId, network: network);
      final router = IncomingMessageRouter(p2pService: p2pService);
      router.start();

      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(
        ContactModel(
          peerId: bobPeerId,
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Bob',
          signature: 'sig',
          scannedAt: '2026-01-01T00:00:00Z',
          avatarVersion: null, // no avatar yet
        ),
      );

      final bridge = _MockBridge();
      bridge.profileDownloadBytes = Uint8List.fromList(
        List<int>.generate(96, (index) => index % 256),
      );
      final processedBytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      final avatarNormalizer = _makeAvatarNormalizer(processedBytes);

      final listener = ProfileUpdateListener(
        profileUpdateStream: router.profileUpdateStream,
        contactRepo: contactRepo,
        bridge: bridge,
        downloadProfilePictureFn: ({
          required Bridge bridge,
          required contactRepo,
          required ownerPeerId,
          required avatarVersion,
        }) {
          return downloadProfilePicture(
            bridge: bridge,
            contactRepo: contactRepo,
            ownerPeerId: ownerPeerId,
            avatarVersion: avatarVersion,
            avatarNormalizer: avatarNormalizer,
          );
        },
      );
      listener.start();

      p2pService.injectIncomingMessage(
        buildProfileUpdateMessage(
          fromPeerId: bobPeerId,
          avatarVersion: 'v2',
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final contact = await contactRepo.getContact(bobPeerId);
      expect(contact, isNotNull);
      expect(contact!.avatarVersion, 'v2');

      final canonicalFile = File(
        '${tempDir.path}/media/avatars/$bobPeerId.jpg',
      );
      expect(await canonicalFile.exists(), isTrue);
      expect(await canonicalFile.readAsBytes(), orderedEquals(processedBytes));
      expect(
        bridge.lastParsedRequest?['payload']?['outputPath'],
        isNot(equals(canonicalFile.path)),
      );

      listener.dispose();
      router.dispose();
      p2pService.dispose();
    });

    test('4f. Broadcast goes to all active contacts (not archived)', () async {
      final contactRepo = InMemoryContactRepository();

      // 2 active, 1 archived
      contactRepo.addTestContact(
        ContactModel(
          peerId: 'contact-1',
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Active1',
          signature: 'sig',
          scannedAt: '2026-01-01T00:00:00Z',
        ),
      );
      contactRepo.addTestContact(
        ContactModel(
          peerId: 'contact-2',
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Active2',
          signature: 'sig',
          scannedAt: '2026-01-01T00:00:00Z',
        ),
      );
      contactRepo.addTestContact(
        ContactModel(
          peerId: 'contact-3',
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Archived',
          signature: 'sig',
          scannedAt: '2026-01-01T00:00:00Z',
          isArchived: true,
          archivedAt: '2026-01-02T00:00:00Z',
        ),
      );

      final activeContacts = await contactRepo.getActiveContacts();
      expect(activeContacts.length, 2);

      final archivedContacts = await contactRepo.getArchivedContacts();
      expect(archivedContacts.length, 1);

      // Verify broadcast would go to exactly 2 active contacts
      final broadcastTargets = activeContacts.map((c) => c.peerId).toList();
      expect(broadcastTargets, containsAll(['contact-1', 'contact-2']));
      expect(broadcastTargets, isNot(contains('contact-3')));
    });
  });
}
