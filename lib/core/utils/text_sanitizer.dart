/// Maximum allowed message length (characters).
const int maxMessageLength = 10000;

/// Maximum allowed username length.
const int maxUsernameLength = 30;

/// Regex matching dangerous bidi control characters and invisible formatting.
///
/// Strips: U+200B (zero-width space), U+200C (ZWNJ),
/// U+202A-U+202E (legacy bidi embedding/override), and U+FEFF (BOM/ZWNBS).
///
/// Preserves safe/helpful markers:
/// - U+200D (ZWJ) for emoji sequences
/// - U+200E (LRM) and U+200F (RLM) for mixed-direction text
/// - U+061C (ALM) for Arabic numeric/context handling
/// - U+2066 (LRI), U+2067 (RLI), U+2068 (FSI), U+2069 (PDI) isolates
final _bidiPattern = RegExp(
  '[\u200B\u200C'
  '\u202A-\u202E'
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
  return RegExp(
    r'^[a-zA-Z0-9_\-\.\u00C0-\u024F\u0600-\u06FF\u0750-\u077F]+$',
  ).hasMatch(username);
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
