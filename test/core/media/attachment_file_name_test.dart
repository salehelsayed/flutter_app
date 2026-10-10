import 'package:flutter_app/core/media/attachment_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeAttachmentFileName (414)', () {
    test('keeps a normal name', () {
      expect(
        sanitizeAttachmentFileName('Invoice 2026.pdf'),
        'Invoice 2026.pdf',
      );
    });

    test('drops path parts on both separators', () {
      expect(sanitizeAttachmentFileName('../../etc/passwd.pdf'), 'passwd.pdf');
      expect(sanitizeAttachmentFileName(r'C:\Users\x\a.pdf'), 'a.pdf');
    });

    test('removes bidi and control characters', () {
      expect(
        sanitizeAttachmentFileName('invoice\u202Efdp.exe'),
        'invoicefdp.exe',
      );
      expect(sanitizeAttachmentFileName('a\u2066b\u0000c\n.pdf'), 'abc.pdf');
    });

    test('caps a long name and keeps the extension', () {
      final result = sanitizeAttachmentFileName('${'a' * 300}.pdf')!;
      expect(result.length, kMaxAttachmentFileNameLength);
      expect(result.endsWith('.pdf'), isTrue);
    });

    test('never ends on half a surrogate pair', () {
      final name = '${'a' * 115}\u{1F600}\u{1F600}.pdf';
      final result = sanitizeAttachmentFileName(name)!;
      final beforeExt = result.codeUnitAt(result.length - 5);
      expect(beforeExt >= 0xD800 && beforeExt <= 0xDBFF, isFalse);
      expect(result.endsWith('.pdf'), isTrue);
    });

    test('returns null when nothing usable is left', () {
      expect(sanitizeAttachmentFileName(null), isNull);
      expect(sanitizeAttachmentFileName(42), isNull);
      expect(sanitizeAttachmentFileName(''), isNull);
      expect(sanitizeAttachmentFileName('dir/'), isNull);
      expect(sanitizeAttachmentFileName('..'), isNull);
      expect(sanitizeAttachmentFileName('\u202E'), isNull);
    });
  });
}
