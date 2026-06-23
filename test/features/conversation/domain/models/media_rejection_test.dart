import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/conversation/domain/models/media_rejection.dart';

// 149 TC-06: the size/GIF SEND gate is a PURE, collection-returning function
// shared by the 1:1 and group composers. It must mark EVERY failing index
// (not just the first), carry the index + a normalized reason, and iterate the
// list itself (no GroupMediaSizePolicy.validateAttachments index loss).
void main() {
  // Resolve a mime from the file extension, mirroring the composers'
  // `_mimeFromPath` for the types under test.
  String? mimeResolver(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  PendingComposerMedia media(String name, int budgetBytes) =>
      PendingComposerMedia(file: File(name), budgetBytes: budgetBytes);

  group('collectPendingMediaSizeRejections', () {
    test('marks EVERY failing index with a normalized {index, reason}', () {
      final rejections = collectPendingMediaSizeRejections(
        [
          media('valid.jpg', 1024), // index 0 — small image, valid
          media('big.mp4', 300 * 1024 * 1024), // index 1 — > 250 MB video cap
          media('big.gif', 30 * 1024 * 1024), // index 2 — > 25 MB GIF cap
        ],
        mimeResolver,
      );

      expect(rejections, hasLength(2));
      expect(
        rejections,
        containsAll(const [
          MediaRejection(index: 1, reason: 'too_large'),
          MediaRejection(index: 2, reason: 'gif_too_large'),
        ]),
      );
      // The valid index is NOT marked.
      expect(rejections.any((r) => r.index == 0), isFalse);
    });

    test('returns empty when every attachment is within its per-type cap', () {
      final rejections = collectPendingMediaSizeRejections(
        [media('a.jpg', 1024), media('b.mp4', 1024), media('c.gif', 1024)],
        mimeResolver,
      );
      expect(rejections, isEmpty);
    });

    test('normalizes every non-GIF per-type size reason to too_large', () {
      final rejections = collectPendingMediaSizeRejections(
        [
          media('img.jpg', 30 * 1024 * 1024), // > 25 MB image cap
          media('vid.mp4', 300 * 1024 * 1024), // > 250 MB video cap
        ],
        mimeResolver,
      );
      expect(rejections.map((r) => r.reason).toSet(), {'too_large'});
      expect(rejections.map((r) => r.index).toList(), [0, 1]);
    });
  });
}
