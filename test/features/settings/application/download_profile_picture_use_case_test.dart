import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';

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

class _FakeContactRepository implements ContactRepository {
  ContactModel? contactResult;
  ContactModel? lastAdded;

  @override
  Future<ContactModel?> getContact(String peerId) async => contactResult;

  @override
  Future<void> addContact(ContactModel contact) async {
    lastAdded = contact;
  }

  // Not needed
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
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
ContactModel _makeContact({String peerId = '12D3KooWOwnerPeerId123456'}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk',
    rendezvous: '/addr',
    username: 'Bob',
    signature: 'sig',
    scannedAt: '2024-01-01T00:00:00Z',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockBridge bridge;
  late _FakeContactRepository contactRepo;
  late Directory tempDir;

  setUp(() async {
    flowEventLoggingEnabled = false;
    bridge = _MockBridge();
    contactRepo = _FakeContactRepository();

    tempDir = await Directory.systemTemp.createTemp('download_profile_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('downloadProfilePicture', () {
    test('success: returns updated ContactModel with avatarPath and avatarVersion',
        () async {
      bridge.nextResponse = {'ok': true, 'mime': 'image/jpeg', 'size': 1024};
      contactRepo.contactResult = _makeContact();

      // Create the output file the bridge "downloads"
      final avatarsDir = Directory('${tempDir.path}/media/avatars');
      avatarsDir.createSync(recursive: true);
      File('${avatarsDir.path}/12D3KooWOwnerPeerId123456.jpg')
          .writeAsBytesSync([0xFF, 0xD8]);

      final result = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(result, isNotNull);
      expect(result!.avatarVersion, equals('2024-06-15T12:00:00Z'));
      expect(result.avatarPath, contains('media'));
      expect(result.avatarPath, contains('avatars'));
      expect(result.avatarPath, contains('12D3KooWOwnerPeerId123456.jpg'));
    });

    test('downloadFailed: returns null when bridge returns ok=false', () async {
      bridge.nextResponse = {
        'ok': false,
        'errorMessage': 'not found',
      };
      contactRepo.contactResult = _makeContact();

      final result = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(result, isNull);
    });

    test('contactNotFound: returns null when getContact returns null', () async {
      bridge.nextResponse = {'ok': true};
      contactRepo.contactResult = null;

      final result = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(result, isNull);
    });

    test('exception: returns null when bridge.send throws', () async {
      bridge.shouldThrow = true;

      final result = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(result, isNull);
    });

    test('creates avatars directory if not exists', () async {
      bridge.nextResponse = {'ok': true};
      contactRepo.contactResult = _makeContact();

      final avatarsDir = Directory('${tempDir.path}/media/avatars');
      expect(avatarsDir.existsSync(), isFalse);

      await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(avatarsDir.existsSync(), isTrue);
    });

    test('updates contact via addContact (upsert)', () async {
      bridge.nextResponse = {'ok': true};
      contactRepo.contactResult = _makeContact();

      // Create the file so FileImage.evict doesn't fail
      final avatarsDir = Directory('${tempDir.path}/media/avatars');
      avatarsDir.createSync(recursive: true);
      File('${avatarsDir.path}/12D3KooWOwnerPeerId123456.jpg')
          .writeAsBytesSync([0xFF, 0xD8]);

      await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(contactRepo.lastAdded, isNotNull);
      expect(contactRepo.lastAdded!.avatarVersion, equals('2024-06-15T12:00:00Z'));
    });

    test('avatarPath is relative format (media/avatars/{peerId}.jpg)', () async {
      bridge.nextResponse = {'ok': true};
      contactRepo.contactResult = _makeContact(peerId: '12D3KooWRelPathPeer123456');

      final avatarsDir = Directory('${tempDir.path}/media/avatars');
      avatarsDir.createSync(recursive: true);
      File('${avatarsDir.path}/12D3KooWRelPathPeer123456.jpg')
          .writeAsBytesSync([0xFF, 0xD8]);

      final result = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWRelPathPeer123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(result, isNotNull);
      // Should be the relative path form: media/avatars/<peerId>.jpg
      expect(result!.avatarPath,
          equals('media/avatars/12D3KooWRelPathPeer123456.jpg'));
    });

    test('returns null on general exception', () async {
      // Force an exception by making bridge throw
      bridge.shouldThrow = true;

      final result = await downloadProfilePicture(
        bridge: bridge,
        contactRepo: contactRepo,
        ownerPeerId: '12D3KooWOwnerPeerId123456',
        avatarVersion: '2024-06-15T12:00:00Z',
      );

      expect(result, isNull);
    });
  });
}
