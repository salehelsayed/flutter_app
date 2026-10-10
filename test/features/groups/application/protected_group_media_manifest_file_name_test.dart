import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

ProtectedGroupMediaAttachmentCommitment _commitment({
  String mime = 'application/pdf',
  String mediaType = 'file',
  String? fileName,
}) {
  return ProtectedGroupMediaAttachmentCommitment(
    attachmentId: 'att-1',
    custodyBlobId: 'blob-1',
    ciphertextSha256: 'a' * 64,
    ciphertextSize: 4096,
    mime: mime,
    mediaType: mediaType,
    encryptionKeyBase64: 'key',
    encryptionNonce: 'nonce',
    fileName: fileName,
    targets: [
      GroupMediaBlobTargetCommitment(
        recipientPeerId: 'peer-b',
        expiresAtMs: 1000,
      ),
    ],
  );
}

ProtectedGroupMediaAttachmentCommitment _parse(Map<String, Object?> json) {
  return ProtectedGroupMediaAttachmentCommitment.fromJson(
    json,
    recipientPeerIds: const ['peer-b'],
    custodyKind: groupMediaBlobCustodyKind,
    custodyContract: groupMediaBlobCustodyContract,
  );
}

void main() {
  group('strict group media commitment fileName (414)', () {
    test('a document name round-trips through the signed JSON', () {
      final json = _commitment(fileName: 'Invoice.pdf').toJson();
      expect(json['fileName'], 'Invoice.pdf');
      expect(_parse(json).fileName, 'Invoice.pdf');
      expect(_parse(json).toJson(), json);
    });

    test('image commitments keep the exact pre-414 key set', () {
      final json = _commitment(mime: 'image/jpeg', mediaType: 'image').toJson();
      expect(json.containsKey('fileName'), isFalse);
      expect(_parse(json).fileName, isNull);
    });

    test('an unclean name fails closed on both sides', () {
      expect(() => _commitment(fileName: '../evil.pdf'), throwsArgumentError);
      final json = _commitment(fileName: 'ok.pdf').toJson()
        ..['fileName'] = 'in\u202Efdp.exe';
      expect(() => _parse(json), throwsArgumentError);
    });
  });
}
