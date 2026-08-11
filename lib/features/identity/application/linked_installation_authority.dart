import 'dart:convert';

import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';

/// Secure-storage key holding the expected installation role marker.
///
/// Written FIRST during linked setup, so a crash between this write and the
/// credential write leaves a state that is recognizably "linked setup began"
/// rather than an installation that silently keeps primary behavior.
const String linkedInstallationRoleStorageKey =
    'direct_linked_device_expected_role_v1';

/// Secure-storage key holding the versioned transport credential.
const String linkedInstallationTransportCredentialStorageKey =
    'direct_linked_device_transport_credential_v1';

/// Marker value for an installation that expects to be a linked secondary.
const String linkedInstallationRoleMarkerValue = 'linked_secondary';

/// Credential envelope version.
const int linkedTransportCredentialVersion = 1;

/// Domain-separated ownership challenge signed during credential creation.
const String _transportOwnershipChallengeDomain =
    'mknoon/direct-linked-device/transport-ownership-proof/v1';

/// Lifecycle state of the single transport credential.
enum LinkedTransportCredentialState {
  /// Created, key material committed, but NOT yet usable. A resumed setup
  /// re-adopts these exact bytes rather than minting a second identity.
  preparing,

  /// Fully committed. This installation starts exactly this transport.
  active,
}

/// What the persisted authority says this installation must do at startup.
enum LinkedInstallationDisposition {
  /// No marker and no credential — ordinary primary. Startup is byte-for-byte
  /// the incumbent path.
  primary,

  /// Marker present, no credential yet. Setup MAY generate its first
  /// credential; normal startup refuses.
  awaitingCredential,

  /// Marker plus a `preparing` credential. Setup resumes with the SAME bytes;
  /// normal startup refuses.
  preparing,

  /// Marker plus an `active` credential bound to this account and device.
  /// Startup uses exactly this transport.
  active,

  /// Any other shape — credential without marker, unparseable envelope,
  /// cross-account binding, or canonical device-ID drift. Startup refuses and
  /// NEVER falls back to the account transport.
  failClosed,
}

/// One versioned, device-local transport credential.
///
/// The `transportPrivateKey` never leaves secure storage: it is not written to
/// SQLite, not emitted in flow events, not put in analytics, and not included
/// in any migration bundle or receipt.
class LinkedTransportCredential {
  const LinkedTransportCredential({
    required this.state,
    required this.accountPeerId,
    required this.accountPublicKey,
    required this.deviceId,
    required this.transportPeerId,
    required this.transportPublicKey,
    required this.transportPrivateKey,
    required this.createdAt,
    required this.activatedAt,
  });

  final LinkedTransportCredentialState state;

  /// The LOGICAL account this installation belongs to. Distinct from
  /// [transportPeerId]: the account gate sees this, the bridge sees the
  /// transport.
  final String accountPeerId;
  final String accountPublicKey;

  /// The canonical runtime installation ID. Bound exactly; never re-minted.
  final String deviceId;

  final String transportPeerId;
  final String transportPublicKey;
  final String transportPrivateKey;
  final String createdAt;
  final String? activatedAt;

