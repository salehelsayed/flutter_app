import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService aliceService;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late FakeSecureKeyStore secureKeyStore;
  late FakeMediaFileManager mediaFileManager;

  setUp(() {
    network = FakeP2PNetwork();
    aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    secureKeyStore = FakeSecureKeyStore();
    mediaFileManager = FakeMediaFileManager();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'sends image posts with media metadata in the post_create payload',
    () async {
      await secureKeyStore.write(
        ImageQualityPreference.storageKey,
        ImageQualityPreference.original.toStorageString(),
      );

      final (result, post) = await sendPost(
        p2pService: aliceService,
        postRepo: posts,
        contactRepo: contacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Photo post',
        audience: PostAudience.allFriends(),
        mediaDrafts: const [
          PostMediaDraft(
            localFilePath: '/tmp/image.jpg',
            mime: 'image/jpeg',
            width: 1440,
            height: 1080,
          ),
        ],
        secureKeyStore: secureKeyStore,
        imageProcessor: ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                return XFile('${path}_processed');
              },
        ),
        mediaFileManager: mediaFileManager,
        uploadPostMediaFn:
            ({
              required postId,
              required localFilePath,
              required mime,
              required allowedPeers,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
            }) async {
              return PostMediaAttachmentModel(
                mediaId: 'media-1',
                postId: postId,
                blobId: 'blob-1',
                kind: 'image',
                mime: mime,
                sizeBytes: 248120,
                width: width,
                height: height,
                localPath: 'post_media/$postId/blob-1.jpg',
                downloadStatus: 'done',
                createdAt: '2026-03-15T10:20:00.000Z',
              );
            },
      );

      expect(result, SendPostResult.success);
      expect(post, isNotNull);
      expect(post!.mediaKind, 'image');
      expect(await posts.loadPostMediaAttachments(post.id), hasLength(1));

      final inboxMessage =
          network.retrieveInbox('peer-bob').single['message'] as String;
      final payload = jsonDecode(inboxMessage) as Map<String, dynamic>;
      final snapshot = payload['payload']['snapshot'] as Map<String, dynamic>;
      expect(snapshot['media_kind'], 'image');
      expect(snapshot['media'], hasLength(1));
      expect(snapshot['media'][0]['blob_id'], 'blob-1');
    },
  );

  test('allows voice-only posts when media is attached', () async {
    final (result, post) = await sendPost(
      p2pService: aliceService,
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      text: '',
      audience: PostAudience.allFriends(),
      mediaDrafts: const [
        PostMediaDraft(
          localFilePath: '/tmp/voice.m4a',
          mime: 'audio/mp4',
          durationMs: 5000,
          waveform: [0.2, 0.4, 0.8],
        ),
      ],
      secureKeyStore: secureKeyStore,
      imageProcessor: ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async {
              return XFile('${path}_processed');
            },
      ),
      mediaFileManager: mediaFileManager,
      uploadPostMediaFn:
          ({
            required postId,
            required localFilePath,
            required mime,
            required allowedPeers,
            mediaFileManager,
            width,
            height,
            durationMs,
            waveform,
          }) async {
            return PostMediaAttachmentModel(
              mediaId: 'media-voice-1',
              postId: postId,
              blobId: 'blob-voice-1',
              kind: 'voice',
              mime: mime,
              sizeBytes: 48000,
              durationMs: durationMs,
              waveform: waveform,
              localPath: 'post_media/$postId/blob-voice-1.m4a',
              downloadStatus: 'done',
              createdAt: '2026-03-15T10:20:00.000Z',
            );
          },
    );

    expect(result, SendPostResult.success);
    expect(post, isNotNull);
    expect(post!.mediaKind, 'voice');
    expect(post.text, isEmpty);
  });
}

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
  );
}
