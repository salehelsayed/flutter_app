/// The same lifetime applies to the author's thought and every received copy.
abstract final class ThoughtLifetime {
  static const duration = Duration(hours: 24);

  static DateTime expiresAt(DateTime createdAt) =>
      createdAt.toUtc().add(duration);

  static bool isExpired(DateTime createdAt, DateTime now) =>
      !now.toUtc().isBefore(expiresAt(createdAt));
}
