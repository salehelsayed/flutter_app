import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/application/send_thought_sticker_reply_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_send.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/recording_fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _budget = Duration(seconds: 4);
const _local = 'local-peer-0001';
const _author = 'author-peer-0001';
const _postId = 'thought-1';
const _messageId = '8ad53b87-3d4f-4abd-9f55-52ae557979c6';
const _bytes = [9, 4, 1, 10];

Future<T> _within<T>(Future<T> future) => future.timeout(_budget);

void main() {
  late Directory directory;
  late MediaRepositoryRealDbFixture fixture;
  late InMemoryPostRepository posts;
  late FakeContactRepository contacts;
  late FakeIdentityRepository identities;
  late FakeP2PService service;
  late RecordingFakeBridge bridge;
  late DateTime now;
  late List<Map<String, dynamic>> encryptedPayloads;
  late PendingComposerMedia source;
  final files = MediaFileManager();

  setUp(() async {
    now = DateTime.now().toUtc();
    directory = Directory.systemTemp.createTempSync('thought-sticker-reply-');
    final root = directory.path;
    addTearDown(() => _within(directory.delete(recursive: true)));
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PathProvider(root);
    addTearDown(() => PathProviderPlatform.instance = previousPathProvider);
    fixture = await _within(
      MediaRepositoryRealDbFixture.create(
        databasePath: '$root/messages.sqlite',
        databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      ),
    );
    addTearDown(() => _within(fixture.dispose()));
    source = PendingComposerMedia(
      file: File('$root/prepared.png')..writeAsBytesSync(_bytes),
      budgetBytes: _bytes.length,
      width: 10,
      height: 12,
    );
    posts = InMemoryPostRepository();
    addTearDown(posts.dispose);
    contacts = FakeContactRepository();
    identities = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: _local));
    final author = ContactModel(
      peerId: _author,
      publicKey: 'author-public-key',
      rendezvous: 'test-rendezvous',
      username: 'Sam',
      signature: 'test-signature',
      scannedAt: now.toIso8601String(),
      mlKemPublicKey: 'author-mlkem-key',
    );
    contacts.seed([author]);
    await _within(fixture.db.insert('contacts', author.toMap()));
    await _within(
      fixture.db.insert('identity', {
        'id': 1,
        'peer_id': _local,
        'public_key': 'local-public-key',
        'username': 'Me',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }),
    );
    await _within(
      posts.savePost(
        PostModel(
          id: _postId,
          eventId: 'thought-event',
          senderPeerId: _author,
          authorPeerId: _author,
          authorUsername: 'Sam',
          text: 'At the lake',
          audience: PostAudience.allFriends(),
          createdAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
          visibleAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
          expiresAt: now.add(const Duration(hours: 23)).toIso8601String(),
          isIncoming: true,
        ),
      ),
    );
    final network = FakeP2PNetwork();
    service = FakeP2PService(peerId: _local, network: network)
      ..connectedPeers.add(_author);
    final authorService = FakeP2PService(peerId: _author, network: network);
    addTearDown(service.dispose);
    addTearDown(authorService.dispose);
    encryptedPayloads = [];
    bridge = RecordingFakeBridge();
    bridge.whenCommand('message.encrypt', (request) {
      encryptedPayloads.add(
        jsonDecode(request!['plaintext'] as String) as Map<String, dynamic>,
      );
      return jsonEncode({
        'ok': true,
        'kem': 'test-kem',
        'ciphertext': 'opaque-test-ciphertext',
        'nonce': 'test-nonce',
      });
    });
  });

  Future<ThoughtReplyStatus> send({
    String stickerId = 'catalog-a',
    bool initial = true,
    void Function()? adopted,
    UploadMediaFn? upload,
    PreparedDirectMediaBlobCustodyCoordinator? coordinator,
  }) => _within(
    sendThoughtStickerReply(
      messageId: _messageId,
      postId: _postId,
      authorPeerId: _author,
      expectedSenderPeerId: _local,
      stickerId: stickerId,
      preparedMedia: initial ? source : null,
      onMediaAdopted: adopted,
      postRepo: posts,
      messageRepo: fixture.messageRepo,
      identityRepo: identities,
      contactRepo: contacts,
      p2pService: service,
      bridge: bridge,
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: files,
      nowProvider: () => now,
      uploadMediaFn: upload ?? uploadMedia,
      directMediaBlobCustodyClientEnabled: coordinator != null,
      directMediaBlobCustodyCoordinator: coordinator,
    ),
  );

  Future<MediaAttachment> storedSticker() async => (await _within(
    fixture.repo.getAttachmentsForMessage(
      _messageId,
      owner: MediaOwnerLane.direct,
    ),
  )).single;

  void expectEncryptedSticker(String marker, MediaAttachment saved) {
    expect(encryptedPayloads, hasLength(1));
    final payload = encryptedPayloads.single;
    expect(payload['id'], _messageId);
    expect(payload['quotedMessageId'], 'thought:$_postId');
    expect(payload['text'], isEmpty);
    final media = (payload['media'] as List).single as Map;
    expect(media['id'], saved.id);
    expect(media['sticker'], {'id': marker});
    expect(media.containsKey('localPath'), isFalse);
    expect(saved.stickerId, marker);
    expect(saved.downloadStatus, 'done');
  }

  test(
    'default upload saves and encrypts the same quoted bundled sticker once',
    () async {
      var adoptions = 0;
      var uploads = 0;
      final result = await send(
        adopted: () => adoptions++,
        upload:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              fileName,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              uploads++;
              expect(adoptions, 1);
              expect(source.file.existsSync(), isFalse);
              expect(File(localFilePath).readAsBytesSync(), _bytes);
              final parent = await _within(
                fixture.messageRepo.getMessage(_messageId),
              );
              expect(parent?.quotedMessageId, 'thought:$_postId');
              final pending = await storedSticker();
              expect(pending.id, blobId);
              expect(pending.downloadStatus, 'upload_pending');
              final path = files.relativePathForAttachment(
                contactPeerId: recipientPeerId,
                blobId: blobId!,
                mime: mime,
              );
              final output = File('${directory.path}/$path');
              output.parent.createSync(recursive: true);
              output.writeAsBytesSync(_bytes);
              return UploadMediaSucceeded(
                pending.copyWith(
                  localPath: path,
                  downloadStatus: 'done',
                  contentHash: 'a' * 64,
                  encryptionKeyBase64: base64Encode(List<int>.filled(32, 1)),
                  encryptionNonce: base64Encode(List<int>.filled(12, 2)),
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                ),
              );
            },
      );
      expect(result, ThoughtReplyStatus.sent);
      final saved = await storedSticker();
      expectEncryptedSticker('catalog-a', saved);
      expect(
        File('${directory.path}/${saved.localPath}').readAsBytesSync(),
        _bytes,
      );
      expect(
        Directory('${directory.path}/pending_uploads/$_messageId').existsSync(),
        isFalse,
      );
      expect(await send(initial: false), ThoughtReplyStatus.sent);
      expect(
        await send(stickerId: 'different-catalog-item', initial: false),
        ThoughtReplyStatus.failed,
      );
      expect(uploads, 1);
      expect(await _within(fixture.db.query('messages')), hasLength(1));
      expect(encryptedPayloads, hasLength(1));
    },
  );

  test(
    'published strict custom sticker reopens and sends the exact quoted attachment',
    () async {
      var prepares = 0;
      var uploadReady = false;
      final attempts = <(String, String)>[];
      PreparedDirectMediaBlobCustodyCoordinator coordinator() =>
          PreparedDirectMediaBlobCustodyCoordinator(
            repository: fixture.repo,
            artifactStore: DirectMediaBlobArtifactStore(
              documentsDirectoryProvider: () async => directory,
            ),
            prepareArtifact: ({required bridge, required localFilePath}) async {
              prepares++;
              expect(File(localFilePath).readAsBytesSync(), _bytes);
              final file = File('${directory.path}/prepared-ciphertext')
                ..writeAsBytesSync(List<int>.generate(64, (index) => index));
              return EncryptedMediaArtifact(
                encryptedPath: file.path,
                keyBase64: base64Encode(List<int>.filled(32, 1)),
                nonce: base64Encode(List<int>.filled(12, 2)),
                scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                contentHash: sha256.convert(file.readAsBytesSync()).toString(),
                plaintextSize: _bytes.length,
              );
            },
            strictUpload:
                ({
                  required bridge,
                  required attachmentId,
                  required recipientPeerId,
                  required ciphertextPath,
                  required contentHash,
                  required ciphertextSize,
                }) async {
                  attempts.add((attachmentId, contentHash));
                  if (!uploadReady) return {'ok': false};
                  return {
                    'ok': true,
                    'id': attachmentId,
                    'storeStatus': 'stored',
                    'custodyKind': kDirectMediaBlobCustodyKind,
                    'custodyContract': kDirectMediaBlobCustodyContract,
                    'contentHash': contentHash,
                    'size': ciphertextSize,
                    'mime': kDirectMediaBlobTransportMime,
                    'expiresAtMs': now
                        .add(const Duration(days: 1))
                        .millisecondsSinceEpoch,
                    'custodyRelayPeerId': 'fixture-relay',
                  };
                },
          );

      expect(
        await send(
          stickerId: kCustomStickerMarkerId,
          coordinator: coordinator(),
        ),
        ThoughtReplyStatus.queued,
      );
      final pending = await storedSticker();
      expect(pending.stickerId, kCustomStickerMarkerId);
      expect(pending.downloadStatus, 'upload_pending');
      final rows = await _within(
        fixture.repo.loadDirectMediaBlobCustodyForMessage(_messageId),
      );
      expect(rows.single.attachmentId, pending.id);
      expect(encryptedPayloads, isEmpty);
      fixture = await _within(fixture.reopen());
      uploadReady = true;

      expect(
        await _within(
          retryIncompleteUploads(
            mediaAttachmentRepo: fixture.repo,
            messageRepo: fixture.messageRepo,
            bridge: bridge,
            p2pService: service,
            identityRepo: identities,
            contactRepo: contacts,
            mediaFileManager: files,
            directMediaBlobCustodyCoordinator: coordinator(),
            restrictToMessageIds: {_messageId},
          ),
        ),
        1,
      );
      final saved = await storedSticker();
      expectEncryptedSticker(kCustomStickerMarkerId, saved);
      expect(saved.id, pending.id);
      expect(attempts, [
        (pending.id, rows.single.contentHash),
        (pending.id, rows.single.contentHash),
      ]);
      expect(prepares, 1);
      expect(
        (await _within(
          fixture.messageRepo.getMessage(_messageId),
        ))?.quotedMessageId,
        'thought:$_postId',
      );
      expect(await _within(fixture.db.query('messages')), hasLength(1));
    },
  );

  test(
    'initialized roster refuses default sticker before staging or upload',
    () async {
      await _within(
        fixture.db.insert('direct_contact_device_roster_metadata', {
          'contact_account_peer_id': _author,
          'roster_initialized': 1,
          'legacy_target_state': 'active',
          'initialized_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        }),
      );
      expect(
        await send(adopted: () => fail('unexpected source adoption')),
        ThoughtReplyStatus.failed,
      );
      expect(source.file.existsSync(), isTrue);
      expect(encryptedPayloads, isEmpty);
      expect(await _within(fixture.db.query('messages')), isEmpty);
      expect(await _within(fixture.db.query('media_attachments')), isEmpty);
    },
  );
}

class _PathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _PathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
