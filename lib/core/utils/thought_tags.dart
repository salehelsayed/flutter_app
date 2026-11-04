/// A #tag in a Thought's text. [start] and [end] cover the '#' and its word.
class ThoughtTag {
  const ThoughtTag({required this.start, required this.end, required this.key});

  final int start;
  final int end;

  /// The word after '#', lowercased: tags with the same key are one tag.
  final String key;
}

/// A '#' that starts no word, then letters, marks, digits or underscores in
/// any script. Punctuation, a hyphen or a space ends the tag.
final _tagPattern = RegExp(
  r'(?<![\p{L}\p{M}\p{N}_])#([\p{L}\p{M}\p{N}_]+)',
  unicode: true,
);

/// The tags in [text], in order.
List<ThoughtTag> parseThoughtTags(String text) => [
  for (final match in _tagPattern.allMatches(text))
    ThoughtTag(
      start: match.start,
      end: match.end,
      key: match.group(1)!.toLowerCase(),
    ),
];

/// Whether [text] carries the tag whose key is [key].
bool hasThoughtTag(String text, String key) =>
    parseThoughtTags(text).any((tag) => tag.key == key);
