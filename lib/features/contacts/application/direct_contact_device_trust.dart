import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/ios_nse_inbox_projection.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
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

  /// Stages ONE authenticated linked-device document as `pending`.
  ///
  /// Admission is NOT granted here — the row is pending until explicit Verify
  /// on the contact profile. The repository re-reads the contact's current
  /// account key AND its blocked state inside the staging transaction, so a
  /// contact blocked or rotated between the scan and this write is refused.
  Future<DirectContactDeviceBindingStageOutcome> stagePendingBinding(
    DirectLinkedDeviceQrDocument document,
  );

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
  Future<DirectContactDeviceBindingStageOutcome> stagePendingBinding(
    DirectLinkedDeviceQrDocument document,
  ) => Future.value(DirectContactDeviceBindingStageOutcome.refused);

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
    DirectReactionNotificationProjection? notificationProjection,
    DateTime Function()? now,
  }) : _database = database,
       _notificationProjection = notificationProjection,
       _now = now ?? DateTime.now;

  final Database _database;
  final DirectReactionNotificationProjection? _notificationProjection;
  final DateTime Function() _now;

  String get _decidedAt => _now().toUtc().toIso8601String();

  @override
  Future<DirectContactDeviceRoster> loadRoster(String contactAccountPeerId) {
    return dbLoadDirectContactDeviceRoster(_database, contactAccountPeerId);
  }

  @override
  Future<DirectContactDeviceBindingStageOutcome> stagePendingBinding(
    DirectLinkedDeviceQrDocument document,
  ) {
    return dbStageDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: document.accountPeerId,
      accountSigningPublicKey: document.accountPublicKey,
      deviceId: document.deviceId,
      transportPeerId: document.transportPeerId,
      transportPublicKey: document.transportPublicKey,
      deviceMlKemPublicKey: document.deviceMlKemPublicKey,
      stagedAt: _decidedAt,
    );
  }

  @override
  Future<bool> verifyDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) => _mutateProjectedAuthority(
    contactAccountPeerId,
    () => dbVerifyDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      deviceId: deviceId,
      expectedFingerprint: expectedFingerprint,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      decidedAt: _decidedAt,
    ),
  );

  @override
  Future<bool> rejectDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) => _mutateProjectedAuthority(
    contactAccountPeerId,
    () => dbRejectDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      deviceId: deviceId,
      expectedFingerprint: expectedFingerprint,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      decidedAt: _decidedAt,
    ),
  );

  @override
  Future<bool> revokeDevice({
    required String contactAccountPeerId,
    required String deviceId,
    required String expectedFingerprint,
    required String expectedAccountSigningPublicKey,
  }) => _mutateProjectedAuthority(
    contactAccountPeerId,
    () => dbRevokeDirectContactDeviceBinding(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      deviceId: deviceId,
      expectedFingerprint: expectedFingerprint,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      decidedAt: _decidedAt,
    ),
  );

  @override
  Future<bool> revokeLegacyTarget({
    required String contactAccountPeerId,
    required String expectedAccountSigningPublicKey,
    required String expectedLegacyPeerId,
    required String expectedLegacyMlKemPublicKey,
  }) => _mutateProjectedAuthority(
    contactAccountPeerId,
    () => dbRevokeDirectContactLegacyTarget(
      _database,
      contactAccountPeerId: contactAccountPeerId,
      expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
      expectedLegacyPeerId: expectedLegacyPeerId,
      expectedLegacyMlKemPublicKey: expectedLegacyMlKemPublicKey,
      decidedAt: _decidedAt,
    ),
  );

  Future<bool> _mutateProjectedAuthority(
    String contactAccountPeerId,
    Future<bool> Function() mutation,
  ) async {
    final projection = _notificationProjection;
    if (projection == null) return mutation();
    await projection.retireContactTransportAuthority(contactAccountPeerId);
    final committed = await mutation();
    final transports = await loadDirectNotificationAuthorizedTransportPeerIds(
      _database,
      contactAccountPeerId,
    );
    await projection.replaceContactTransportAuthority(
      peerId: contactAccountPeerId,
      authorizedTransportPeerIds: transports,
    );
    return committed;
  }
}

/// Reads the currently authorized physical senders for one logical contact.
/// This deliberately does not consult `ContactModel` display state.
Future<List<String>> loadDirectNotificationAuthorizedTransportPeerIds(
  Database database,
  String contactAccountPeerId,
) async {
  final contact = contactAccountPeerId.trim();
  if (contact.isEmpty) return const <String>[];
  final rows = await database.query(
    'contacts',
    columns: const <String>['peer_id', 'public_key', 'is_blocked'],
    where: 'peer_id = ?',
    whereArgs: <Object?>[contact],
    limit: 1,
  );
  if (rows.isEmpty) return const <String>[];
  final row = rows.single;
  final accountKey = row['public_key'];
  final blocked = row['is_blocked'];
  if (accountKey is! String ||
      accountKey.trim().isEmpty ||
      accountKey != accountKey.trim() ||
      !isNativeCompatibleIosNsePeerId(contact) ||
      !ed25519PublicKeyMatchesPeerId(
        base64PublicKey: accountKey,
        claimedPeerId: contact,
      ) ||
      (blocked is int ? blocked != 0 : blocked == true)) {
    return const <String>[];
  }
  final roster = await dbLoadDirectContactDeviceRoster(database, contact);
  final peers = <String>{
    if (!roster.metadata.rosterInitialized ||
        !roster.metadata.legacyTargetRevoked)
      contact,
    if (roster.metadata.rosterInitialized)
      for (final binding in roster.activeBindings)
        if (binding.verifiedAccountSigningPublicKey == accountKey &&
            isNativeCompatibleIosNsePeerId(binding.transportPeerId) &&
            ed25519PublicKeyMatchesPeerId(
              base64PublicKey: binding.transportPublicKey,
              claimedPeerId: binding.transportPeerId,
            ))
          binding.transportPeerId,
  }.toList(growable: false)..sort();
  return peers;
}
