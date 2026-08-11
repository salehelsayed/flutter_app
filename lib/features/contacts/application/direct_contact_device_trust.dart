import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// The exact linked-device trust authority the contact profile owns.
///
/// Every mutating method takes the caller's BELIEVED authority — the binding's
/// full immutable fingerprint and the contact's account signing key — and the
/// implementation re-reads both inside one transaction before acting. The
/// screen therefore cannot decide on behalf of a row it never actually
/// rendered: a contact whose key rotated, a binding another surface just
/// revoked, and a stale route argument all fail closed.
abstract interface class DirectContactDeviceTrustCapability {
  /// Loads the roster snapshot shown on the profile.
  Future<DirectContactDeviceRoster> loadRoster(String contactAccountPeerId);

  /// Activates exactly one PENDING binding.
  Future<bool> verifyDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  });

  /// Records exact inactive authority for one PENDING binding.
  Future<bool> rejectDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  });

  /// Withdraws exactly one ACTIVE binding.
  Future<bool> revokeDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  });

  /// Revokes the contact's DYNAMIC legacy account target.
  ///
  /// Separate from [revokeDevice] because the legacy target is not a binding
  /// row — its peer and ML-KEM key live in `contacts` and legitimately change
  /// under ordinary key rotation.
  Future<bool> revokeLegacyTarget({
    required String contactAccountPeerId,
    required String expectedAccountSigningPublicKey,
    required String expectedLegacyPeerId,
    required String expectedLegacyMlKemPublicKey,
  });
}

/// Inert capability for surfaces that have no database handle.
///
/// Reports an EMPTY, uninitialized roster and refuses every decision. Two
/// consequences are deliberate: the profile renders exactly as it did before
/// Plan 360 (no linked-devices card, `v1` safety number), and no decision can
/// be recorded from a surface that could not have read the real authority in
/// the first place.
///
/// This exists so the profile screen's capability can stay REQUIRED and
/// non-null — the boundary where a missing wire actually matters — without
/// forcing a new required parameter through the hundreds of existing
/// construction sites of the two wired host screens.
class UnavailableDirectContactDeviceTrust
    implements DirectContactDeviceTrustCapability {
  const UnavailableDirectContactDeviceTrust();

  @override
  Future<DirectContactDeviceRoster> loadRoster(String contactAccountPeerId) {
    return Future.value(
      DirectContactDeviceRoster(
        metadata: DirectContactDeviceRosterMetadata.uninitialized(
          contactAccountPeerId,
        ),
        bindings: const <DirectContactDeviceBinding>[],
      ),
    );
  }

  @override
  Future<bool> verifyDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) => Future.value(false);

  @override
  Future<bool> rejectDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) => Future.value(false);

  @override
  Future<bool> revokeDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) => Future.value(false);

  @override
  Future<bool> revokeLegacyTarget({
    required String contactAccountPeerId,
    required String expectedAccountSigningPublicKey,
    required String expectedLegacyPeerId,
    required String expectedLegacyMlKemPublicKey,
  }) => Future.value(false);
}

/// Real-database implementation.
class DatabaseDirectContactDeviceTrust
    implements DirectContactDeviceTrustCapability {
  DatabaseDirectContactDeviceTrust({
    required Database database,
    DateTime Function()? now,
  }) : _database = database,
       _now = now ?? DateTime.now;

  final Database _database;
  final DateTime Function() _now;

  String get _decidedAt => _now().toUtc().toIso8601String();

  @override
  Future<DirectContactDeviceRoster> loadRoster(String contactAccountPeerId) {
    return dbLoadDirectContactDeviceRoster(_database, contactAccountPeerId);
  }

  @override
  Future<bool> verifyDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) {
    return dbVerifyDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      deviceId: deviceId,
      expectedFingerprint: expectedFingerprint,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      decidedAt: _decidedAt,
    );
  }

  @override
  Future<bool> rejectDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) {
    return dbRejectDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      deviceId: deviceId,
      expectedFingerprint: expectedFingerprint,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      decidedAt: _decidedAt,
    );
  }

  @override
  Future<bool> revokeDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) {
    return dbRevokeDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      deviceId: deviceId,
      expectedFingerprint: expectedFingerprint,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      decidedAt: _decidedAt,
    );
  }

  @override
  Future<bool> revokeLegacyTarget({
    required String contactAccountPeerId,
    required String expectedAccountSigningPublicKey,
    required String expectedLegacyPeerId,
    required String expectedLegacyMlKemPublicKey,
  }) {
    return dbRevokeDirectContactLegacyTarget(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      expectedLegacyPeerId: expectedLegacyPeerId,
      expectedLegacyMlKemPublicKey: expectedLegacyMlKemPublicKey,
      decidedAt: _decidedAt,
    );
  }
}
