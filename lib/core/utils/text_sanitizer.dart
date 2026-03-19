/// Maximum allowed message length (characters).
const int maxMessageLength = 10000;

/// Maximum allowed username length.
const int maxUsernameLength = 30;

/// Regex matching bidi control characters and invisible formatting characters.
///
/// Strips: U+200B (zero-width space), U+200C (ZWNJ),
/// U+200E-200F (LRM/RLM), U+202A-202E (bidi embedding/override),
/// U+2066-2069 (bidi isolate), U+061C (ALM), U+FEFF (BOM/ZWNBS).
///
/// Preserves U+200D (zero-width joiner) for emoji sequences.
final _bidiPattern = RegExp(
  '[\u200B\u200C\u200E\u200F'
  '\u202A-\u202E'
  '\u2066-\u2069'
  '\u061C'
  '\uFEFF]',
);

/// Strips bidi control characters and invisible formatting from [text].
String stripBidiCharacters(String text) {
  return text.replaceAll(_bidiPattern, '');
}

/// Whether [text] exceeds the maximum message length.
bool isMessageTooLong(String text) {
  return text.length > maxMessageLength;
}

/// Whether [username] contains only allowed characters:
/// Latin + Extended Latin `\u00C0-\u024F` (covers German äöüÄÖÜß,
/// French àâçéèêë, Scandinavian åæø, etc.), digits `0-9`, `_-.`,
/// Arabic `\u0600-\u06FF`, Arabic Supplement `\u0750-\u077F`.
bool isValidUsername(String username) {
  if (username.isEmpty) return false;
  return RegExp(r'^[a-zA-Z0-9_\-\.\u00C0-\u024F\u0600-\u06FF\u0750-\u077F]+$')
      .hasMatch(username);
}

/// Sanitizes message text by stripping bidi characters.
String sanitizeMessageText(String text) {
  return stripBidiCharacters(text);
}

/// Sanitizes a username by stripping bidi characters and truncating to [maxUsernameLength].
String sanitizeUsername(String username) {
  final stripped = stripBidiCharacters(username);
  if (stripped.length > maxUsernameLength) {
    return stripped.substring(0, maxUsernameLength);
  }
  return stripped;
}
