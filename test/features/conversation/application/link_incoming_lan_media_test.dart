import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/conversation/application/link_incoming_local_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

/// FDC-15 (receive leg) — a Go `media:lan_received` payload is mapped via the
/// NEW `LocalMediaReady.fromJson` factory and fed to the EXISTING
/// `linkIncomingLocalMedia` → `<canonical>.enc` → decrypt-adopt pipeline. The Go
/// side already staged the ciphertext to a temp path, so `persistMedia` just
/// hands that path back (mirrors the production main.dart wiring).
void main() {
  MediaAttachment encPendingAttachment() =>
      MediaAttachment(
        id: 'media-1',
        messageId: 'msg-1',
        mime: 'image/jpeg',
        size: 272,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: '2026-05-30T00:00:00.000Z',
      ).copyWith(
        encryptionKeyBase64: 'k',
        encryptionNonce: 'n',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

  test('TD9: media:lan_received → LocalMediaReady.fromJson → staged at '
      '<canonical>.enc, row stays pending, Go temp consumed', () async {
    final repo = InMemoryMediaAttachmentRepository();
    await repo.saveAttachment(
      encPendingAttachment(),
      owner: MediaOwnerLane.direct,
    );

    final fileManager = FakeMediaFileManager();
    final scratch = Directory.systemTemp.createTempSync('fdc15_td9_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final ciphertext = List<int>.filled(272, 7);
    final goStaged = File('${scratch.path}/go-staged-blob')
      ..writeAsBytesSync(ciphertext);

    // The Go media:lan_received payload (TL11 shape), parsed via the NEW factory.
    final media = LocalMediaReady.fromJson(<String, dynamic>{
      'id': 'media-1',
      'from': 'peer-A',
      'to': 'peer-self',
      'mime': 'application/octet-stream',
      'size': 272,
      'localPath': goStaged.path,
      'sha256': 'abc123',
      'enc': true,
      'encScheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      'durationMs': 0,
    });
    expect(media.id, 'media-1');
    expect(media.localPath, goStaged.path);
    expect(media.enc, isTrue);
    expect(media.encScheme, kMediaAttachmentEncryptionSchemeBlobAesGcmV1);

    final outcome = await linkIncomingLocalMedia(
      media: media,
      mediaAttachmentRepo: repo,
      // The Go node already staged the ciphertext; hand its path straight back.
      persistMedia: (mediaId, fromPeerId) async => media.localPath,
      mediaFileManager: fileManager,
    );

    expect(outcome, LinkLocalMediaOutcome.stagedForDecrypt);

    final absolutePath = await fileManager.localPathForAttachment(
      contactPeerId: 'peer-A',
      blobId: 'media-1',
      mime: 'image/jpeg',
    );
    final staged = File('$absolutePath.enc');
    addTearDown(() {
      if (staged.existsSync()) staged.deleteSync();
    });
    expect(staged.existsSync(), isTrue);
    expect(staged.readAsBytesSync(), ciphertext);
    // The Go temp was consumed by the rename to <canonical>.enc.
    expect(goStaged.existsSync(), isFalse);

    // Completion happens ONLY via decrypt-adopt — the row stays pending.
    final stored = (await repo.getAttachmentsForMessage(
      'msg-1',
      owner: MediaOwnerLane.direct,
    )).single;
    expect(stored.localPath, isNull);
    expect(stored.downloadStatus, 'pending');
  });

  test(
    'TD9b (control): LocalMediaReady.fromJson preserves enc/encScheme so the '
    'bytes are staged for decrypt-adopt, never rendered raw',
    () {
      final media = LocalMediaReady.fromJson(<String, dynamic>{
        'id': 'm',
        'from': 'p',
        'to': 's',
        'mime': 'application/octet-stream',
        'size': 1,
        'localPath': '/tmp/x',
        'sha256': 'h',
        'enc': true,
        'encScheme': 'blob-aes-gcm-v1',
      });
      expect(media.enc, isTrue);
      expect(media.encScheme, 'blob-aes-gcm-v1');
    },
  );
}
