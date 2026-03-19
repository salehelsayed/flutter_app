import 'package:intl/intl.dart' as intl;

/// Formats an ISO-8601 timestamp into locale-aware time format.
///
/// Returns a string like "3:30 PM" (en) or "15:30" (de/ar) or empty string on invalid input.
String formatMessageTime(String isoTimestamp, [String locale = 'en']) {
  try {
    final date = DateTime.parse(isoTimestamp).toLocal();
    return intl.DateFormat.jm(locale).format(date);
  } catch (_) {
    return '';
  }
}

/// Formats an ISO-8601 timestamp into a relative time string.
///
/// Returns strings like "Active now", "2m ago", "3h ago", "1d ago".
String formatRelativeTime(String isoTimestamp) {
  try {
    final date = DateTime.parse(isoTimestamp).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Active now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  } catch (_) {
    return '';
  }
}
