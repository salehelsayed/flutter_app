/// Only the phase and an ephemeral in-memory token cross the observation seam.
/// A token must never be a filename, account key, or notification identifier.
enum NotificationFileLockPhase { waiting, held, released }

/// A transport-free observation seam for storage, avoiding a dependency from
/// database transactions back to the native bridge/diagnostic uploader.
abstract final class AppDiagnosticEvents {
  static void Function(bool successful, int durationMs)? onStorageTransaction;
  static void Function(Object owner, NotificationFileLockPhase phase)?
  onNotificationFileLock;

  static void notificationFileLock(
    Object owner,
    NotificationFileLockPhase phase,
  ) {
    try {
      onNotificationFileLock?.call(owner, phase);
    } catch (_) {
      // Observation never owns a file descriptor or changes lock semantics.
    }
  }

  static void storageTransaction(bool successful, int durationMs) {
    try {
      onStorageTransaction?.call(successful, durationMs);
    } catch (_) {
      // An observer cannot change transaction success or error propagation.
    }
  }
}
