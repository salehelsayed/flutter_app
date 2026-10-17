import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_control.dart';

/// Task 12b engineering bounds for the reply-once repair. They are tuned by
/// the focused tests, not inherited from an older constant.
abstract final class ContactRepairLimits {
  static const Duration replyPacing = Duration(seconds: 5);
  static const int maxPendingPerPeer = 4;
  static const int maxPendingGlobal = 256;
  static const int maxTransmitting = 2;
  static const int maxGuardsPerPeer = 18016;
  static const int maxGuardsGlobal = 100000;
  static const int maxAttempts = 3;
  static const Duration freshnessPast = Duration(hours: 24);
  static const Duration freshnessFuture = Duration(minutes: 5);
  static const Duration guardRetention = Duration(hours: 25);
  static const Duration clockAnomalyTolerance = Duration(minutes: 5);
  static const int garbageBatch = 500;

  static Duration retryBackoff(int attemptsUsed) => attemptsUsed <= 1
      ? const Duration(seconds: 5)
      : const Duration(seconds: 30);
}

enum ContactRepairFreshness { fresh, stale, clockAnomaly }

/// Freshness of a signed request time against the persisted effective clock.
///
/// The past bound uses the effective clock (never behind the high-water), so a
/// wall clock moved backward cannot make an old request fresh again. The
/// future bound uses the wall clock. A wall clock far behind the high-water is
/// an anomaly that defers automatic work.
ContactRepairFreshness signedRequestFreshness({
  required int signedAtMs,
  required int wallNowMs,
  required int highWaterMs,
}) {
  if (wallNowMs <
      highWaterMs - ContactRepairLimits.clockAnomalyTolerance.inMilliseconds) {
    return ContactRepairFreshness.clockAnomaly;
  }
  final effectiveNowMs = wallNowMs > highWaterMs ? wallNowMs : highWaterMs;
  if (signedAtMs <
      effectiveNowMs - ContactRepairLimits.freshnessPast.inMilliseconds) {
    return ContactRepairFreshness.stale;
  }
  if (signedAtMs >
      wallNowMs + ContactRepairLimits.freshnessFuture.inMilliseconds) {
    return ContactRepairFreshness.stale;
  }
  return ContactRepairFreshness.fresh;
}

/// Parses a signed ISO-8601 time to a UTC instant in milliseconds. Null when
/// absent or malformed: a malformed signed time is never eligible.
int? parseSignedInstantMs(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw)?.toUtc().millisecondsSinceEpoch;
}

/// Fingerprint of a standard-base64 Ed25519 public key. Throws
/// [FormatException] unless the key decodes to exactly 32 bytes.
String ed25519AuthorityFingerprint(String base64PublicKey) {
  final bytes = base64Decode(base64PublicKey.trim());
  if (bytes.length != 32) {
    throw const FormatException('ed25519 public key must be 32 bytes');
  }
  return 'ed25519:${sha256.convert(bytes)}';
}

/// Digest of the exact canonical signed payload of one request.
String contactRequestSignedDigest(String canonicalSignedData) =>
    sha256.convert(utf8.encode(canonicalSignedData)).toString();

/// Why a verified message does or does not ask for an automatic reply.
enum ExistingContactRepairDecision {
  /// A fresh-candidate signed `new_request` from a contact that existed and
  /// was not blocked before routing.
  claimReply,
  notMarked,
  isReply,
  notExistingContact,
  blocked,
}

/// Pure decision over verified inputs captured BEFORE intro routing. Only the
/// signed marker counts; unsigned outer intent never does.
ExistingContactRepairDecision decideExistingContactRepair({
  required ContactRequestControl? control,
  required bool existedBeforeRouting,
  required bool blocked,
}) {
  if (control == null) return ExistingContactRepairDecision.notMarked;
  if (!control.isNewRequest) return ExistingContactRepairDecision.isReply;
  if (!existedBeforeRouting) {
    return ExistingContactRepairDecision.notExistingContact;
  }
  if (blocked) return ExistingContactRepairDecision.blocked;
  return ExistingContactRepairDecision.claimReply;
}
