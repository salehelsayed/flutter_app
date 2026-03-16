import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_upload_recovery_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../bridge/fake_bridge.dart';
import 'fake_p2p_service.dart';
import '../../shared/fakes/in_memory_post_repository.dart';

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

PostModel _post({
  required String id,
  required String mediaKind,
  String deliveryStatus = 'failed',
}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-self',
    authorPeerId: 'peer-self',
    authorUsername: 'Alice',
    text: '',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-16T10:00:00.000Z',
    visibleAt: '2026-03-16T10:00:00.000Z',
    expiresAt: '2026-03-19T10:00:00.000Z',
    isIncoming: false,
    deliveryStatus: deliveryStatus,
    mediaKind: mediaKind,
  );
}

void main() {
  late FakeP2PService p2pService;
  late InMemoryPostRepository posts;
  late FakeContactRepository contacts;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;
  late Directory tempDir;

  setUp(() async {
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-self',
        circuitAddresses: <String>['/p2p-circuit/addr1'],
      ),
    );
    posts = InMemoryPostRepository();
    contacts = FakeContactRepository();
    secureKeyStore = FakeSecureKeyStore();
    imageProcessor = ImageProcessor(
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
    );
    tempDir = await Directory.systemTemp.createTemp('phase7-media-retry');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    posts.dispose();
    p2pService.dispose();
  });

  test(
    'start while already online runs one immediate media recovery pass',
    () async {
      final localFile = File('${tempDir.path}/photo.jpg');
      await localFile.writeAsString('phase7');
      contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      await posts.savePost(_post(id: 'post-1', mediaKind: 'image'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-16T10:00:01.000Z',
          deliveryPath: 'failed',
          lastError: 'direct_and_inbox_failed',
          createdAt: '2026-03-16T10:00:01.000Z',
          updatedAt: '2026-03-16T10:00:01.000Z',
        ),
      );
      await posts.replacePostMediaUploadRecoveryItems(
        'post-1',
        <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-1',
            position: 0,
            localFilePath: localFile.path,
            mime: 'image/jpeg',
            kind: 'image',
            createdAt: '2026-03-16T10:00:00.000Z',
          ),
        ],
      );

      final retrier = PendingPostMediaUploadRetrier(
        p2pService: p2pService,
        postRepo: posts,
        contactRepo: contacts,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        bridge: FakeBridge(),
        retryDebounce: Duration.zero,
        periodicRetryInterval: const Duration(hours: 1),
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
                sizeBytes: 100,
                width: width,
                height: height,
                localPath: 'post_media/$postId/blob-1.jpg',
                downloadStatus: 'done',
                createdAt: '2026-03-16T10:00:02.000Z',
              );
            },
      );

      retrier.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(await posts.loadPostMediaUploadRecoveryItems('post-1'), isEmpty);
      expect(await posts.loadPostMediaAttachments('post-1'), hasLength(1));
      expect((await posts.getPost('post-1'))!.deliveryStatus, 'sent');

      retrier.dispose();
    },
  );

  test(
    'missing local file becomes a terminal failed post instead of retrying forever',
    () async {
      contacts.seed(<ContactModel>[_contact('peer-bob', 'Bob')]);
      await posts.savePost(_post(id: 'post-missing', mediaKind: 'image'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-missing',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-16T10:00:01.000Z',
          deliveryPath: 'failed',
          lastError: 'direct_and_inbox_failed',
          createdAt: '2026-03-16T10:00:01.000Z',
          updatedAt: '2026-03-16T10:00:01.000Z',
        ),
      );
      await posts.replacePostMediaUploadRecoveryItems(
        'post-missing',
        const <PostMediaUploadRecoveryItem>[
          PostMediaUploadRecoveryItem(
            postId: 'post-missing',
            position: 0,
            localFilePath: '/tmp/does-not-exist-phase7.jpg',
            mime: 'image/jpeg',
            kind: 'image',
            createdAt: '2026-03-16T10:00:00.000Z',
          ),
        ],
      );

      final retried = await retryPendingPostMediaUploads(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: p2pService,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        bridge: FakeBridge(),
      );
      final retriedAgain = await retryPendingPostMediaUploads(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: p2pService,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        bridge: FakeBridge(),
      );

      expect(retried, 1);
      expect(retriedAgain, 0);
      expect(
        await posts.loadPostMediaUploadRecoveryItems('post-missing'),
        isEmpty,
      );
      expect(await posts.loadPostMediaAttachments('post-missing'), isEmpty);
      expect((await posts.getPost('post-missing'))!.deliveryStatus, 'failed');
    },
  );
}
