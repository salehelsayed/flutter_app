import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/settings/application/upload_profile_picture_use_case.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------
class _MockBridge extends Bridge {
  Map<String, dynamic>? lastParsedRequest;
  Map<String, dynamic> nextResponse = {'ok': true};
  bool shouldThrow = false;

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
    if (shouldThrow) throw Exception('bridge error');
    lastParsedRequest = jsonDecode(message) as Map<String, dynamic>;
    return jsonEncode(nextResponse);
  }
}

class _FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identityResult;
  IdentityModel? lastSaved;

  @override
  Future<IdentityModel?> loadIdentity() async => identityResult;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    lastSaved = identity;
  }
}

class _FakeContactRepository implements ContactRepository {
  List<ContactModel> activeContacts = [];

  @override
  Future<List<ContactModel>> getActiveContacts() async => activeContacts;

  // Not needed
  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class _FakeP2PService implements P2PService {
  SendMessageResult sendWithReplyResult = const SendMessageResult(
    sent: true,
    acked: true,
    reply: 'ack',
  );
  bool throwOnSend = false;
  bool storeResult = true;
  bool throwOnStore = false;
  List<String> sentToPeers = [];
  List<String> storedToPeers = [];

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    if (throwOnSend) throw Exception('send error');
    sentToPeers.add(peerId);
    return sendWithReplyResult.sent && sendWithReplyResult.acknowledged;
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    if (throwOnStore) throw Exception('store error');
    storedToPeers.add(toPeerId);
    return storeResult;
  }

  // Not needed
  @override
  NodeState get currentState => throw UnimplementedError();
  @override
  Stream<NodeState> get stateStream => throw UnimplementedError();
  @override
  Stream<ChatMessage> get messageStream => throw UnimplementedError();
  @override
  Future<bool> startNode(String pk, String id) async => true;
  @override
  Future<bool> startNodeCore(String pk, String id) async => true;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (throwOnSend) throw Exception('send error');
    sentToPeers.add(peerId);
    return sendWithReplyResult;
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;
  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;
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
  }) async => false;
  @override
  String? get lastRecoveryMethod => null;
  @override
  void dispose() {}
}

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;
  _FakePathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
IdentityModel _makeIdentity({String peerId = '12D3KooWTestPeerId123456'}) {
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk_base64',
    privateKey: 'sk_base64',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    createdAt: '2024-01-01T00:00:00Z',
    updatedAt: '2024-01-01T00:00:00Z',
  );
}

ContactModel _makeContact(String peerId) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk',
    rendezvous: '/addr',
    username: 'user',
    signature: 'sig',
    scannedAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockBridge bridge;
  late _FakeIdentityRepository identityRepo;
  late _FakeContactRepository contactRepo;
  late _FakeP2PService p2pService;
  late Directory tempDir;
  late File sourceFile;

  setUp(() async {
    flowEventLoggingEnabled = false;
    bridge = _MockBridge();
    identityRepo = _FakeIdentityRepository();
    contactRepo = _FakeContactRepository();
    p2pService = _FakeP2PService();

    tempDir = await Directory.systemTemp.createTemp('upload_profile_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    // Create a fake source image file
    sourceFile = File('${tempDir.path}/source_avatar.jpg');
    await sourceFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('uploadProfilePicture', () {
    test('success: returns true on full success path', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();

      final result = await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(result, isTrue);
    });

    test(
      'uploadFailed: returns false when bridge upload returns ok=false',
      () async {
        bridge.nextResponse = {'ok': false, 'errorMessage': 'upload failed'};

        final result = await uploadProfilePicture(
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          filePath: sourceFile.path,
          mime: 'image/jpeg',
        );

        expect(result, isFalse);
      },
    );

    test('noIdentity: returns false when loadIdentity returns null', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = null;

      final result = await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(result, isFalse);
    });

    test('exception: returns false when bridge.send throws', () async {
      bridge.shouldThrow = true;

      final result = await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(result, isFalse);
    });

    test('copies file to avatars directory ({peerId}.jpg)', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity(
        peerId: '12D3KooWCopyTest1234567',
      );

      await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      final copied = File(
        '${tempDir.path}/media/avatars/12D3KooWCopyTest1234567.jpg',
      );
      expect(await copied.exists(), isTrue);
    });

    test('creates avatars directory if not exists', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();

      // Ensure it doesn't exist before
      final avatarsDir = Directory('${tempDir.path}/media/avatars');
      expect(await avatarsDir.exists(), isFalse);

      await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(await avatarsDir.exists(), isTrue);
    });

    test('saves updated identity with new avatarVersion', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();

      await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(identityRepo.lastSaved, isNotNull);
      expect(identityRepo.lastSaved!.avatarVersion, isNotNull);
      // Should be a valid ISO-8601 timestamp
      DateTime.parse(identityRepo.lastSaved!.avatarVersion!);
    });

    test('broadcasts profile_update envelope to all active contacts', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();
      contactRepo.activeContacts = [
        _makeContact('12D3KooWContact_A_1234'),
        _makeContact('12D3KooWContact_B_1234'),
      ];

      await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(
        p2pService.sentToPeers,
        containsAll(['12D3KooWContact_A_1234', '12D3KooWContact_B_1234']),
      );
    });

    test('fallback: stores in inbox when direct send is unacked', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();
      contactRepo.activeContacts = [_makeContact('12D3KooWOfflinePeer1234')];
      p2pService.sendWithReplyResult = const SendMessageResult(
        sent: true,
        acked: false,
      );

      await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(p2pService.storedToPeers, contains('12D3KooWOfflinePeer1234'));
    });

    test('fallback: stores in inbox when direct send throws', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();
      contactRepo.activeContacts = [_makeContact('12D3KooWThrowPeer12345')];
      p2pService.throwOnSend = true;

      await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(p2pService.storedToPeers, contains('12D3KooWThrowPeer12345'));
    });

    test('silently ignores inbox store failure', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();
      contactRepo.activeContacts = [_makeContact('12D3KooWFailInboxPeer1')];
      p2pService.throwOnSend = true;
      p2pService.throwOnStore = true;

      // Should not throw - silently ignores
      final result = await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(result, isTrue);
    });

    test('works with empty contacts list', () async {
      bridge.nextResponse = {'ok': true};
      identityRepo.identityResult = _makeIdentity();
      contactRepo.activeContacts = [];

      final result = await uploadProfilePicture(
        bridge: bridge,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        filePath: sourceFile.path,
        mime: 'image/jpeg',
      );

      expect(result, isTrue);
      expect(p2pService.sentToPeers, isEmpty);
    });
  });
}
