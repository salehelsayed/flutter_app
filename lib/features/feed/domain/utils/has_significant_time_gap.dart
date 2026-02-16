/// Returns true if there is a significant time gap between two timestamps.
///
/// A gap is significant if:
/// - The absolute difference is 2 or more hours, OR
/// - The timestamps cross an AM/PM boundary (noon).
bool hasSignificantTimeGap(DateTime a, DateTime b) {
  if (b.difference(a).abs().inHours >= 2) return true;
  final aLocal = a.toLocal();
  final bLocal = b.toLocal();
  return (aLocal.hour < 12) != (bLocal.hour < 12);
}
