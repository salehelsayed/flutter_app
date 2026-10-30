import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

import '../../contact_request/support/contact_repair_harness.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';

// --- Fakes ---

class _FakeBridge implements Bridge {
  Map<String, dynamic> downloadResponse = {
    'ok': true,
    'mime': 'image/jpeg',
    'size': 1024,
  };

  @override
  Future<String> send(String message) async {
    return jsonEncode(downloadResponse);
  }

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

class _FakeContactRepo implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  void seed(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> updateContactAvatar(
    String peerId, {
    required String avatarPath,
    required String avatarVersion,
  }) async {
    final current = _contacts[peerId];
    if (current == null || current.isBlocked) return null;
    final updated = current.copyWith(
      avatarPath: avatarPath,
      avatarVersion: avatarVersion,
    );
    _contacts[peerId] = updated;
    return updated;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      _contacts.values.where((c) => !c.isArchived).toList();

  @override
  Future<void> deleteContact(String peerId) async => _contacts.remove(peerId);

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

  @override
  Future<int> getContactCount() async => _contacts.length;

  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

ContactModel _makeContact(String peerId) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'User-$peerId',
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
  );
}

ChatMessage _makeProfileUpdateMessage(
  String senderPeerId,
  String avatarVersion,
) {
  return ChatMessage(
    from: senderPeerId,
    to: 'my-peer-id',
    content: jsonEncode({
      'type': 'profile_update',
      'version': '1',
      'payload': {'peerId': senderPeerId, 'avatarVersion': avatarVersion},
    }),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<ChatMessage> profileUpdateController;
  late _FakeBridge bridge;
  late _FakeContactRepo contactRepo;
  late ProfileUpdateListener listener;

  setUp(() {
    profileUpdateController = StreamController<ChatMessage>.broadcast();
    bridge = _FakeBridge();
    contactRepo = _FakeContactRepo();
    listener = ProfileUpdateListener(
      profileUpdateStream: profileUpdateController.stream,
      contactRepo: contactRepo,
      bridge: bridge,
    );
    listener.start();
  });

  tearDown(() {
    listener.dispose();
    profileUpdateController.close();
  });

  for (final cut in _ProfileAwaitCut.values) {
    test('CONTACT-008 old avatar completion at ${cut.name} preserves newer '
        'persisted key authority, name and flags in listener output', () async {
      final directory = await Directory.systemTemp.createTemp(
        'profile_key_race_',
      );
      final dbPath = '${directory.path}/account.db';
      var db = await openRepairTestDatabase(dbPath);
      final originalPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _ProfilePathProvider(directory.path);
      final pause = _ProfilePause();
      final owner = TestEd25519Identity.fromSeedByte(0x91);
      final contacts = databaseContactRepository(db);
      final avatarBridge = _ProfileDownloadBridge(
        cut == _ProfileAwaitCut.avatarDownload ? pause : null,
      );
      final listenerRepository = _ProfileWriteBoundary(
        contacts,
        cut == _ProfileAwaitCut.contactWrite ? pause : null,
      );
      addTearDown(() async {
        if (!pause.release.isCompleted) pause.release.complete();
        listener.dispose();
        PathProviderPlatform.instance = originalPlatform;
        if (db.isOpen) await db.close();
        await directory.delete(recursive: true);
      });
      final before = contactFor(
        owner,
        mlKem: 'old-mlkem',
      ).copyWith(username: 'Old name', avatarVersion: 'v1');
      await contacts.addContact(before);
      listener.dispose();
      listener = ProfileUpdateListener(
        profileUpdateStream: profileUpdateController.stream,
        contactRepo: listenerRepository,
        bridge: avatarBridge,
        downloadProfilePictureFn:
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
              bool retryPendingRequest = false,
            }) => downloadProfilePicture(
              bridge: bridge,
              contactRepo: contactRepo,
              ownerPeerId: ownerPeerId,
              avatarVersion: avatarVersion,
              retryPendingRequest: retryPendingRequest,
              avatarNormalizer: AvatarNormalizationHelper(
                imageProcessor: ImageProcessor(
                  compressFile:
                      ({
                        required path,
                        required quality,
                        required keepExif,
                        minWidth = 1920,
                        minHeight = 1080,
                      }) async {
                        final output = '${path}_processed.jpg';
                        await File(
                          output,
                        ).writeAsBytes(_profilePng, flush: true);
                        return XFile(output);
                      },
                ),
              ),
            ),
      );
      final updates = <ContactModel>[];
      final emitted = Completer<void>();
      final subscription = listener.contactUpdatedStream.listen((contact) {
        updates.add(contact);
        if (!emitted.isCompleted) emitted.complete();
      });
      addTearDown(subscription.cancel);
      listener.start();
      await listener.retryNow();
      profileUpdateController.add(
        _makeProfileUpdateMessage(owner.peerId, 'v2'),
      );
      await pause.entered.future.timeout(const Duration(seconds: 5));
      // Metadata and ML-KEM rotation keep the account key bound to owner.peerId.
      final newer = before.copyWith(
        mlKemPublicKey: 'new-authoritative-mlkem',
        mlKemKeyUpdatedTs: '2026-10-30T12:00:00.000Z',
        username: 'New authoritative name',
        isArchived: true,
        archivedAt: '2026-10-30T12:01:00.000Z',
        introsBannerDismissed: true,
        introsSentAt: '2026-10-30T12:02:00.000Z',
        introducedBy: 'Preserved introducer',
        introducedByPeerId: 'introducer-peer',
      );
      await contacts.addContact(newer);
      pause.release.complete();
      await emitted.future.timeout(const Duration(seconds: 5));
      expect(avatarBridge.downloads, 1);
      expect(updates, hasLength(1));
      final expected = newer.copyWith(
        avatarVersion: 'v2',
        avatarPath: 'media/avatars/${owner.peerId}.jpg',
      );
      listener.dispose();
      await db.close();
      db = await openRepairTestDatabase(dbPath);
      final persisted = (await databaseContactRepository(
        db,
      ).getContact(owner.peerId))!.toMap();
      expect(
        persisted,
        expected.toMap(),
        reason: 'the persisted row must retain new authority',
      );
      expect(
        updates.single.toMap(),
        expected.toMap(),
        reason: 'the observable refresh must contain current authority',
      );
      expect(
        await File('${directory.path}/${expected.avatarPath}').exists(),
        isTrue,
      );
    });
  }

