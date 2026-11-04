/// Whether [text] contains [query], ignoring upper and lower case. A blank
/// query matches nothing.
bool textSearchMatches(String text, String query) {
  final needle = query.trim().toLowerCase();
  return needle.isNotEmpty && text.toLowerCase().contains(needle);
}

/// Where [query] occurs in [text], ignoring upper and lower case, for
/// marking. Matches do not overlap; a blank query matches nothing.
List<({int start, int end})> textSearchRanges(String text, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final haystack = text.toLowerCase();
  // Lower-casing can change a string's length (e.g. 'İ'); positions would
  // then point at the wrong letters, so such text is left unmarked.
  if (haystack.length != text.length) return const [];
  final ranges = <({int start, int end})>[];
  var at = haystack.indexOf(needle);
  while (at >= 0) {
    ranges.add((start: at, end: at + needle.length));
    at = haystack.indexOf(needle, at + needle.length);
  }
  return ranges;
}

/// The ids of the messages whose words contain [query], newest first.
/// [oldestFirst] is the chat in timeline order.
List<String> newestFirstSearchHits(
  Iterable<({String id, String text})> oldestFirst,
  String query,
) => [
  for (final message in oldestFirst.toList().reversed)
    if (textSearchMatches(message.text, query)) message.id,
];
