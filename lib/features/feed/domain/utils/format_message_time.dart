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
