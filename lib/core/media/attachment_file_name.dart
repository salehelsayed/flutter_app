/// Longest display name kept for a document attachment (414).
const int kMaxAttachmentFileNameLength = 120;

// Control characters and bidirectional-text controls. A right-to-left
// override (U+202E) could make a name ending in `fdp.exe` display as `exe.pdf`.
final RegExp _unsafeFileNameCharacters = RegExp(
  '[\u0000-\u001F\u007F-\u009F\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
);
final RegExp _onlyDots = RegExp(r'^\.+$');

/// Cleans a document file name for display. Used on send and on receive,
/// because the name comes from the sender and is untrusted.
///
/// Keeps the last path part only, removes control and bidi characters, and
/// caps the length while keeping a short extension. Returns null when
/// nothing usable is left. The name is never used to build a disk path.
String? sanitizeAttachmentFileName(Object? raw) {
  if (raw is! String) return null;
  var name = raw.split(RegExp(r'[/\\]')).last;
  name = name.replaceAll(_unsafeFileNameCharacters, '').trim();
  if (name.isEmpty || _onlyDots.hasMatch(name)) return null;
  if (name.length <= kMaxAttachmentFileNameLength) return name;

  final dot = name.lastIndexOf('.');
  final extension = dot > 0 && name.length - dot <= 10
      ? name.substring(dot)
      : '';
  var stem = name.substring(0, kMaxAttachmentFileNameLength - extension.length);
  // Never end on half of a surrogate pair.
  final last = stem.codeUnitAt(stem.length - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    stem = stem.substring(0, stem.length - 1);
  }
  return '$stem$extension';
}

/// The display name to carry for an attachment built from the local file at
/// [path]: its cleaned base name for a document, null for anything else.
String? documentFileNameForPath(String path, {required String mediaType}) =>
    mediaType == 'file' ? sanitizeAttachmentFileName(path) : null;