  group('ProfileUpdateListener', () {
    test('ignores unknown contacts', () async {
      final updates = <ContactModel>[];
      listener.contactUpdatedStream.listen(updates.add);

      // Inject profile update from unknown peer (not in contacts)
      profileUpdateController.add(
        _makeProfileUpdateMessage('unknown-peer', '2026-02-21T12:00:00.000Z'),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates, isEmpty);
    });

    test('skips if avatarVersion matches', () async {
      final updates = <ContactModel>[];
      listener.contactUpdatedStream.listen(updates.add);

      // Add contact with existing avatarVersion
      final contact = _makeContact(
        'peer-a',
      ).copyWith(avatarVersion: '2026-02-21T12:00:00.000Z');
      contactRepo.seed(contact);

      // Inject update with same version
      profileUpdateController.add(
        _makeProfileUpdateMessage('peer-a', '2026-02-21T12:00:00.000Z'),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates, isEmpty);
    });

    test('handles malformed JSON gracefully', () async {
      final updates = <ContactModel>[];
      listener.contactUpdatedStream.listen(updates.add);

      // Inject message with invalid content
      profileUpdateController.add(
        ChatMessage(
          from: 'peer-a',
          to: 'my-peer-id',
          content: 'not valid json {{{',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Should not crash, just log and skip
      expect(updates, isEmpty);
    });

    test('handles missing payload fields gracefully', () async {
      final updates = <ContactModel>[];
      listener.contactUpdatedStream.listen(updates.add);

      // Inject message with missing payload fields
      profileUpdateController.add(
        ChatMessage(
          from: 'peer-a',
          to: 'my-peer-id',
          content: jsonEncode({
            'type': 'profile_update',
            'version': '1',
            'payload': {},
          }),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      expect(updates, isEmpty);
    });

    test(
      'emits updated contact when download succeeds with normalization',
      () async {
        final downloadedContacts = <String>[];

        listener.dispose();
        listener = ProfileUpdateListener(
          profileUpdateStream: profileUpdateController.stream,
          contactRepo: contactRepo,
          bridge: bridge,
          downloadProfilePictureFn:
              ({
                required Bridge bridge,
                required ContactRepository contactRepo,
                required String ownerPeerId,
                required String avatarVersion,
                bool retryPendingRequest = false,
              }) async {
                downloadedContacts.add(ownerPeerId);
                final contact = _makeContact(ownerPeerId).copyWith(
                  avatarVersion: avatarVersion,
                  avatarPath: 'media/avatars/$ownerPeerId.jpg',
                );
                await contactRepo.addContact(contact);
                return contact;
              },
        );
        listener.start();
        final updates = <ContactModel>[];
        final sub = listener.contactUpdatedStream.listen(updates.add);

        final peerId = 'peer-normalized';
        contactRepo.seed(_makeContact(peerId));
        profileUpdateController.add(_makeProfileUpdateMessage(peerId, 'v2'));

        await Future.delayed(const Duration(milliseconds: 100));

        expect(downloadedContacts, contains(peerId));
        expect(updates, hasLength(1));
        expect(updates.single.avatarVersion, 'v2');
        expect(updates.single.avatarPath, 'media/avatars/$peerId.jpg');
        await sub.cancel();
      },
    );

    test('retries once when the first download attempt returns null', () async {
      var attempts = 0;

      listener.dispose();
      listener = ProfileUpdateListener(
        profileUpdateStream: profileUpdateController.stream,
        contactRepo: contactRepo,
        bridge: bridge,
        retryDelay: const Duration(milliseconds: 1),
        downloadProfilePictureFn:
            ({
              required Bridge bridge,
              required ContactRepository contactRepo,
              required String ownerPeerId,
              required String avatarVersion,
              bool retryPendingRequest = false,
            }) async {
              attempts++;
              if (attempts == 1) {
                return null;
              }
              final contact = _makeContact(ownerPeerId).copyWith(
                avatarVersion: avatarVersion,
                avatarPath: 'media/avatars/$ownerPeerId.jpg',
              );
              await contactRepo.addContact(contact);
              return contact;
            },
      );
      listener.start();

      final updates = <ContactModel>[];
      final sub = listener.contactUpdatedStream.listen(updates.add);

      const peerId = 'peer-retry';
      contactRepo.seed(_makeContact(peerId));
      profileUpdateController.add(_makeProfileUpdateMessage(peerId, 'v2'));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(attempts, 2);
      expect(updates, hasLength(1));
      expect(updates.single.avatarVersion, 'v2');
      expect(updates.single.avatarPath, 'media/avatars/$peerId.jpg');
      await sub.cancel();
    });
  });
}

enum _ProfileAwaitCut { avatarDownload, contactWrite }

final class _ProfilePause {
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> wait() async {
    if (entered.isCompleted) return;
    entered.complete();
    await release.future;
  }
}

final _profilePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAADklEQVR4nGNhAAMWCAUAAGIACcSrH9MAAAAASUVORK5CYII=',
);

final class _ProfilePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _ProfilePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

final class _ProfileDownloadBridge extends _FakeBridge {
  _ProfileDownloadBridge(this.pause);
  final _ProfilePause? pause;
  var downloads = 0;
  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'profile:download') {
      downloads++;
      final payload = request['payload'] as Map<String, dynamic>;
      await File(
        payload['outputPath'] as String,
      ).writeAsBytes(Uint8List.fromList(_profilePng), flush: true);
      await pause?.wait();
    }
    return jsonEncode({'ok': true});
  }
}

// Only the profile listener/downloader's public repository operations are
// intercepted; all state is committed by the real SQL repository.
final class _ProfileWriteBoundary implements ContactRepository {
  _ProfileWriteBoundary(this.inner, this.pause);
  final ContactRepository inner;
  final _ProfilePause? pause;
  @override
  Future<ContactModel?> getContact(String id) => inner.getContact(id);
  @override
  Future<List<ContactModel>> getAllContacts() => inner.getAllContacts();
  @override
  Future<void> addContact(ContactModel contact) async {
    await pause?.wait();
    await inner.addContact(contact);
  }

  @override
  Future<ContactModel?> updateContactAvatar(
    String peerId, {
    required String avatarPath,
    required String avatarVersion,
  }) async {
    await pause?.wait();
    return inner.updateContactAvatar(
      peerId,
      avatarPath: avatarPath,
      avatarVersion: avatarVersion,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected profile operation: ${invocation.memberName}',
  );
}
