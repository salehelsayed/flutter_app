import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';

void main() {
  group('stripBidiCharacters', () {
    test('removes zero-width space (U+200B)', () {
      expect(stripBidiCharacters('hello\u200Bworld'), 'helloworld');
    });

    test('removes ZWNJ (U+200C)', () {
      expect(stripBidiCharacters('hello\u200Cworld'), 'helloworld');
    });

    test('removes LRM (U+200E) and RLM (U+200F)', () {
      expect(stripBidiCharacters('hello\u200E\u200Fworld'), 'helloworld');
    });

    test('removes bidi embedding/override (U+202A-202E)', () {
      expect(
        stripBidiCharacters('ab\u202A\u202B\u202C\u202D\u202Ecd'),
        'abcd',
      );
    });

    test('removes bidi isolate (U+2066-2069)', () {
      expect(
        stripBidiCharacters('ab\u2066\u2067\u2068\u2069cd'),
        'abcd',
      );
    });

    test('removes ALM (U+061C)', () {
      expect(stripBidiCharacters('hello\u061Cworld'), 'helloworld');
    });

    test('removes BOM (U+FEFF)', () {
      expect(stripBidiCharacters('\uFEFFhello'), 'hello');
    });

    test('preserves ZWJ (U+200D) for emoji sequences', () {
      // Family emoji: man + ZWJ + woman + ZWJ + girl
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      expect(stripBidiCharacters(family), family);
    });

    test('handles empty string', () {
      expect(stripBidiCharacters(''), '');
    });

    test('handles string of only bidi characters', () {
      expect(stripBidiCharacters('\u200B\u200C\u200E\u202A\uFEFF'), '');
    });

    test('preserves normal text', () {
      expect(stripBidiCharacters('Hello, World!'), 'Hello, World!');
    });
  });

  group('isMessageTooLong', () {
    test('returns false for text at exactly maxMessageLength', () {
      final text = 'a' * maxMessageLength;
      expect(isMessageTooLong(text), false);
    });

    test('returns true for text exceeding maxMessageLength', () {
      final text = 'a' * (maxMessageLength + 1);
      expect(isMessageTooLong(text), true);
    });

    test('returns false for short text', () {
      expect(isMessageTooLong('hello'), false);
    });

    test('returns false for empty text', () {
      expect(isMessageTooLong(''), false);
    });
  });

  group('isValidUsername', () {
    test('accepts lowercase letters', () {
      expect(isValidUsername('alice'), true);
    });

    test('accepts uppercase letters', () {
      expect(isValidUsername('Alice'), true);
    });

    test('accepts digits', () {
      expect(isValidUsername('alice123'), true);
    });

    test('accepts underscores', () {
      expect(isValidUsername('alice_bob'), true);
    });

    test('accepts hyphens', () {
      expect(isValidUsername('alice-bob'), true);
    });

    test('accepts dots', () {
      expect(isValidUsername('alice.bob'), true);
    });

    test('accepts mixed valid characters', () {
      expect(isValidUsername('Alice_Bob-99.x'), true);
    });

    test('rejects spaces', () {
      expect(isValidUsername('alice bob'), false);
    });

    test('rejects emoji', () {
      expect(isValidUsername('alice\u{1F600}'), false);
    });

    test('rejects bidi characters', () {
      expect(isValidUsername('alice\u200B'), false);
    });

    test('rejects empty string', () {
      expect(isValidUsername(''), false);
    });

    test('rejects special characters', () {
      expect(isValidUsername('alice@bob'), false);
      expect(isValidUsername('alice/bob'), false);
      expect(isValidUsername('alice#1'), false);
    });
  });

  group('sanitizeMessageText', () {
    test('strips bidi characters from message', () {
      expect(sanitizeMessageText('hello\u200Bworld'), 'helloworld');
    });

    test('preserves normal text', () {
      expect(sanitizeMessageText('Hello, World!'), 'Hello, World!');
    });
  });

  group('sanitizeUsername', () {
    test('strips bidi characters from username', () {
      expect(sanitizeUsername('alice\u200B'), 'alice');
    });

    test('truncates to maxUsernameLength', () {
      final longName = 'a' * 30;
      expect(sanitizeUsername(longName).length, maxUsernameLength);
    });

    test('does not truncate username at or under limit', () {
      final name = 'a' * maxUsernameLength;
      expect(sanitizeUsername(name), name);
    });

    test('strips bidi then truncates', () {
      // 18 chars + 5 bidi = 23 chars input; after strip = 18 chars (under limit)
      final name = 'a' * 18 + '\u200B' * 5;
      expect(sanitizeUsername(name), 'a' * 18);
    });
  });
}
