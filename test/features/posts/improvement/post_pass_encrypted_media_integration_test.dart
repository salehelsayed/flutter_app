import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/download_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _EncryptedMediaUser sender;
  late _EncryptedMediaUser author;
  late _EncryptedMediaUser recipient;
  late _RelayMediaStore relayStore;
  late Directory tempDir;
  late _TempPostMediaFileManager mediaFileManager;

  setUp(() {
    network = FakeP2PNetwork();
    relayStore = _RelayMediaStore();
    sender = _EncryptedMediaUser.create(
      peerId: 'peer-hisam',
      username: 'Hisam',
      network: network,
      relayStore: relayStore,
    );
    author = _EncryptedMediaUser.create(
      peerId: 'peer-solz',
      username: 'Solz',
      network: network,
      relayStore: relayStore,
    );
    recipient = _EncryptedMediaUser.create(
      peerId: 'peer-ibra',
      username: 'Ibra',
      network: network,
      relayStore: relayStore,
    );

    sender.addContact(author);
    sender.addContact(recipient);
    author.addContact(sender);
    recipient.addContact(sender);

    author.start();
    recipient.start();

    tempDir = Directory.systemTemp.createTempSync(
      'post-pass-encrypted-media-',
    );
    mediaFileManager = _TempPostMediaFileManager(tempDir.path);
  });

  tearDown(() {
    sender.dispose();
    author.dispose();
    recipient.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'encrypted repost media uploads ciphertext, preserves recipient ACL, and decrypts back to the original bytes',
    () async {
      final originalBytes = Uint8List.fromList(
        List<int>.generate(256, (index) => (index * 17) & 0xff),
      );
      final originalFile = File('${tempDir.path}/source-image.jpg');
      await originalFile.writeAsBytes(originalBytes);

      await sender.postRepo.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-solz',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
          text: 'Need help carrying a ladder.',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T10:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
          isIncoming: true,
          mediaKind: 'image',
        ),
      );
      await sender.postRepo.savePostMediaAttachment(
        PostMediaAttachmentModel(
          mediaId: 'media-1',
          postId: 'post-1',
          blobId: 'blob-original-1',
          kind: 'image',
          mime: 'image/jpeg',
          sizeBytes: originalBytes.length,
          width: 1440,
          height: 1080,
          localPath: originalFile.path,
          downloadStatus: 'done',
          createdAt: '2026-03-15T10:20:00.000Z',
        ),
      );

      final (result, pass) = await passPostAlong(
        p2pService: sender.p2pService,
        postRepo: sender.postRepo,
        contactRepo: sender.contactRepo,
        bridge: sender.bridge,
        postId: 'post-1',
        senderPeerId: sender.peerId,
        senderUsername: sender.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );

      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);
      expect(
        sender.bridge.commandLog.where((command) => command == 'blob:encrypt'),
        hasLength(1),
      );
      expect(
        sender.bridge.commandLog.where((command) => command == 'media:upload'),
        hasLength(1),
      );
      expect(
        sender.bridge.commandLog.where((command) => command == 'message.encrypt'),
        hasLength(2),
      );

      await _waitForPassCount(sender, expectedCount: 1);
      await _waitForPassCount(author, expectedCount: 1);
      await _waitForPassCount(recipient, expectedCount: 1);

      final relayBlobId = sender.relayStore.blobIds.single;
      expect(relayBlobId, isNot('blob-original-1'));
      expect(sender.relayStore.allowedPeersByBlobId[relayBlobId], isNotNull);
      expect(
        sender.relayStore.allowedPeersByBlobId[relayBlobId]!,
        unorderedEquals(<String>[
          sender.peerId,
          recipient.peerId,
          author.peerId,
        ]),
      );
      expect(
        sender.relayStore.ciphertextByBlobId[relayBlobId],
        isNotNull,
      );
      expect(
        sender.relayStore.ciphertextByBlobId[relayBlobId]!,
        isNot(equals(originalBytes)),
      );

      final recipientPass = (await recipient.postRepo.loadPostPasses('post-1'))
          .single;
      expect(recipientPass.innerPayloadJson, isNotNull);
      await _waitForMediaAttachmentCount(recipient, expectedCount: 1);
      final recipientAttachment = (await recipient.postRepo
              .loadPostMediaAttachments('post-1'))
          .single;
      expect(recipientAttachment.isEncrypted, isTrue);
      expect(recipientAttachment.blobId, relayBlobId);
      expect(recipientAttachment.encryptionKeyBase64, isNotNull);
      expect(recipientAttachment.encryptionNonce, isNotNull);

      final hydratedAttachment = await downloadPostMedia(
        bridge: recipient.bridge,
        postRepo: recipient.postRepo,
        mediaFileManager: mediaFileManager,
        attachment: recipientAttachment,
      );

      expect(hydratedAttachment.downloadStatus, 'done');
      expect(hydratedAttachment.localPath, isNotNull);

      final localPath = await mediaFileManager.localPathForPostAttachment(
        postId: 'post-1',
        blobId: relayBlobId,
        mime: 'image/jpeg',
      );
      final restoredBytes = await File(localPath).readAsBytes();
      expect(restoredBytes, orderedEquals(originalBytes));
    },
  );
}

