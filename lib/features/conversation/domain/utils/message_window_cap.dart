/// 159 (rebuild-storms-3): the in-memory message-window cap shared by the 1:1
/// and group conversation screens.
///
/// A long-lived chat screen otherwise grows its in-RAM `_messages` list forever
/// as the live relay-drain append path keeps adding rows. This caps that
/// forward growth to the newest [kMaxInMemoryMessages], evicting the OLDEST
/// (front) rows — never the live edge. It is applied ONLY on the live-append
/// path (`_upsertMessageById` / `_upsertMessage`); the manual back-scroll
/// older-page path is intentionally exempt (a newest-first trim there would
/// immediately evict the just-loaded oldest page and loop).
library;

/// The maximum number of messages held in memory on a chat screen before the
/// live-append path starts evicting the oldest. ~300 is well above any single
/// repository page, so eviction only happens on a genuinely long live session.
const int kMaxInMemoryMessages = 300;

/// Returns [messages] trimmed to its newest [cap] entries — dropping the OLDEST
/// from the FRONT — or the SAME list instance when already within [cap].
///
/// Assumes [messages] is ordered oldest→newest (ascending), so the live edge
/// (the newest message, at the end) is always retained. Because it keeps the
/// tail, applying it to a back-scroll PREPEND (which adds the oldest page to the
/// front) would evict exactly what was just loaded — hence callers apply it only
/// on the live-append path.
List<T> trimToNewestInMemoryCap<T>(
  List<T> messages, {
  int cap = kMaxInMemoryMessages,
}) {
  if (messages.length <= cap) return messages;
  return messages.sublist(messages.length - cap);
}
