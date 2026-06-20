import 'package:flutter/foundation.dart';

/// Process-wide registry of media blob uploads currently owned by a live
/// (foreground) send.
///
/// 127-Bug-B: the background `PendingMessageRetrier` / `retryIncompleteUploads`
/// consults this before re-uploading an `upload_pending` blob. While a
/// foreground send is actively uploading a blob — and through the subsequent
/// envelope send — the retrier must NOT re-encrypt + re-upload the same blob:
/// AES-GCM mints a fresh nonce per encryption, so a concurrent re-upload would
/// store ciphertext on the relay whose SHA-256 no longer matches the
/// `contentHash` the foreground already advertised in the message envelope,
/// and the recipient's pre-decrypt content-hash gate would reject it
/// (`integrity_failed` / "Couldn't verify this media").
///
/// Re-uploading IS correct when the retrier runs alone (a send that crashed
/// mid-upload): it re-encrypts and re-advertises the new hash. This tracker
/// only suppresses the racing-concurrent case, which is the sole inconsistent
/// one.
class MediaUploadInFlightTracker {
  final Set<String> _inFlight = <String>{};

  /// Marks [blobId] as being uploaded by a live foreground send.
  void begin(String blobId) {
    if (blobId.isEmpty) return;
    _inFlight.add(blobId);
  }

  /// Clears the in-flight mark for [blobId] (no-op if absent).
  void end(String blobId) {
    _inFlight.remove(blobId);
  }

  /// Whether [blobId] is currently being uploaded by a live foreground send.
  bool isInFlight(String blobId) => _inFlight.contains(blobId);

  @visibleForTesting
  int get inFlightCount => _inFlight.length;

  @visibleForTesting
  void clearAll() => _inFlight.clear();
}

/// The single process-wide instance, shared between the foreground send path
/// (`conversation_wired.dart`) and the background retrier wiring (`main.dart`).
final MediaUploadInFlightTracker mediaUploadInFlightTracker =
    MediaUploadInFlightTracker();
