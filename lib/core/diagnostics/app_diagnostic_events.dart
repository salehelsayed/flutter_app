/// A transport-free observation seam for storage, avoiding a dependency from
/// database transactions back to the native bridge/diagnostic uploader.
abstract final class AppDiagnosticEvents {
  static void Function(bool successful, int durationMs)? onStorageTransaction;

  static void storageTransaction(bool successful, int durationMs) {
    try {
      onStorageTransaction?.call(successful, durationMs);
    } catch (_) {
      // An observer cannot change transaction success or error propagation.
    }
  }
}
