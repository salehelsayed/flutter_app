import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const String kMediaDownloadStatusPending = 'pending';
const String kMediaDownloadStatusDownloading = 'downloading';
const String kMediaDownloadStatusDone = 'done';
const String kMediaDownloadStatusFailed = 'failed';

/// A direct transport retry burst ended; another trigger or tap may retry.
const String kMediaDownloadStatusRetryWaiting = 'retry_waiting';

/// The relay explicitly answered that this item is absent or unauthorized.
const String kMediaDownloadStatusUnavailable = 'unavailable';
const String kMediaDownloadStatusIntegrityFailed = 'integrity_failed';
const String kMediaDownloadStatusUploadPending = 'upload_pending';
const String kMediaDownloadStatusUploadFailed = 'upload_failed';
const String kMediaDownloadStatusUploadCancelled = 'upload_cancelled';

/// Nontransport retry budget exhausted, or an older ambiguous terminal row.
/// Explicit relay absence now uses [kMediaDownloadStatusUnavailable]. Distinct
/// from the Go bridge event `'media:download_failed'` (a separate namespace).
const String kMediaDownloadStatusDownloadFailed = 'download_failed';

/// 229: local-only "user removed the downloaded copy, message kept" state.
///
/// Reached exclusively through the owner-aware eviction claim (Clear local
/// copy); never parsed from or written to attachment wire JSON. Auto-download
/// and mounted recovery ignore it; only an explicit user retry may transition
/// it back to downloading. `evicted` with a non-null `local_path` is a
/// deliberate cleanup-pending state (the claim survived a failed file delete
/// or a failed final path-clear), not successful byte reclamation.
const String kMediaDownloadStatusEvicted = 'evicted';

/// Verification result for a canonical, app-owned plaintext media copy.
///
/// [MediaAttachment.contentHash] authenticates the encrypted relay blob, not
/// this plaintext file. Callers that reopen or forward a downloaded file must
/// therefore validate the durable decrypt result through its canonical path,
/// exact plaintext size, and MIME signature instead of comparing two hashes
/// from different byte domains.
class CanonicalGroupMediaPlaintextValidationResult {
  const CanonicalGroupMediaPlaintextValidationResult.valid(
    String this.resolvedPath,
  ) : reason = null;

  const CanonicalGroupMediaPlaintextValidationResult.invalid(String this.reason)
    : resolvedPath = null;

  final String? resolvedPath;
  final String? reason;

  bool get isValid => resolvedPath != null;
}

class GroupMediaIntegrityPolicy {
  static final RegExp _sha256HexPattern = RegExp(r'^[a-f0-9]{64}$');

