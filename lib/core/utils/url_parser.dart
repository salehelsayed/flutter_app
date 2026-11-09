/// A segment of text that may or may not be a URL.
class TextSegment {
  final String text;

  /// Where a tap on this segment goes: always http or https. Null for plain
  /// text.
  final Uri? uri;
  const TextSegment(this.text, {this.uri});

  bool get isUrl => uri != null;
}

/// Matches http(s):// URLs and www. URLs (case insensitive). A www. right
/// after a scheme, an @ or a dot belongs to something else, such as
/// `myapp://www.example.com` or `me@www.example.com`, and stays plain.
final _urlPattern = RegExp(
  r'(https?://[^\s<>"]+|(?<![\w@./:-])www\.[^\s<>"]+\.[a-zA-Z]{2,}[^\s<>"]*)',
  caseSensitive: false,
);

/// Characters to trim from the end of a matched URL, Arabic ones included.
const _trailingPunctuation = <String>{
  '.',
  ',',
  ';',
  ':',
  '!',
  '?',
  '،',
  '؛',
  '؟',
};

/// Parses [text] into a list of [TextSegment]s, identifying URLs.
///
/// URLs are detected by http(s):// scheme or www. prefix; a www. link opens
/// over https. Trailing punctuation is stripped from URL matches.
/// Matched parentheses are preserved (e.g. Wikipedia URLs).
List<TextSegment> parseUrls(String text) {
  if (text.isEmpty) return [const TextSegment('')];

  final segments = <TextSegment>[];
  void addPlain(String plain) {
    final last = segments.lastOrNull;
    if (last != null && !last.isUrl) {
      segments[segments.length - 1] = TextSegment(last.text + plain);
    } else {
      segments.add(TextSegment(plain));
    }
  }

  var lastEnd = 0;

  for (final match in _urlPattern.allMatches(text)) {
    // Add plain text before this match
    if (match.start > lastEnd) {
      addPlain(text.substring(lastEnd, match.start));
    }

    var url = match.group(0)!;
    var strippedCount = 0;

    // Trim trailing punctuation and unmatched brackets
    while (url.isNotEmpty) {
      final lastChar = url[url.length - 1];
      if (_trailingPunctuation.contains(lastChar)) {
        strippedCount++;
        url = url.substring(0, url.length - 1);
      } else if (lastChar == ')') {
        // Only trim if unmatched
        final openCount = url.codeUnits.where((c) => c == 0x28).length;
        final closeCount = url.codeUnits.where((c) => c == 0x29).length;
        if (closeCount > openCount) {
          strippedCount++;
          url = url.substring(0, url.length - 1);
        } else {
          break;
        }
      } else if (lastChar == ']') {
        strippedCount++;
        url = url.substring(0, url.length - 1);
      } else {
        break;
      }
    }

    final uri = _linkUri(url);
    if (uri != null) {
      segments.add(TextSegment(url, uri: uri));
    } else if (url.isNotEmpty) {
      addPlain(url);
    }

    // Roll back lastEnd so stripped chars become part of the next plain segment
    lastEnd = match.end - strippedCount;
  }

  // Add any remaining plain text
  if (lastEnd < text.length) {
    addPlain(text.substring(lastEnd));
  } else if (segments.isEmpty) {
    segments.add(TextSegment(text));
  }

  return segments;
}

Uri? _linkUri(String url) {
  final uri = Uri.tryParse(
    url.toLowerCase().startsWith('www.') ? 'https://$url' : url,
  );
  if (uri == null || uri.host.isEmpty) return null;
  return uri.isScheme('http') || uri.isScheme('https') ? uri : null;
}
