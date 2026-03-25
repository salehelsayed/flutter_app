import 'dart:async';
import 'dart:convert';
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
