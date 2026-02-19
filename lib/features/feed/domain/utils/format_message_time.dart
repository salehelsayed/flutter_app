/// Formats an ISO-8601 timestamp into 12-hour AM/PM display format.
///
/// Returns a string like "3:30 PM" or empty string on invalid input.
String formatMessageTime(String isoTimestamp) {
  try {
    final date = DateTime.parse(isoTimestamp).toLocal();
    final hour =
        date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
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
