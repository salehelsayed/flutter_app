import 'package:flutter_app/core/media/media_mime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mimeFromPath (414)', () {
    test('pdf maps to application/pdf in any case', () {
      expect(mimeFromPath('/tmp/Report.PDF'), kPdfMime);
      expect(mimeFromPath('a.b.pdf'), kPdfMime);
    });

    test('every extension the old private copies knew maps the same', () {
      // The 1:1 composer, group composer and share batch copies before 414.
      const legacy = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'heic': 'image/heic',
        'heif': 'image/heic',
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'avi': 'video/x-msvideo',
        'mkv': 'video/x-matroska',
        'm4v': 'video/x-m4v',
        'm4a': 'audio/mp4',
        'aac': 'audio/aac',
      };
      for (final entry in legacy.entries) {
        expect(mimeFromPath('x.${entry.key}'), entry.value, reason: entry.key);
      }
    });

    test('unknown extensions and paths without one stay octet-stream', () {
      expect(mimeFromPath('x.docx'), kUnknownMediaMime);
      expect(mimeFromPath('x.zip'), kUnknownMediaMime);
      expect(mimeFromPath('noextension'), kUnknownMediaMime);
    });
  });

  group('isSupportedDocumentMime (414 D1)', () {
    test('accepts only application/pdf', () {
      expect(isSupportedDocumentMime('application/pdf'), isTrue);
      expect(isSupportedDocumentMime(' Application/PDF '), isTrue);
      expect(isSupportedDocumentMime('application/octet-stream'), isFalse);
      expect(isSupportedDocumentMime('application/zip'), isFalse);
      expect(isSupportedDocumentMime('image/jpeg'), isFalse);
      expect(isSupportedDocumentMime(null), isFalse);
    });
  });

  group('hasPdfSignature', () {
    test('matches %PDF- only', () {
      expect(hasPdfSignature('%PDF-1.7\n'.codeUnits), isTrue);
      expect(hasPdfSignature('%PDF'.codeUnits), isFalse);
      expect(hasPdfSignature('PK\u0003\u0004'.codeUnits), isFalse);
      expect(hasPdfSignature(const []), isFalse);
    });
  });
}
