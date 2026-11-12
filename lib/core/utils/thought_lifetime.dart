/// The same lifetime applies to the author's thought and every received copy.
abstract final class ThoughtLifetime {
  static const duration = Duration(hours: 24);

  /// A received Thought stays on disk, hidden, this long past its expiry.
  /// A viewer clock set ahead by less than this must not delete a Thought
  /// that is still live by real time (BL-14).
  static const deleteGrace = Duration(hours: 48);

  static DateTime expiresAt(DateTime createdAt) =>
      createdAt.toUtc().add(duration);

  static bool isExpired(DateTime createdAt, DateTime now) =>
      !now.toUtc().isBefore(expiresAt(createdAt));

  /// Ended before its full lifetime because a newer Thought took its place.
  static bool isReplaced(DateTime createdAt, DateTime expiresAt) =>
      expiresAt.toUtc().isBefore(ThoughtLifetime.expiresAt(createdAt));
}
