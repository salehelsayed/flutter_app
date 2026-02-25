/// A segment of text that may or may not be a URL.
class TextSegment {
  final String text;
  final bool isUrl;
  const TextSegment(this.text, {this.isUrl = false});
}

/// Matches http(s):// URLs and www. URLs (case insensitive).
final _urlPattern = RegExp(
  r'(https?://[^\s<>"]+|www\.[^\s<>"]+\.[a-zA-Z]{2,}[^\s<>"]*)',
  caseSensitive: false,
);

/// Characters to trim from the end of a matched URL.
const _trailingPunctuation = <String>{'.', ',', ';', ':', '!', '?'};

/// Parses [text] into a list of [TextSegment]s, identifying URLs.
///
/// URLs are detected by http(s):// scheme or www. prefix.
/// Trailing punctuation is stripped from URL matches.
/// Matched parentheses are preserved (e.g. Wikipedia URLs).
List<TextSegment> parseUrls(String text) {
  if (text.isEmpty) return [const TextSegment('')];

  final segments = <TextSegment>[];
  var lastEnd = 0;

  for (final match in _urlPattern.allMatches(text)) {
    // Add plain text before this match
    if (match.start > lastEnd) {
      segments.add(TextSegment(text.substring(lastEnd, match.start)));
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

    if (url.isNotEmpty) {
      segments.add(TextSegment(url, isUrl: true));
    }

    // Roll back lastEnd so stripped chars become part of the next plain segment
    lastEnd = match.end - strippedCount;
  }

  // Add any remaining plain text
  if (lastEnd < text.length) {
    segments.add(TextSegment(text.substring(lastEnd)));
  } else if (segments.isEmpty) {
    segments.add(TextSegment(text));
  }

  return segments;
}
