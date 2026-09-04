import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';

import '../domain/call_wake_handle_grant.dart';

enum CallEndpointResolutionCode {
  notAccepted,
  blocked,
  unavailable,
  stale,
  mismatched,
  unlinked,
  invalidSignature,
  ambiguous,
}

final class CallEndpointResolutionException implements Exception {
  const CallEndpointResolutionException(this.code);

  final CallEndpointResolutionCode code;

  @override
  String toString() => 'Call endpoint unavailable: ${code.name}';
}

final class TrustedCallDeviceAuthority {
  const TrustedCallDeviceAuthority({
    required this.accountPeerId,
    required this.devicePeerId,
    required this.linked,
    required this.deviceKeyEpoch,
    required this.signingPublicKey,
    required this.mlKemPublicKey,
  });

  final String accountPeerId;
  final String devicePeerId;
  final bool linked;
  final int deviceKeyEpoch;
  final String signingPublicKey;
  final String mlKemPublicKey;
}

typedef VerifyCallEndpointSignature =
    Future<bool> Function(
      SignedCallEndpointRecord endpoint,
      String trustedSigningPublicKey,
    );

final class ResolvedCallEndpoint {
  const ResolvedCallEndpoint({
    required this.accountPeerId,
    required this.devicePeerId,
    required this.signingPublicKey,
    required this.mlKemPublicKey,
    required this.deviceKeyEpoch,
    required this.preferenceEpoch,
    required this.platform,
    required this.expiresAtMs,
    required this.routingHandle,
    required this.wakeHandle,
  });

  final String accountPeerId;
  final String devicePeerId;
  final String signingPublicKey;
  final String mlKemPublicKey;
  final int deviceKeyEpoch;
  final int preferenceEpoch;
  final CallEndpointPlatform platform;
  final int expiresAtMs;
  final String routingHandle;
  final String wakeHandle;
}

/// Resolves the single endpoint authorized by both local contact state and the
/// relay's current, device-signed capability record.
///
/// A relay record is never identity authority on its own. Its canonical bytes
/// are verified with the current signing key from [trustedDevices] before the
/// endpoint can be returned.
final class CallEndpointResolver {
  CallEndpointResolver({
    required int Function() nowMs,
    required VerifyCallEndpointSignature verifyEndpointSignature,
  }) : _nowMs = nowMs,
       _verifyEndpointSignature = verifyEndpointSignature;

  static const String voiceCapability = 'voice_call_v1';
  static final RegExp _routingHandleGrammar = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _wakeHandleGrammar = RegExp(r'^[0-9a-f]{32}$');

  final int Function() _nowMs;
  final VerifyCallEndpointSignature _verifyEndpointSignature;

  Future<ResolvedCallEndpoint> resolve({
    required String contactAccountPeerId,
    required bool contactAccepted,
    required bool contactBlocked,
    required List<TrustedCallDeviceAuthority> trustedDevices,
    required List<SignedCallEndpointRecord> relayCapabilities,
    CallWakeHandleGrant? wakeHandleGrant,
  }) async {
    if (!contactAccepted) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.notAccepted,
      );
    }
    if (contactBlocked) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.blocked,
      );
    }

    final accountRoster = trustedDevices
        .where((device) => device.accountPeerId == contactAccountPeerId)
        .toList(growable: false);
    if (accountRoster.isEmpty) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
    }
    final linkedRoster = accountRoster
        .where((device) => device.linked)
        .toList(growable: false);
    if (linkedRoster.isEmpty) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.unlinked,
      );
    }
    if (relayCapabilities.isEmpty) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
    }

    final sameAccount = relayCapabilities
        .where((entry) => entry.record.accountPeerId == contactAccountPeerId)
        .toList(growable: false);
    if (sameAccount.isEmpty) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.mismatched,
      );
    }
    final nowMs = _nowMs();
    final current = sameAccount
        .where((entry) => entry.record.expiresAtMs > nowMs)
        .toList(growable: false);
    if (current.isEmpty) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.stale,
      );
    }

    var foundIntersectionCandidate = false;
    final matches =
        <({TrustedCallDeviceAuthority trusted, CallEndpointRecord record})>[];
    for (final trusted in linkedRoster) {
      if (trusted.devicePeerId.trim().isEmpty ||
          trusted.signingPublicKey.trim().isEmpty ||
          trusted.mlKemPublicKey.trim().isEmpty ||
          trusted.deviceKeyEpoch < 0) {
        continue;
      }
      for (final endpoint in current) {
        final record = endpoint.record;
        if (record.devicePeerId != trusted.devicePeerId ||
            record.deviceKeyEpoch != trusted.deviceKeyEpoch ||
            record.preferenceEpoch < 0 ||
            !record.capabilities.contains(voiceCapability) ||
            !_routingHandleGrammar.hasMatch(record.routingHandle)) {
          continue;
        }
        foundIntersectionCandidate = true;
        var signatureValid = false;
        try {
          signatureValid = await _verifyEndpointSignature(
            endpoint,
            trusted.signingPublicKey,
          );
        } catch (_) {
          signatureValid = false;
        }
        if (!signatureValid) continue;

        matches.add((trusted: trusted, record: record));
      }
    }

    if (matches.isEmpty) {
      throw CallEndpointResolutionException(
        foundIntersectionCandidate
            ? CallEndpointResolutionCode.invalidSignature
            : CallEndpointResolutionCode.mismatched,
      );
    }
    if (matches.length != 1) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.ambiguous,
      );
    }
    final match = matches.single;
    final grant = wakeHandleGrant;
    if (grant == null) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
    }
    if (!grant.isValidAt(nowMs)) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.stale,
      );
    }
    if (grant.recipientDevicePeerId != match.trusted.devicePeerId ||
        grant.deviceKeyEpoch != match.trusted.deviceKeyEpoch ||
        grant.deviceKeyEpoch <= 0 ||
        grant.generation <= 0 ||
        !_wakeHandleGrammar.hasMatch(grant.handle)) {
      throw const CallEndpointResolutionException(
        CallEndpointResolutionCode.mismatched,
      );
    }

    final authorityExpiresAtMs = match.record.expiresAtMs < grant.expiresAtMs
        ? match.record.expiresAtMs
        : grant.expiresAtMs;
    return ResolvedCallEndpoint(
      accountPeerId: match.trusted.accountPeerId,
      devicePeerId: match.trusted.devicePeerId,
      signingPublicKey: match.trusted.signingPublicKey,
      mlKemPublicKey: match.trusted.mlKemPublicKey,
      deviceKeyEpoch: match.trusted.deviceKeyEpoch,
      preferenceEpoch: match.record.preferenceEpoch,
      platform: match.record.platform,
      expiresAtMs: authorityExpiresAtMs,
      routingHandle: match.record.routingHandle,
      wakeHandle: grant.handle,
    );
  }
}
