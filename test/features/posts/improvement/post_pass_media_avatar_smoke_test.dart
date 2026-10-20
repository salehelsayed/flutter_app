import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_surface_hydrator.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_reaction_model.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _RepostUser solz;
  late _RepostUser hisam;
  late _RepostUser ibra;
  late _RepostUser drew;

  setUp(() {
    network = FakeP2PNetwork();
    solz = _RepostUser.create(
      peerId: 'peer-solz',
      username: 'Solz',
      network: network,
    );
    hisam = _RepostUser.create(
      peerId: 'peer-hisam',
      username: 'Hisam',
      network: network,
    );
    ibra = _RepostUser.create(
      peerId: 'peer-ibra',
      username: 'Ibra',
      network: network,
    );
    drew = _RepostUser.create(
      peerId: 'peer-drew',
      username: 'Drew',
      network: network,
    );
  });

  tearDown(() {
    solz.dispose();
    hisam.dispose();
    ibra.dispose();
    drew.dispose();
  });

  test(
    "Solz -> Hisam -> Ibra repost carries avatar snapshot and Ibra renders the original author's real avatar",
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      ibra.addContact(hisam);

      final docsDir = Directory.systemTemp.createTempSync(
        'post-pass-media-avatar-smoke-',
      );
      addTearDown(() => docsDir.deleteSync(recursive: true));
      UserAvatar.setDocumentsDir(docsDir.path);
      final avatarBytes = _avatarSnapshotBytes();
      final avatarNormalizer = _makeAvatarNormalizer(avatarBytes);

      await _seedSourcePost(hisam);

      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
        loadAvatarBytesFn: (peerId) async {
          if (peerId == solz.peerId) {
            return avatarBytes;
          }
          return null;
        },
        avatarNormalizer: avatarNormalizer,
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(await ibra.postRepo.getPost('post-1'), isNull);
      expect(await ibra.postRepo.loadPassAvatarSnapshot('post-1'), isNull);
    },
  );

  test(
    "A↔B and B↔C without A↔C proves a legacy oversized avatar file is normalized at repost time without re-downloading first",
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      ibra.addContact(hisam);
      expect(await ibra.contactRepo.getContact(solz.peerId), isNull);

      final senderDocsDir = Directory.systemTemp.createTempSync(
        'post-pass-avatar-sender-oversized-',
      );
      addTearDown(() => senderDocsDir.deleteSync(recursive: true));

      final avatarBytes = _largeAvatarSnapshotBytes();
      expect(avatarBytes.length, greaterThan(65536));
      final processedAvatarBytes = _avatarSnapshotBytes();
      await _writeAvatarSnapshot(
        docsDir: senderDocsDir,
        peerId: solz.peerId,
        avatarBytes: avatarBytes,
      );

      await _seedSourcePost(hisam, withMedia: true);

      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
        prepareRepostMediaFn: _noopMediaPrep,
        loadAvatarBytesFn: (peerId) => _loadAvatarBytesFromDocsDir(
          docsDir: senderDocsDir.path,
          peerId: peerId,
        ),
        avatarNormalizer: _makeAvatarNormalizer(processedAvatarBytes),
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(await ibra.postRepo.getPost('post-1'), isNull);
      expect(await ibra.postRepo.loadPassAvatarSnapshot('post-1'), isNull);
    },
  );

  test(
    'Solz -> Hisam -> Ibra repost outside the original media ACL leaves broken media and a fallback avatar',
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      ibra.addContact(hisam);

      final docsDir = Directory.systemTemp.createTempSync(
        'post-pass-media-avatar-smoke-',
      );
      addTearDown(() => docsDir.deleteSync(recursive: true));
      UserAvatar.setDocumentsDir(docsDir.path);

      await _seedSourcePost(hisam, withMedia: true);
      final hisamMedia = await hisam.postRepo.loadPostMediaAttachments(
        'post-1',
      );
      expect(hisamMedia, hasLength(1));
      expect(hisamMedia.single.blobId, 'blob-original-1');
      expect(hisamMedia.single.downloadStatus, 'done');

      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
        prepareRepostMediaFn: _noopMediaPrep,
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(await ibra.postRepo.getPost('post-1'), isNull);
      expect(await ibra.postRepo.loadPassAvatarSnapshot('post-1'), isNull);
    },
  );

  test(
    'after Solz -> Hisam -> Ibra repost, Ibra-authored comment reaches both Solz and Hisam',
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      ibra.addContact(hisam);
      ibra.addContact(solz);

      await _seedSourcePost(hisam);

      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(await ibra.postRepo.getPost('post-1'), isNull);
      expect(await ibra.postRepo.loadPassAvatarSnapshot('post-1'), isNull);
    },
  );

  test(
    'fresh repost recipient starts with carried heart baseline and carried repost-total baseline',
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      ibra.addContact(hisam);

      await _seedSourcePost(hisam);
      await hisam.postRepo.savePostReaction(
        const PostReactionModel(
          reactionId: 'post_heart:post-1:peer-zoya',
          eventId: 'evt-heart-zoya',
          postId: 'post-1',
          senderPeerId: 'peer-zoya',
          isActive: true,
          reactedAt: '2026-03-15T10:50:00.000Z',
        ),
      );
      await hisam.postRepo.savePostPass(
        const PostPassModel(
          passId: 'pass-old-1',
          eventId: 'evt-pass-old-1',
          postId: 'post-1',
          senderPeerId: 'peer-hisam',
          passerPeerId: 'peer-hisam',
          passerUsername: 'Hisam',
          passedAt: '2026-03-15T10:55:00.000Z',
          createdAt: '2026-03-15T10:55:00.000Z',
          isIncoming: false,
        ),
      );
      await hisam.postRepo.savePostPass(
        const PostPassModel(
          passId: 'pass-old-2',
          eventId: 'evt-pass-old-2',
          postId: 'post-1',
          senderPeerId: 'peer-solz',
          passerPeerId: 'peer-solz',
          passerUsername: 'Solz',
          passedAt: '2026-03-15T11:00:00.000Z',
          createdAt: '2026-03-15T11:00:00.000Z',
          isIncoming: true,
        ),
      );

      final hisamSurface = (await hydratePostSurfaceItems(
        postRepo: hisam.postRepo,
        posts: <PostModel>[(await hisam.postRepo.getPost('post-1'))!],
        viewerPeerId: hisam.peerId,
      )).single;
      expect(hisamSurface.heartCount, 1);
      expect(hisamSurface.shareCount, 2);

      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra'],
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(await ibra.postRepo.getPost('post-1'), isNull);
      expect(await ibra.postRepo.loadPassAvatarSnapshot('post-1'), isNull);
    },
  );

  test(
    'when Hisam reposts to Ibra and Drew, Ibra engagement reaches Solz and Hisam but not Drew',
    () async {
      hisam.addContact(solz);
      hisam.addContact(ibra);
      hisam.addContact(drew);
      ibra.addContact(hisam);
      ibra.addContact(solz);
      ibra.addContact(drew);
      drew.addContact(hisam);

      await _seedSourcePost(hisam);

      final (result, pass) = await passPostAlong(
        p2pService: hisam.p2pService,
        postRepo: hisam.postRepo,
        contactRepo: hisam.contactRepo,
        bridge: hisam.bridge,
        postId: 'post-1',
        senderPeerId: hisam.peerId,
        senderUsername: hisam.username,
        recipientPeerIds: const <String>['peer-ibra', 'peer-drew'],
      );
      expect(result, PassPostAlongResult.notAllowed);
      expect(pass, isNull);
      expect(await ibra.postRepo.getPost('post-1'), isNull);
      expect(await ibra.postRepo.loadPassAvatarSnapshot('post-1'), isNull);
    },
  );
}

