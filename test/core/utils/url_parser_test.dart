import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/url_parser.dart';

void main() {
  group('parseUrls', () {
    test('plain text returns single plain segment', () {
      final result = parseUrls('Hello world');
      expect(result, hasLength(1));
      expect(result[0].text, 'Hello world');
      expect(result[0].isUrl, isFalse);
    });

    test('empty string returns single empty segment', () {
      final result = parseUrls('');
      expect(result, hasLength(1));
      expect(result[0].text, '');
      expect(result[0].isUrl, isFalse);
    });

    test('https URL alone', () {
      final result = parseUrls('https://example.com');
      expect(result, hasLength(1));
      expect(result[0].text, 'https://example.com');
      expect(result[0].isUrl, isTrue);
    });

    test('http URL alone', () {
      final result = parseUrls('http://example.com');
      expect(result, hasLength(1));
      expect(result[0].text, 'http://example.com');
      expect(result[0].isUrl, isTrue);
    });

    test('URL at start of text', () {
      final result = parseUrls('https://example.com is a site');
      expect(result, hasLength(2));
      expect(result[0].text, 'https://example.com');
      expect(result[0].isUrl, isTrue);
      expect(result[1].text, ' is a site');
      expect(result[1].isUrl, isFalse);
    });

    test('URL in middle of text', () {
      final result = parseUrls('Visit https://example.com for info');
      expect(result, hasLength(3));
      expect(result[0].text, 'Visit ');
      expect(result[0].isUrl, isFalse);
      expect(result[1].text, 'https://example.com');
      expect(result[1].isUrl, isTrue);
      expect(result[2].text, ' for info');
      expect(result[2].isUrl, isFalse);
    });

    test('URL at end of text', () {
      final result = parseUrls('Go to https://example.com');
      expect(result, hasLength(2));
      expect(result[0].text, 'Go to ');
      expect(result[0].isUrl, isFalse);
      expect(result[1].text, 'https://example.com');
      expect(result[1].isUrl, isTrue);
    });

    test('URL with path', () {
      final result = parseUrls('https://example.com/path/to/page');
      expect(result, hasLength(1));
      expect(result[0].text, 'https://example.com/path/to/page');
      expect(result[0].isUrl, isTrue);
    });

    test('URL with query params', () {
      final result = parseUrls('https://example.com/search?q=dart&lang=en');
      expect(result, hasLength(1));
      expect(result[0].text, 'https://example.com/search?q=dart&lang=en');
      expect(result[0].isUrl, isTrue);
    });

    test('URL with fragment', () {
      final result = parseUrls('https://example.com/page#section');
      expect(result, hasLength(1));
      expect(result[0].text, 'https://example.com/page#section');
      expect(result[0].isUrl, isTrue);
    });

    test('URL with port', () {
      final result = parseUrls('https://example.com:8080/api');
      expect(result, hasLength(1));
      expect(result[0].text, 'https://example.com:8080/api');
      expect(result[0].isUrl, isTrue);
    });

    test('www URL without scheme', () {
      final result = parseUrls('www.example.com');
      expect(result, hasLength(1));
      expect(result[0].text, 'www.example.com');
      expect(result[0].isUrl, isTrue);
    });

    test('www URL with path', () {
      final result = parseUrls('Check www.example.com/page for details');
      expect(result, hasLength(3));
      expect(result[1].text, 'www.example.com/page');
      expect(result[1].isUrl, isTrue);
    });

    test('multiple URLs in one string', () {
      final result = parseUrls(
        'Visit https://a.com and https://b.com today',
      );
      expect(result, hasLength(5));
      expect(result[0].text, 'Visit ');
      expect(result[0].isUrl, isFalse);
      expect(result[1].text, 'https://a.com');
      expect(result[1].isUrl, isTrue);
      expect(result[2].text, ' and ');
      expect(result[2].isUrl, isFalse);
      expect(result[3].text, 'https://b.com');
      expect(result[3].isUrl, isTrue);
      expect(result[4].text, ' today');
      expect(result[4].isUrl, isFalse);
    });

    test('trailing period stripped from URL', () {
      final result = parseUrls('Go to https://example.com.');
      expect(result, hasLength(3));
      expect(result[0].text, 'Go to ');
      expect(result[0].isUrl, isFalse);
      expect(result[1].text, 'https://example.com');
      expect(result[1].isUrl, isTrue);
      expect(result[2].text, '.');
      expect(result[2].isUrl, isFalse);
    });

    test('trailing comma stripped from URL', () {
      final result = parseUrls('See https://example.com, thanks');
      expect(result, hasLength(3));
      expect(result[0].text, 'See ');
      expect(result[1].text, 'https://example.com');
      expect(result[1].isUrl, isTrue);
      expect(result[2].text, ', thanks');
    });

    test('trailing semicolon stripped from URL', () {
      final result = parseUrls('https://example.com;');
      expect(result, hasLength(2));
      expect(result[0].text, 'https://example.com');
      expect(result[0].isUrl, isTrue);
      expect(result[1].text, ';');
    });

    test('trailing bracket stripped from URL', () {
      final result = parseUrls('[https://example.com]');
      expect(result, hasLength(3));
      expect(result[0].text, '[');
      expect(result[1].text, 'https://example.com');
      expect(result[1].isUrl, isTrue);
      expect(result[2].text, ']');
    });

    test('matched parens preserved (Wikipedia-style)', () {
      final result = parseUrls(
        'https://en.wikipedia.org/wiki/Dart_(programming_language)',
      );
      expect(result, hasLength(1));
      expect(
        result[0].text,
        'https://en.wikipedia.org/wiki/Dart_(programming_language)',
      );
      expect(result[0].isUrl, isTrue);
    });

    test('unmatched trailing paren stripped', () {
      final result = parseUrls('(https://example.com)');
      expect(result, hasLength(3));
      expect(result[0].text, '(');
      expect(result[1].text, 'https://example.com');
      expect(result[1].isUrl, isTrue);
      expect(result[2].text, ')');
    });

    test('email addresses not matched', () {
      final result = parseUrls('Contact user@example.com for info');
      expect(result, hasLength(1));
      expect(result[0].text, 'Contact user@example.com for info');
      expect(result[0].isUrl, isFalse);
    });

    test('newlines between URLs', () {
      final result = parseUrls('https://a.com\nhttps://b.com');
      expect(result, hasLength(3));
      expect(result[0].text, 'https://a.com');
      expect(result[0].isUrl, isTrue);
      expect(result[1].text, '\n');
      expect(result[1].isUrl, isFalse);
      expect(result[2].text, 'https://b.com');
      expect(result[2].isUrl, isTrue);
    });

    test('URL-encoded characters preserved', () {
      final result = parseUrls('https://example.com/path%20with%20spaces');
      expect(result, hasLength(1));
      expect(result[0].text, 'https://example.com/path%20with%20spaces');
      expect(result[0].isUrl, isTrue);
    });

    test('case-insensitive scheme', () {
      final result = parseUrls('HTTPS://EXAMPLE.COM');
      expect(result, hasLength(1));
      expect(result[0].text, 'HTTPS://EXAMPLE.COM');
      expect(result[0].isUrl, isTrue);
    });

    test('YouTube URL detected', () {
      final result = parseUrls(
        'Watch this https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(result, hasLength(2));
      expect(result[1].text, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(result[1].isUrl, isTrue);
    });

    test('bare domain without www or scheme not matched', () {
      final result = parseUrls('Visit example.com today');
      expect(result, hasLength(1));
      expect(result[0].isUrl, isFalse);
    });
  });
}