  LinkedTransportCredential copyWithActivated(String activatedAt) {
    return LinkedTransportCredential(
      state: LinkedTransportCredentialState.active,
      accountPeerId: accountPeerId,
      accountPublicKey: accountPublicKey,
      deviceId: deviceId,
      transportPeerId: transportPeerId,
      transportPublicKey: transportPublicKey,
      transportPrivateKey: transportPrivateKey,
      createdAt: createdAt,
      activatedAt: activatedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'v': linkedTransportCredentialVersion,
    'state': state.name,
    'accountPeerId': accountPeerId,
    'accountPublicKey': accountPublicKey,
    'deviceId': deviceId,
    'transportPeerId': transportPeerId,
    'transportPublicKey': transportPublicKey,
    'transportPrivateKey': transportPrivateKey,
    'createdAt': createdAt,
    'activatedAt': activatedAt,
  };

  /// Parses a stored envelope, returning null for ANY malformed shape.
  ///
  /// Null is fail-closed, never "treat as absent and regenerate": a corrupt
  /// credential on an installation that already announced a transport peer
  /// must refuse, because regenerating would strand every binding a contact
  /// already verified.
  static LinkedTransportCredential? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['v'] != linkedTransportCredentialVersion) {
        return null;
      }
      final state = switch (decoded['state']) {
        'preparing' => LinkedTransportCredentialState.preparing,
        'active' => LinkedTransportCredentialState.active,
        _ => null,
      };
      if (state == null) {
        return null;
      }
      final accountPeerId = _requiredString(decoded['accountPeerId']);
      final accountPublicKey = _requiredString(decoded['accountPublicKey']);
      final deviceId = _requiredString(decoded['deviceId']);
      final transportPeerId = _requiredString(decoded['transportPeerId']);
      final transportPublicKey = _requiredString(decoded['transportPublicKey']);
      final transportPrivateKey = _requiredString(
        decoded['transportPrivateKey'],
      );
      final createdAt = _requiredString(decoded['createdAt']);
      if (accountPeerId == null ||
          accountPublicKey == null ||
          deviceId == null ||
          transportPeerId == null ||
          transportPublicKey == null ||
          transportPrivateKey == null ||
          createdAt == null) {
        return null;
      }
      final activatedAt = decoded['activatedAt'];
      if (state == LinkedTransportCredentialState.active &&
          _requiredString(activatedAt) == null) {
        return null;
      }
      return LinkedTransportCredential(
        state: state,
        accountPeerId: accountPeerId,
        accountPublicKey: accountPublicKey,
        deviceId: deviceId,
        transportPeerId: transportPeerId,
        transportPublicKey: transportPublicKey,
        transportPrivateKey: transportPrivateKey,
        createdAt: createdAt,
        activatedAt: activatedAt is String ? activatedAt : null,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _requiredString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Resolved persisted authority for this installation.
class LinkedInstallationAuthoritySnapshot {
  const LinkedInstallationAuthoritySnapshot({
    required this.disposition,
    required this.credential,
    required this.failClosedReason,
  });

  final LinkedInstallationDisposition disposition;

  /// Present for [LinkedInstallationDisposition.preparing] and
  /// [LinkedInstallationDisposition.active].
  final LinkedTransportCredential? credential;

  /// Non-null only for [LinkedInstallationDisposition.failClosed]. Carries a
  /// coarse reason code — never key material.
  final String? failClosedReason;

  /// True when ordinary primary startup may proceed byte-for-byte.
  bool get isOrdinaryPrimary =>
      disposition == LinkedInstallationDisposition.primary;

  /// True when this installation must start the exact linked transport.
  bool get isActiveLinkedSecondary =>
      disposition == LinkedInstallationDisposition.active;

  /// True when startup must refuse. A half-pair, a corrupt envelope, a
  /// cross-account binding, and device-ID drift are all in this bucket: none
  /// of them may fall back to the account transport, because doing so would
  /// put two installations back on one shared relay mailbox.
  bool get refusesStartup =>
      disposition == LinkedInstallationDisposition.awaitingCredential ||
      disposition == LinkedInstallationDisposition.preparing ||
      disposition == LinkedInstallationDisposition.failClosed;
}

/// Outcome of one linked setup step.
enum LinkedInstallationSetupResult {
  success,

  /// The bridge refused, or the generated key failed its own ownership proof.
  bridgeError,

  /// The canonical runtime installation ID is missing.
  missingDeviceIdentity,

  /// Persisted authority is in a state this step cannot advance from.
  refused,
}

/// Crash-safe owner of this installation's linked role and transport identity.
///
/// The write ORDER is the contract, and it is deliberately marker-first:
///
///   1. expected-role marker,
///   2. create (or re-adopt) exactly ONE credential in `preparing`,
///   3. save the restored logical account identity and installation-local
///      ML-KEM (owned by the caller, between steps 2 and 4),
///   4. transition THAT EXACT credential to `active`, last.
///
/// Every intermediate crash therefore lands on a state that refuses normal
/// startup instead of one that looks primary. The inverse order — credential
/// first — would produce an installation holding a live transport identity
/// that no marker claims, which is indistinguishable from corruption.
class LinkedInstallationAuthority {
  LinkedInstallationAuthority({
    required SecureKeyStore secureKeyStore,
    DateTime Function()? now,
  }) : _secureKeyStore = secureKeyStore,
       _now = now ?? DateTime.now;

  final SecureKeyStore _secureKeyStore;
  final DateTime Function() _now;

  /// Classifies the persisted authority.
  ///
  /// [expectedAccountPeerId] is the logical account this installation
  /// currently holds, when known. A credential bound to a DIFFERENT account is
  /// fail-closed rather than adopted.
  Future<LinkedInstallationAuthoritySnapshot> load({
    String? expectedAccountPeerId,
  }) async {
    final marker = (await _secureKeyStore.read(
      linkedInstallationRoleStorageKey,
    ))?.trim();
    final rawCredential = await _secureKeyStore.read(
      linkedInstallationTransportCredentialStorageKey,
    );
    final hasMarker = marker == linkedInstallationRoleMarkerValue;
    final hasRawCredential =
        rawCredential != null && rawCredential.trim().isNotEmpty;

    if (marker != null && marker.isNotEmpty && !hasMarker) {
      return _failClosed('unknown_role_marker');
    }
    if (!hasMarker && !hasRawCredential) {
      return const LinkedInstallationAuthoritySnapshot(
        disposition: LinkedInstallationDisposition.primary,
        credential: null,
        failClosedReason: null,
      );
    }
    if (!hasMarker && hasRawCredential) {
      // A live transport identity that no marker claims. Never adopt it and
      // never delete it here: only an explicit reset may retire authority.
      return _failClosed('credential_without_role_marker');
    }
    if (!hasRawCredential) {
      return const LinkedInstallationAuthoritySnapshot(
        disposition: LinkedInstallationDisposition.awaitingCredential,
        credential: null,
        failClosedReason: null,
      );
    }

    final credential = LinkedTransportCredential.tryParse(rawCredential);
    if (credential == null) {
      return _failClosed('corrupt_credential');
    }
    if (expectedAccountPeerId != null &&
        expectedAccountPeerId.trim().isNotEmpty &&
        credential.accountPeerId != expectedAccountPeerId.trim()) {
      return _failClosed('cross_account_credential');
    }

    final deviceId = await _canonicalDeviceId();
    if (deviceId == null || deviceId != credential.deviceId) {
      // Missing/reset/mismatched runtime ID after activation REFUSES rather
      // than rotating transport identity: rotating would silently orphan every
      // binding a contact already verified against the old transport peer.
      return _failClosed('canonical_device_id_mismatch');
    }

    // The stored public key must still derive the stored peer. This catches a
    // partially-rewritten envelope that survived JSON parsing.
    if (!ed25519PublicKeyMatchesPeerId(
      base64PublicKey: credential.transportPublicKey,
      claimedPeerId: credential.transportPeerId,
    )) {
      return _failClosed('transport_peer_derivation_mismatch');
    }

    return LinkedInstallationAuthoritySnapshot(
      disposition: credential.state == LinkedTransportCredentialState.active
          ? LinkedInstallationDisposition.active
          : LinkedInstallationDisposition.preparing,
      credential: credential,
      failClosedReason: null,
    );
  }

  /// Step 1 — records that this installation expects to be a linked secondary.
  Future<void> markExpectedLinkedRole() async {
    await _writeAndVerify(
      linkedInstallationRoleStorageKey,
      linkedInstallationRoleMarkerValue,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_ROLE_MARKER_WRITTEN',
      details: const {},
    );
  }

  /// Step 2 — creates, or re-adopts, exactly one `preparing` credential.
  ///
  /// Idempotent by construction. Once a `preparing` credential exists, a
  /// resumed setup returns THOSE EXACT BYTES; it never mints a second
  /// identity. Two identities would mean the QR the contact scanned yesterday
  /// names a transport this installation no longer starts.
  ///
  /// [callIdentityGenerate] reuses the incumbent bridge identity generation;
  /// [callSign]/[callVerify] reuse the incumbent Ed25519 challenge so private
  /// and public halves are proven to belong together BEFORE anything durable
  /// depends on them.
  Future<(LinkedInstallationSetupResult, LinkedTransportCredential?)>
  createOrResumeTransportCredential({
    required String accountPeerId,
    required String accountPublicKey,
    required Future<Map<String, dynamic>> Function() callIdentityGenerate,
    required Future<Map<String, dynamic>> Function(
      String data,
      String privateKey,
    )
    callSign,
    required Future<bool> Function({
      required String publicKey,
      required String data,
      required String signature,
    })
    callVerify,
  }) async {
    final snapshot = await load(expectedAccountPeerId: accountPeerId);
    switch (snapshot.disposition) {
      case LinkedInstallationDisposition.preparing:
        // Resume with the same bytes.
        emitFlowEvent(
          layer: 'FL',
          event: 'LINKED_DEVICE_CREDENTIAL_RESUMED',
          details: const {},
        );
        return (LinkedInstallationSetupResult.success, snapshot.credential);
      case LinkedInstallationDisposition.active:
      case LinkedInstallationDisposition.failClosed:
      case LinkedInstallationDisposition.primary:
        // `primary` means the marker is absent: step 1 has not run, so there
        // is nothing to attach a credential to.
        return (LinkedInstallationSetupResult.refused, null);
      case LinkedInstallationDisposition.awaitingCredential:
        break;
    }

    final deviceId = await _canonicalDeviceId();
    if (deviceId == null) {
      return (LinkedInstallationSetupResult.missingDeviceIdentity, null);
    }

    final Map<String, dynamic> generated;
    try {
      generated = await callIdentityGenerate();
    } catch (error) {
      return _bridgeFailure('identity_generate_threw', error);
    }
    if (generated['ok'] != true) {
      return _bridgeFailure('identity_generate_not_ok', generated['errorCode']);
    }
    final identity = generated['identity'];
    if (identity is! Map) {
      return _bridgeFailure('identity_generate_shape', null);
    }
    final transportPeerId = _trimmedOrNull(identity['peerId']);
    final transportPublicKey = _trimmedOrNull(identity['publicKey']);
    final transportPrivateKey = _trimmedOrNull(identity['privateKey']);
    if (transportPeerId == null ||
        transportPublicKey == null ||
        transportPrivateKey == null) {
      return _bridgeFailure('identity_generate_missing_fields', null);
    }

    // Offline: the bridge's own peer must be the peer its public key derives
    // to. This is the same check the QR consumer runs, so a bridge that ever
    // disagreed with the pinned derivation is caught here rather than after a
    // contact has already trusted the device.
    if (!ed25519PublicKeyMatchesPeerId(
      base64PublicKey: transportPublicKey,
      claimedPeerId: transportPeerId,
    )) {
      return _bridgeFailure('transport_peer_derivation_mismatch', null);
    }

    // A fresh transport must never collide with the logical account identity.
    if (transportPeerId == accountPeerId.trim() ||
        transportPublicKey == accountPublicKey.trim()) {
      return _bridgeFailure('transport_equals_account_identity', null);
    }

    // Prove private/public ownership with the incumbent sign/verify challenge.
    final challenge =
        '$_transportOwnershipChallengeDomain\n'
        'account:${accountPeerId.trim()}\n'
        'device:$deviceId\n'
        'transport:$transportPeerId';
    final Map<String, dynamic> signResponse;
    try {
      signResponse = await callSign(challenge, transportPrivateKey);
    } catch (error) {
      return _bridgeFailure('ownership_sign_threw', error);
    }
    final signature = _trimmedOrNull(signResponse['signature']);
    if (signResponse['ok'] != true || signature == null) {
      return _bridgeFailure('ownership_sign_failed', signResponse['errorCode']);
    }
    final bool verified;
    try {
      verified = await callVerify(
        publicKey: transportPublicKey,
        data: challenge,
        signature: signature,
      );
    } catch (error) {
      return _bridgeFailure('ownership_verify_threw', error);
    }
    if (!verified) {
      return _bridgeFailure('ownership_verify_failed', null);
    }

    final credential = LinkedTransportCredential(
      state: LinkedTransportCredentialState.preparing,
      accountPeerId: accountPeerId.trim(),
      accountPublicKey: accountPublicKey.trim(),
      deviceId: deviceId,
      transportPeerId: transportPeerId,
      transportPublicKey: transportPublicKey,
      transportPrivateKey: transportPrivateKey,
      createdAt: _now().toUtc().toIso8601String(),
      activatedAt: null,
    );
    await _writeAndVerify(
      linkedInstallationTransportCredentialStorageKey,
      jsonEncode(credential.toJson()),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_CREDENTIAL_PREPARED',
      details: {'transportPeerId': _redactPeer(transportPeerId)},
    );
    return (LinkedInstallationSetupResult.success, credential);
  }

  /// Step 4 — transitions THAT EXACT credential to `active`.
  ///
  /// [expectedTransportPeerId] is required so a caller cannot activate a
  /// credential other than the one it just prepared and published.
  Future<LinkedInstallationSetupResult> activateTransportCredential({
    required String accountPeerId,
    required String expectedTransportPeerId,
  }) async {
    final snapshot = await load(expectedAccountPeerId: accountPeerId);
    if (snapshot.disposition == LinkedInstallationDisposition.active) {
      // Idempotent only for the same credential.
      return snapshot.credential?.transportPeerId ==
              expectedTransportPeerId.trim()
          ? LinkedInstallationSetupResult.success
          : LinkedInstallationSetupResult.refused;
    }
    if (snapshot.disposition != LinkedInstallationDisposition.preparing) {
      return LinkedInstallationSetupResult.refused;
    }
    final credential = snapshot.credential;
    if (credential == null ||
        credential.transportPeerId != expectedTransportPeerId.trim()) {
      return LinkedInstallationSetupResult.refused;
    }

    final activated = credential.copyWithActivated(
      _now().toUtc().toIso8601String(),
    );
    await _writeAndVerify(
      linkedInstallationTransportCredentialStorageKey,
      jsonEncode(activated.toJson()),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_CREDENTIAL_ACTIVATED',
      details: {'transportPeerId': _redactPeer(activated.transportPeerId)},
    );
    return LinkedInstallationSetupResult.success;
  }

  Future<String?> _canonicalDeviceId() async {
    // Read only. Minting the canonical installation ID stays with
    // CanonicalRuntimeBindingCoordinator; a competing identifier here would
    // mean two device IDs describing one installation.
    final id = (await _secureKeyStore.read(
      canonicalRuntimeInstallationIdStorageKey,
    ))?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _writeAndVerify(String key, String value) async {
    await _secureKeyStore.write(key, value);
    if (await _secureKeyStore.read(key) != value) {
      throw StateError('linked installation authority write was not durable');
    }
  }

  LinkedInstallationAuthoritySnapshot _failClosed(String reason) {
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_AUTHORITY_FAIL_CLOSED',
      details: {'reason': reason},
    );
    return LinkedInstallationAuthoritySnapshot(
      disposition: LinkedInstallationDisposition.failClosed,
      credential: null,
      failClosedReason: reason,
    );
  }

  (LinkedInstallationSetupResult, LinkedTransportCredential?) _bridgeFailure(
    String reason,
    Object? detail,
  ) {
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_CREDENTIAL_BRIDGE_ERROR',
      details: {'reason': reason, if (detail != null) 'detail': '$detail'},
    );
    return (LinkedInstallationSetupResult.bridgeError, null);
  }

  static String? _trimmedOrNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _redactPeer(String peerId) =>
      peerId.length <= 12 ? peerId : peerId.substring(0, 12);
}