  static String? normalizeSha256Hex(String? digest) {
    final normalized = digest?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (!_sha256HexPattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static GroupMediaValidationResult validateRequiredContentHash(
    String? digest,
  ) {
    final raw = digest?.trim();
    if (raw == null || raw.isEmpty) {
      return const GroupMediaValidationResult.invalid('missing_content_hash');
    }
    if (normalizeSha256Hex(raw) == null) {
      return const GroupMediaValidationResult.invalid('malformed_content_hash');
    }
    return const GroupMediaValidationResult.valid();
  }

  static GroupMediaValidationResult validateOptionalThumbnailHash(
    String? digest,
  ) {
    final raw = digest?.trim();
    if (raw == null || raw.isEmpty) {
      return const GroupMediaValidationResult.valid();
    }
    if (normalizeSha256Hex(raw) == null) {
      return const GroupMediaValidationResult.invalid(
        'malformed_thumbnail_hash',
      );
    }
    return const GroupMediaValidationResult.valid();
  }

  static bool hasValidContentHash(MediaAttachment attachment) {
    return validateRequiredContentHash(attachment.contentHash).isValid;
  }

  static bool hasRequiredVerificationMetadata(MediaAttachment attachment) {
    return hasValidContentHash(attachment) && attachment.hasEncryptionMetadata;
  }

  static bool canDisplayVerifiedGroupMedia(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusDone &&
        attachment.localPath != null &&
        hasRequiredVerificationMetadata(attachment);
  }

  static bool isQuarantinedGroupMedia(MediaAttachment attachment) {
    return attachment.downloadStatus == kMediaDownloadStatusIntegrityFailed;
  }

  /// Whether a failed download should still be auto/UI-retried.
  ///
  /// Ordinary direct transport bursts wait for another trigger in
  /// `retry_waiting`. Other `failed` rows retain the original bounded counter.
  /// `download_failed`, explicit absence and integrity failures do not receive
  /// automatic retries.
  static bool isRetryableDownloadFailure(MediaAttachment attachment) {
    if (attachment.downloadStatus == kMediaDownloadStatusRetryWaiting) {
      return attachment.ownerLane == MediaOwnerLane.direct;
    }
    if (attachment.downloadStatus != kMediaDownloadStatusFailed) {
      return false;
    }
    return (attachment.downloadRetryCount ?? 0) < kMaxDownloadRetries;
  }

  static bool isUnavailableMedia(
    MediaAttachment attachment, {
    bool requireVerifiedContentHash = false,
  }) {
    switch (attachment.downloadStatus) {
      case kMediaDownloadStatusFailed:
        // Only owned direct/group receivers have the recovery wiring here.
        // Unowned adapters retain their existing failure state until a durable
        // recovery owner is provided for that feature.
        return attachment.ownerLane == null;
      case kMediaDownloadStatusIntegrityFailed:
      case kMediaDownloadStatusDownloadFailed:
      case kMediaDownloadStatusUnavailable:
      case kMediaDownloadStatusUploadFailed:
      case kMediaDownloadStatusUploadCancelled:
        return true;
    }

    if (requireVerifiedContentHash &&
        attachment.downloadStatus == kMediaDownloadStatusDone) {
      return !hasRequiredVerificationMetadata(attachment);
    }

    return false;
  }

  /// Revalidates the canonical local plaintext produced by an authenticated
  /// group-media download.
  ///
  /// The relay [MediaAttachment.contentHash] is required as proof that the
  /// persisted descriptor came through the encrypted-blob integrity contract,
  /// but is deliberately NOT applied to [attachment.localPath]: the download
  /// path verifies the ciphertext before decrypting it and stores plaintext at
  /// the canonical app-owned path. Comparing that plaintext to the relay hash
  /// rejects every valid encrypted download. Path, size, and signature cannot
  /// detect an equal-size same-signature local substitution; closing that gap
  /// requires a future dedicated plaintext digest captured at authenticated
  /// decrypt commit. The relay ciphertext digest must never be repurposed.
  static Future<CanonicalGroupMediaPlaintextValidationResult>
  validateCanonicalLocalPlaintext({
    required MediaAttachment attachment,
    required String ownerScopeId,
    required MediaFileManager mediaFileManager,
  }) async {
    if (!DirectPrivateMediaPathGuard.isSafeSegment(ownerScopeId)) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'unsafe_owner_scope_id',
      );
    }
    if (!DirectPrivateMediaPathGuard.isSafeSegment(attachment.id)) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'unsafe_attachment_id',
      );
    }
    if (attachment.downloadStatus != kMediaDownloadStatusDone) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'not_downloaded',
      );
    }
    if (attachment.size <= 0) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'invalid_plaintext_size',
      );
    }
    if (attachment.mediaType != 'image' && attachment.mediaType != 'video') {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'not_visual_media',
      );
    }
    if (!hasRequiredVerificationMetadata(attachment)) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'missing_relay_integrity_metadata',
      );
    }

    final descriptor = GroupMediaMimePolicy.validateDescriptor(
      mime: attachment.mime,
      mediaType: attachment.mediaType,
    );
    if (!descriptor.isValid) {
      return CanonicalGroupMediaPlaintextValidationResult.invalid(
        descriptor.reason ?? 'invalid_media_descriptor',
      );
    }

    final expectedRelative = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: ownerScopeId,
      blobId: attachment.id,
      mime: attachment.mime,
    );
    final String trustedMediaRoot;
    try {
      trustedMediaRoot = p.normalize(
        await mediaFileManager.trustedMediaRootPath(),
      );
    } catch (_) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'untrusted_media_root',
      );
    }
    if (!p.isAbsolute(trustedMediaRoot)) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'untrusted_media_root',
      );
    }
    final expectedAbsolute = p.normalize(
      p.join(
        trustedMediaRoot,
        ownerScopeId,
        '${attachment.id}${MediaFilePathConvention.extensionFromMime(attachment.mime)}',
      ),
    );
    if (!p.isWithin(trustedMediaRoot, expectedAbsolute)) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'unsafe_canonical_target',
      );
    }
    final storedPath = attachment.localPath;
    if (storedPath == null || storedPath.isEmpty) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'missing_local_path',
      );
    }
    final portableStored = storedPath.replaceAll('\\', '/');
    final storedSegments = portableStored.split('/');
    if (storedSegments.contains('..')) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'noncanonical_local_path',
      );
    }
    final normalizedStored = p.normalize(portableStored);
    final normalizedExpectedRelative = p.normalize(expectedRelative);
    var storedPathIsCanonical = false;
    if (!p.isAbsolute(normalizedStored)) {
      storedPathIsCanonical = normalizedStored == normalizedExpectedRelative;
    } else if (normalizedStored == expectedAbsolute) {
      storedPathIsCanonical = true;
    } else {
      // iOS container UUIDs change across reinstalls/restores. Accept only an
      // exact old `Documents/media/<owner>/<blob.ext>` suffix, then compare
      // MediaFileManager's compatibility reroot against the independently
      // constructed target under the current trusted media root.
      final legacySuffix = '/Documents/$expectedRelative';
      if (portableStored.endsWith(legacySuffix)) {
        try {
          final rerooted = p.normalize(
            await mediaFileManager.resolveStoredPath(storedPath),
          );
          storedPathIsCanonical = rerooted == expectedAbsolute;
        } catch (_) {
          storedPathIsCanonical = false;
        }
      }
    }
    if (!storedPathIsCanonical) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'noncanonical_local_path',
      );
    }

    if (!await DirectPrivateMediaPathGuard.authorizeTarget(
      targetPath: expectedAbsolute,
      authorityRoot: trustedMediaRoot,
      requireExistingFile: true,
    )) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'unsafe_or_missing_local_file',
      );
    }

    try {
      if (await File(expectedAbsolute).length() != attachment.size) {
        return const CanonicalGroupMediaPlaintextValidationResult.invalid(
          'plaintext_size_mismatch',
        );
      }
    } catch (_) {
      return const CanonicalGroupMediaPlaintextValidationResult.invalid(
        'unreadable_local_file',
      );
    }

    final mimeValidation = await GroupMediaMimePolicy.validateFile(
      path: expectedAbsolute,
      mime: attachment.mime,
      mediaType: attachment.mediaType,
    );
    if (!mimeValidation.isValid) {
      return CanonicalGroupMediaPlaintextValidationResult.invalid(
        mimeValidation.reason ?? 'invalid_plaintext_file',
      );
    }

    return CanonicalGroupMediaPlaintextValidationResult.valid(expectedAbsolute);
  }

  static Future<String> computeFileSha256Hex(String path) async {
    final file = File(path);
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<GroupMediaValidationResult> validateFileContentHash({
    required String path,
    required String? expectedHash,
  }) async {
    final expected = normalizeSha256Hex(expectedHash);
    if (expected == null) {
      return validateRequiredContentHash(expectedHash);
    }

    final file = File(path);
    if (!await file.exists()) {
      return const GroupMediaValidationResult.invalid('missing_file');
    }

    final actual = await computeFileSha256Hex(path);
    if (actual != expected) {
      return const GroupMediaValidationResult.invalid('content_hash_mismatch');
    }
    return const GroupMediaValidationResult.valid();
  }
}
