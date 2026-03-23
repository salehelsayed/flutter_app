import 'dart:ui' show TextDirection;

/// Detects text direction using a first-strong-character heuristic.
///
/// Neutral characters such as spaces, punctuation, digits, and emoji are
/// skipped until a strong RTL or LTR character is found. Defaults to LTR when
/// no strong character exists.
TextDirection detectTextDirection(String text) {
  for (final codePoint in text.runes) {
    if (_isRtlChar(codePoint)) {
      return TextDirection.rtl;
    }

    if (_isLtrChar(codePoint)) {
      return TextDirection.ltr;
    }
  }

  return TextDirection.ltr;
}

bool _isRtlChar(int codePoint) {
  if (codePoint >= 0x0590 && codePoint <= 0x05FF) return true;
  if (codePoint >= 0x0600 && codePoint <= 0x06FF) return true;
  if (codePoint >= 0x0700 && codePoint <= 0x074F) return true;
  if (codePoint >= 0x0750 && codePoint <= 0x077F) return true;
  if (codePoint >= 0x0780 && codePoint <= 0x07BF) return true;
  if (codePoint >= 0x07C0 && codePoint <= 0x07FF) return true;
  if (codePoint >= 0x08A0 && codePoint <= 0x08FF) return true;
  if (codePoint >= 0xFB1D && codePoint <= 0xFB4F) return true;
  if (codePoint >= 0xFB50 && codePoint <= 0xFDFF) return true;
  if (codePoint >= 0xFE70 && codePoint <= 0xFEFF) return true;
  return false;
}

bool _isLtrChar(int codePoint) {
  if (codePoint >= 0x0041 && codePoint <= 0x005A) return true;
  if (codePoint >= 0x0061 && codePoint <= 0x007A) return true;
  if (codePoint >= 0x00C0 && codePoint <= 0x024F) return true;
  if (codePoint >= 0x0370 && codePoint <= 0x03FF) return true;
  if (codePoint >= 0x0400 && codePoint <= 0x04FF) return true;
  if (codePoint >= 0x4E00 && codePoint <= 0x9FFF) return true;
  return false;
}