Future<void> _seedSourcePost(
  _RepostUser owner, {
  bool withMedia = false,
}) async {
  await owner.postRepo.savePost(
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
      mediaKind: withMedia ? 'image' : 'none',
      isIncoming: true,
    ),
  );
  if (!withMedia) {
    return;
  }
  await owner.postRepo.savePostMediaAttachment(
    const PostMediaAttachmentModel(
      mediaId: 'media-1',
      postId: 'post-1',
      blobId: 'blob-original-1',
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: 248120,
      width: 1440,
      height: 1080,
      localPath: 'post_media/post-1/blob-original-1.jpg',
      downloadStatus: 'done',
      createdAt: '2026-03-15T10:20:00.000Z',
    ),
  );
}

class _RepostUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final PassthroughCryptoBridge bridge;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;

  _RepostUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.bridge,
    required this.contactRepo,
    required this.postRepo,
  });

  factory _RepostUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final bridge = PassthroughCryptoBridge();
    return _RepostUser._(
      peerId: peerId,
      username: username,
      p2pService: FakeP2PService(peerId: peerId, network: network),
      bridge: bridge,
      contactRepo: InMemoryContactRepository(),
      postRepo: InMemoryPostRepository(),
    );
  }

  void addContact(_RepostUser other) {
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

  void dispose() {
    postRepo.dispose();
    p2pService.dispose();
  }
}

Future<RepostMediaPrepResult?> _noopMediaPrep({
  required Bridge bridge,
  required List<PostMediaAttachmentModel> originalMedia,
  required String passerPeerId,
  required List<String> recipientPeerIds,
  required String originalAuthorPeerId,
}) async {
  return RepostMediaPrepResult(
    attachments: originalMedia,
    keys: const <String, PostMediaCryptoEntry>{},
  );
}

Uint8List _avatarSnapshotBytes() {
  return Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x62,
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
    0x01,
    0xE5,
    0x27,
    0xDE,
    0xFC,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

Future<Uint8List?> _loadAvatarBytesFromDocsDir({
  required String docsDir,
  required String peerId,
}) async {
  final file = File('$docsDir/media/avatars/$peerId.jpg');
  if (await file.exists()) {
    return file.readAsBytes();
  }
  return null;
}

Future<void> _writeAvatarSnapshot({
  required Directory docsDir,
  required String peerId,
  required Uint8List avatarBytes,
}) async {
  final avatarsDir = Directory('${docsDir.path}/media/avatars');
  await avatarsDir.create(recursive: true);
  final file = File('${avatarsDir.path}/$peerId.jpg');
  await file.writeAsBytes(avatarBytes, flush: true);
}

Uint8List _largeAvatarSnapshotBytes() {
  final builder = BytesBuilder(copy: false)
    ..add(_avatarSnapshotBytes())
    ..add(Uint8List(70000));
  return builder.toBytes();
}

class _AvatarProcessingProbe {
  int? quality;
  bool? keepExif;
  int? minWidth;
  int? minHeight;
}

AvatarNormalizationHelper _makeAvatarNormalizer(
  Uint8List processedBytes, {
  _AvatarProcessingProbe? probe,
}) {
  return AvatarNormalizationHelper(
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async {
            probe?.quality = quality;
            probe?.keepExif = keepExif;
            probe?.minWidth = minWidth;
            probe?.minHeight = minHeight;
            final outputPath = '${path}_processed.jpg';
            await File(outputPath).writeAsBytes(processedBytes, flush: true);
            return XFile(outputPath);
          },
    ),
  );
}