class _EncryptedMediaUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final _EncryptedMediaBridge bridge;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPassListener passListener;

  _EncryptedMediaUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.passListener,
  });

  factory _EncryptedMediaUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
    required _RelayMediaStore relayStore,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final bridge = _EncryptedMediaBridge(relayStore);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final passListener = PostPassListener(
      postPassStream: router.postPassStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
    );

    return _EncryptedMediaUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      bridge: bridge,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      passListener: passListener,
    );
  }

  void addContact(_EncryptedMediaUser other) {
    contactRepo.addTestContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: 'pk-${other.peerId}',
        rendezvous: '/dns4/example.invalid/tcp/443',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: '2026-03-15T10:00:00.000Z',
        mlKemPublicKey: 'mlkem-${other.peerId}',
      ),
    );
  }

  void start() {
    router.start();
    passListener.start();
  }

  _RelayMediaStore get relayStore => bridge.relayStore;

  void dispose() {
    passListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}

class _EncryptedMediaBridge extends PassthroughCryptoBridge {
  static final Uint8List _fixedKey = Uint8List.fromList(
    List<int>.generate(32, (index) => (index * 7 + 11) & 0xff),
  );
  static final Uint8List _fixedNonce = Uint8List.fromList(
    List<int>.generate(12, (index) => (index * 13 + 3) & 0xff),
  );

  final _RelayMediaStore relayStore;

  _EncryptedMediaBridge(this.relayStore);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == null) {
      return super.send(message);
    }

    switch (cmd) {
      case 'blob:keygen':
        _record(message, cmd);
        return jsonEncode({
          'ok': true,
          'keyBase64': base64Encode(_fixedKey),
        });
      case 'blob:encrypt':
        _record(message, cmd);
        final payload = parsed['payload'] as Map<String, dynamic>;
        final filePath = payload['filePath'] as String;
        final plaintext = await File(filePath).readAsBytes();
        final encryptedPath = '$filePath.enc';
        await File(encryptedPath).writeAsBytes(
          _xorWithKeyAndNonce(plaintext, _fixedKey, _fixedNonce),
          flush: true,
        );
        return jsonEncode({
          'ok': true,
          'encryptedPath': encryptedPath,
          'nonce': base64Encode(_fixedNonce),
        });
      case 'blob:decrypt':
        _record(message, cmd);
        final payload = parsed['payload'] as Map<String, dynamic>;
        final filePath = payload['filePath'] as String;
        final keyBase64 = payload['keyBase64'] as String;
        final nonceBase64 = payload['nonce'] as String;
        final ciphertext = await File(filePath).readAsBytes();
        final decryptedPath = '$filePath.dec';
        await File(decryptedPath).writeAsBytes(
          _xorWithKeyAndNonce(
            ciphertext,
            base64Decode(keyBase64),
            base64Decode(nonceBase64),
          ),
          flush: true,
        );
        return jsonEncode({
          'ok': true,
          'decryptedPath': decryptedPath,
        });
      case 'media:upload':
        _record(message, cmd);
        final payload = parsed['payload'] as Map<String, dynamic>;
        final blobId = payload['id'] as String;
        final filePath = payload['filePath'] as String;
        final allowedPeers = (payload['allowedPeers'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false);
        final mime = payload['mime'] as String;
        relayStore.uploadedBytesByBlobId[blobId] = await File(filePath).readAsBytes();
        relayStore.allowedPeersByBlobId[blobId] = allowedPeers;
        relayStore.mimeByBlobId[blobId] = mime;
        return jsonEncode({'ok': true, 'id': blobId});
      case 'media:download':
        _record(message, cmd);
        final payload = parsed['payload'] as Map<String, dynamic>;
        final blobId = payload['id'] as String;
        final outputPath = payload['outputPath'] as String;
        final bytes = relayStore.uploadedBytesByBlobId[blobId];
        if (bytes == null) {
          return jsonEncode({
            'ok': false,
            'errorMessage': 'blob not found',
          });
        }
        await File(outputPath).writeAsBytes(bytes, flush: true);
        return jsonEncode({
          'ok': true,
          'id': blobId,
          'mime': relayStore.mimeByBlobId[blobId] ?? 'application/octet-stream',
          'size': bytes.length,
        });
      default:
        return super.send(message);
    }
  }

  void _record(String message, String cmd) {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;
    commandLog.add(cmd);
  }
}

class _RelayMediaStore {
  final Map<String, List<int>> uploadedBytesByBlobId = <String, List<int>>{};
  final Map<String, List<String>> allowedPeersByBlobId =
      <String, List<String>>{};
  final Map<String, String> mimeByBlobId = <String, String>{};

  Iterable<String> get blobIds => uploadedBytesByBlobId.keys;
  Map<String, List<int>> get ciphertextByBlobId => uploadedBytesByBlobId;
}

class _TempPostMediaFileManager extends MediaFileManager {
  final String baseDir;

  _TempPostMediaFileManager(this.baseDir);

  @override
  Future<String> localPathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) async {
    final dir = Directory('$baseDir/post_media/$postId');
    await dir.create(recursive: true);
    return '${dir.path}/$blobId.jpg';
  }

  @override
  String relativePathForPostAttachment({
    required String postId,
    required String blobId,
    required String mime,
  }) {
    return 'post_media/$postId/$blobId.jpg';
  }
}

Future<void> _waitForPassCount(
  _EncryptedMediaUser user, {
  required int expectedCount,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadPostPasses('post-1')).length ==
        expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for repost delivery');
}

Future<void> _waitForMediaAttachmentCount(
  _EncryptedMediaUser user, {
  required int expectedCount,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadPostMediaAttachments('post-1')).length ==
        expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for repost media attachment');
}

Uint8List _xorWithKeyAndNonce(
  List<int> input,
  List<int> key,
  List<int> nonce,
) {
  return Uint8List.fromList(
    List<int>.generate(
      input.length,
      (index) => input[index] ^ key[index % key.length] ^ nonce[index % nonce.length],
    ),
  );
}
