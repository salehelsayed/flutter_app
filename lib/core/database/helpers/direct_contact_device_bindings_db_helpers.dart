import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../../utils/key_conversion.dart';
import '../db_write_transaction.dart';
import '../direct_event_fanout_contract.dart';
import '../migrations/112_direct_linked_device_addressing.dart';

/// Admission state of one authenticated linked-device binding.
enum DirectContactDeviceBindingState {
  /// Dual-signed QR accepted, awaiting an explicit local trust decision.
  pending,

  /// Explicitly verified by the local user; a live addressing target.
  active,

  /// Explicitly refused. Records exact inactive authority so a replayed QR
  /// does not prompt again.
  rejected,

  /// Previously active, explicitly withdrawn. Never auto-reactivates.
  revoked;

  static DirectContactDeviceBindingState fromColumn(Object? value) {
    return switch (value) {
      'pending' => DirectContactDeviceBindingState.pending,
      'active' => DirectContactDeviceBindingState.active,
      'rejected' => DirectContactDeviceBindingState.rejected,
      'revoked' => DirectContactDeviceBindingState.revoked,
      _ => throw StateError('unknown linked-device binding state: $value'),
    };
  }
}

/// Outcome of staging one scanned linked-device binding.
enum DirectContactDeviceBindingStageOutcome {
  /// A new `pending` row was inserted.
  staged,

  /// The exact same immutable material already exists in ANY state. No row
  /// was written and no decision was reset.
  replayed,

  /// Refused all-zero. Nothing was inserted, updated, or deleted.
  refused,
}

/// One immutable authenticated linked-device binding row.
class DirectContactDeviceBinding {
  const DirectContactDeviceBinding({
    required this.contactAccountPeerId,
    required this.deviceId,
    required this.verifiedAccountSigningPublicKey,
    required this.transportPeerId,
    required this.transportPublicKey,
    required this.deviceMlKemPublicKey,
    required this.bindingFingerprint,
    required this.state,
    required this.stagedAt,
    required this.decidedAt,
  });

  final String contactAccountPeerId;
  final String deviceId;
  final String verifiedAccountSigningPublicKey;
  final String transportPeerId;
  final String transportPublicKey;
  final String deviceMlKemPublicKey;
  final String bindingFingerprint;
  final DirectContactDeviceBindingState state;
  final String stagedAt;
  final String? decidedAt;

  static DirectContactDeviceBinding fromRow(Map<String, Object?> row) {
    return DirectContactDeviceBinding(
      contactAccountPeerId: row['contact_account_peer_id'] as String,
      deviceId: row['device_id'] as String,
      verifiedAccountSigningPublicKey:
          row['verified_account_signing_public_key'] as String,
      transportPeerId: row['transport_peer_id'] as String,
      transportPublicKey: row['transport_public_key'] as String,
      deviceMlKemPublicKey: row['device_ml_kem_public_key'] as String,
      bindingFingerprint: row['binding_fingerprint'] as String,
      state: DirectContactDeviceBindingState.fromColumn(row['state']),
      stagedAt: row['staged_at'] as String,
      decidedAt: row['decided_at'] as String?,
    );
  }
}

/// Per-contact roster metadata.
class DirectContactDeviceRosterMetadata {
  const DirectContactDeviceRosterMetadata({
    required this.contactAccountPeerId,
    required this.rosterInitialized,
    required this.legacyTargetRevoked,
    required this.initializedAt,
    required this.legacyRevokedAt,
  });

  /// The pre-initialization default for a contact with no metadata row.
  factory DirectContactDeviceRosterMetadata.uninitialized(
    String contactAccountPeerId,
  ) {
    return DirectContactDeviceRosterMetadata(
      contactAccountPeerId: contactAccountPeerId,
      rosterInitialized: false,
      legacyTargetRevoked: false,
      initializedAt: null,
      legacyRevokedAt: null,
    );
  }

  final String contactAccountPeerId;
  final bool rosterInitialized;
  final bool legacyTargetRevoked;
  final String? initializedAt;
  final String? legacyRevokedAt;

  static DirectContactDeviceRosterMetadata fromRow(Map<String, Object?> row) {
    return DirectContactDeviceRosterMetadata(
      contactAccountPeerId: row['contact_account_peer_id'] as String,
      rosterInitialized: (row['roster_initialized'] as int? ?? 0) == 1,
      legacyTargetRevoked: row['legacy_target_state'] == 'revoked',
      initializedAt: row['initialized_at'] as String?,
      legacyRevokedAt: row['legacy_revoked_at'] as String?,
    );
  }
}

/// One resolved addressing target for a direct contact.
class DirectContactDeviceTarget {
  const DirectContactDeviceTarget({
    required this.peerId,
    required this.mlKemPublicKey,
    required this.isLegacyAccountTarget,
    this.deviceId,
  });

  /// The transport peer to address.
  final String peerId;

  /// The ML-KEM public key that peer decrypts with.
  final String mlKemPublicKey;

  /// True for the contact's own dynamic account target (read live from
  /// `contacts`), false for an explicitly verified linked device.
  final bool isLegacyAccountTarget;

  /// Null for the legacy account target.
  final String? deviceId;
}

/// Full roster snapshot for one contact.
class DirectContactDeviceRoster {
  const DirectContactDeviceRoster({
    required this.metadata,
    required this.bindings,
  });

  final DirectContactDeviceRosterMetadata metadata;
  final List<DirectContactDeviceBinding> bindings;

  Iterable<DirectContactDeviceBinding> get activeBindings =>
      bindings.where((b) => b.state == DirectContactDeviceBindingState.active);

  Iterable<DirectContactDeviceBinding> get pendingBindings =>
      bindings.where((b) => b.state == DirectContactDeviceBindingState.pending);
}

/// Domain separator for the immutable binding fingerprint.
const String _bindingFingerprintDomain =
    'mknoon-direct-linked-device-binding-v1';

/// Computes the immutable fingerprint for one linked-device binding.
///
/// It covers EXACTLY the immutable identity material: contact account peer,
/// verified account signing key, device ID, transport peer, transport public
/// key, and the device ML-KEM public key.
///
/// QR issued-at and BOTH signatures are deliberately excluded. A contact who
/// re-issues a fresh QR for the same credential must replay as identical, not
/// as a contradictory second binding that re-prompts for a trust decision the
/// user already made.
String computeDirectContactDeviceBindingFingerprint({
  required String contactAccountPeerId,
  required String accountSigningPublicKey,
  required String deviceId,
  required String transportPeerId,
  required String transportPublicKey,
  required String deviceMlKemPublicKey,
}) {
  final material =
      '$_bindingFingerprintDomain\n'
      'account:${contactAccountPeerId.trim()}\n'
      'accountKey:${accountSigningPublicKey.trim()}\n'
      'device:${deviceId.trim()}\n'
      'transportPeer:${transportPeerId.trim()}\n'
      'transportKey:${transportPublicKey.trim()}\n'
      'mlkem:${deviceMlKemPublicKey.trim()}';
  return sha256.convert(utf8.encode(material)).toString();
}

/// Domain separator for the DYNAMIC legacy account target's fingerprint.
const String _legacyTargetFingerprintDomain =
    'mknoon-direct-linked-device-legacy-target-v1';

/// Fingerprint of the contact's dynamic legacy account target.
///
/// Distinct domain from [computeDirectContactDeviceBindingFingerprint] so a
/// legacy target can never be mistaken for — or substituted into — a binding
/// row. Unlike a binding fingerprint this value is NOT immutable: it moves
/// with ordinary contact key rotation, which is exactly why the legacy target
/// is never materialized as a binding.
String computeDirectContactLegacyTargetFingerprint({
  required String contactAccountPeerId,
  required String accountSigningPublicKey,
  required String legacyMlKemPublicKey,
}) {
  final material =
      '$_legacyTargetFingerprintDomain\n'
      'account:${contactAccountPeerId.trim()}\n'
      'accountKey:${accountSigningPublicKey.trim()}\n'
      'mlkem:${legacyMlKemPublicKey.trim()}';
  return sha256.convert(utf8.encode(material)).toString();
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;

/// The contact facts every admission and resolution re-reads transactionally.
class _CurrentContactAuthority {
  const _CurrentContactAuthority({
    required this.accountSigningPublicKey,
    required this.isBlocked,
  });

  final String accountSigningPublicKey;
  final bool isBlocked;
}

/// Reads the contact's CURRENT account signing key and blocked state in [txn].
///
/// Returns null when the contact does not exist, or when its account key is
/// missing. Every trust decision and every resolution re-reads this rather than
/// trusting a value the UI or a QR parse captured earlier: a contact whose
/// account key rotated must invalidate stale device authority instead of
/// silently keeping it.
///
/// Blocked state is read HERE, inside the transaction, not only at parse time.
/// The scanner necessarily checks `contact.isBlocked` before it can even
/// authenticate a document, but that check and the staging write are separate
/// operations — a contact blocked in between would otherwise still acquire a
/// pending binding, and blocking is exactly the signal that the user no longer
/// wants new authority from that person.
Future<_CurrentContactAuthority?> _currentContactAuthority(
  DatabaseExecutor txn,
  String contactAccountPeerId,
) async {
  final rows = await txn.query(
    'contacts',
    columns: const <String>['public_key', 'is_blocked'],
    where: 'peer_id = ?',
    whereArgs: <Object?>[contactAccountPeerId],
    limit: 1,
  );
  if (rows.isEmpty) {
    return null;
  }
  final key = rows.first['public_key'];
  if (key is! String || key.trim().isEmpty) {
    return null;
  }
  final blocked = rows.first['is_blocked'];
  return _CurrentContactAuthority(
    accountSigningPublicKey: key,
    isBlocked: blocked is int ? blocked != 0 : blocked == true,
  );
}

/// Convenience for callers that only need the current account key.
Future<String?> _currentContactAccountKey(
  DatabaseExecutor txn,
  String contactAccountPeerId,
) async => (await _currentContactAuthority(
  txn,
  contactAccountPeerId,
))?.accountSigningPublicKey;

/// Stages one scanned linked-device binding as `pending`.
///
/// Refuses ALL-ZERO (writes nothing) when any of the following holds:
///
/// * a field is blank, or a key/peer pair fails offline derivation,
/// * the transport peer equals the contact's account peer (not a linked
///   device),
/// * the contact does not exist, or its current account signing key differs
///   from the key the QR carried (stale or cross-account),
/// * a row for the same `(contact, device)` exists with DIFFERENT immutable
///   material,
/// * the transport peer is already owned by a different `(contact, device)`,
/// * the contact already holds [directContactDeviceBindingCapacity] bindings.
///
/// Exact replay of an already-known binding returns
/// [DirectContactDeviceBindingStageOutcome.replayed] in EVERY state — pending,
/// active, rejected, or revoked — and is checked BEFORE the capacity bound so
/// a re-scan at capacity stays idempotent rather than refusing.
Future<DirectContactDeviceBindingStageOutcome>
dbStageDirectContactDeviceBinding(
  Database db, {
  required String contactAccountPeerId,
  required String accountSigningPublicKey,
  required String deviceId,
  required String transportPeerId,
  required String transportPublicKey,
  required String deviceMlKemPublicKey,
  required String stagedAt,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_LINKED_DEVICE_STAGE_START',
    details: {'deviceId': deviceId},
  );

  if (_isBlank(contactAccountPeerId) ||
      _isBlank(accountSigningPublicKey) ||
      _isBlank(deviceId) ||
      _isBlank(transportPeerId) ||
      _isBlank(transportPublicKey) ||
      _isBlank(deviceMlKemPublicKey) ||
      _isBlank(stagedAt)) {
    return _refusedStage('blank_field');
  }

  final normalizedContact = contactAccountPeerId.trim();
  final normalizedAccountKey = accountSigningPublicKey.trim();
  final normalizedDeviceId = deviceId.trim();
  final normalizedTransportPeer = transportPeerId.trim();
  final normalizedTransportKey = transportPublicKey.trim();
  final normalizedMlKem = deviceMlKemPublicKey.trim();

  if (normalizedDeviceId.length > 128) {
    return _refusedStage('device_id_too_long');
  }
  if (normalizedTransportPeer == normalizedContact) {
    return _refusedStage('transport_equals_account');
  }
  if (normalizedTransportKey == normalizedAccountKey) {
    return _refusedStage('transport_key_equals_account_key');
  }

  // Offline proof that each claimed peer really is the peer its carried key
  // derives to. Without this a tampered QR could bind a device row to a peer
  // string nobody controls.
  if (!ed25519PublicKeyMatchesPeerId(
    base64PublicKey: normalizedAccountKey,
    claimedPeerId: normalizedContact,
  )) {
    return _refusedStage('account_peer_derivation_mismatch');
  }
  if (!ed25519PublicKeyMatchesPeerId(
    base64PublicKey: normalizedTransportKey,
    claimedPeerId: normalizedTransportPeer,
  )) {
    return _refusedStage('transport_peer_derivation_mismatch');
  }

  final fingerprint = computeDirectContactDeviceBindingFingerprint(
    contactAccountPeerId: normalizedContact,
    accountSigningPublicKey: normalizedAccountKey,
    deviceId: normalizedDeviceId,
    transportPeerId: normalizedTransportPeer,
    transportPublicKey: normalizedTransportKey,
    deviceMlKemPublicKey: normalizedMlKem,
  );

  try {
    return await dbWriteTransaction<DirectContactDeviceBindingStageOutcome>(
      db,
      (txn) async {
        final currentAuthority = await _currentContactAuthority(
          txn,
          normalizedContact,
        );
        if (currentAuthority == null) {
          return _refusedStage('unknown_contact');
        }
        if (currentAuthority.isBlocked) {
          // TOCTOU close: the scanner checked this before authenticating, but a
          // contact blocked between that check and this write must not acquire
          // authority.
          return _refusedStage('blocked_contact');
        }
        if (currentAuthority.accountSigningPublicKey != normalizedAccountKey) {
          return _refusedStage('contact_account_key_drift');
        }

        final existing = await txn.query(
          'direct_contact_device_bindings',
          where: 'contact_account_peer_id = ? AND device_id = ?',
          whereArgs: <Object?>[normalizedContact, normalizedDeviceId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final row = DirectContactDeviceBinding.fromRow(existing.first);
          // Replay wins in EVERY state and BEFORE capacity.
          if (row.bindingFingerprint == fingerprint) {
            emitFlowEvent(
              layer: 'DB',
              event: 'DIRECT_LINKED_DEVICE_STAGE_REPLAYED',
              details: {
                'deviceId': normalizedDeviceId,
                'state': row.state.name,
              },
            );
            return DirectContactDeviceBindingStageOutcome.replayed;
          }
          return _refusedStage('immutable_material_changed');
        }

        // One transport peer belongs to exactly one linked device, globally.
        final transportOwner = await txn.query(
          'direct_contact_device_bindings',
          columns: const <String>['device_id'],
          where: 'transport_peer_id = ?',
          whereArgs: <Object?>[normalizedTransportPeer],
          limit: 1,
        );
        if (transportOwner.isNotEmpty) {
          return _refusedStage('duplicate_transport_owner');
        }

        final countRows = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM direct_contact_device_bindings '
          'WHERE contact_account_peer_id = ?',
          <Object?>[normalizedContact],
        );
        final existingCount = (countRows.first['c'] as int?) ?? 0;
        if (existingCount >= directContactDeviceBindingCapacity) {
          return _refusedStage('capacity_exceeded');
        }

        await txn.insert('direct_contact_device_bindings', <String, Object?>{
          'contact_account_peer_id': normalizedContact,
          'device_id': normalizedDeviceId,
          'verified_account_signing_public_key': normalizedAccountKey,
          'transport_peer_id': normalizedTransportPeer,
          'transport_public_key': normalizedTransportKey,
          'device_ml_kem_public_key': normalizedMlKem,
          'binding_fingerprint': fingerprint,
          'state': 'pending',
          'staged_at': stagedAt.trim(),
          'decided_at': null,
        });

        emitFlowEvent(
          layer: 'DB',
          event: 'DIRECT_LINKED_DEVICE_STAGE_SUCCESS',
          details: {'deviceId': normalizedDeviceId},
        );
        return DirectContactDeviceBindingStageOutcome.staged;
      },
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_STAGE_ERROR',
      details: {'error': error.toString()},
    );
    return DirectContactDeviceBindingStageOutcome.refused;
  }
}

DirectContactDeviceBindingStageOutcome _refusedStage(String reason) {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_LINKED_DEVICE_STAGE_REFUSED',
    details: {'reason': reason},
  );
  return DirectContactDeviceBindingStageOutcome.refused;
}

/// Shared exact-compare-and-swap for the three binding trust decisions.
///
/// EVERY decision re-reads, inside one transaction:
///   * the contact's current account signing key,
///   * the target row's FULL immutable fingerprint,
///   * the target row's exact current state,
/// and refuses unless all three match what the caller believed. Stale UI, a
/// contact key that rotated since the screen rendered, and a racing decision
/// from another surface therefore all fail closed rather than mutating
/// authority the user never actually reviewed.
Future<bool> _decideDirectContactDeviceBinding(
  Database db, {
  required String contactAccountPeerId,
  required String deviceId,
  required String expectedFingerprint,
  required String expectedAccountSigningPublicKey,
  required DirectContactDeviceBindingState expectedState,
  required DirectContactDeviceBindingState nextState,
  required String decidedAt,
  required bool initializesRoster,
  required String event,
}) async {
  if (_isBlank(contactAccountPeerId) ||
      _isBlank(deviceId) ||
      _isBlank(expectedFingerprint) ||
      _isBlank(expectedAccountSigningPublicKey) ||
      _isBlank(decidedAt)) {
    return false;
  }

  final normalizedContact = contactAccountPeerId.trim();
  final normalizedDeviceId = deviceId.trim();
  final normalizedFingerprint = expectedFingerprint.trim().toLowerCase();
  final normalizedExpectedKey = expectedAccountSigningPublicKey.trim();
  final normalizedDecidedAt = decidedAt.trim();

  try {
    return await dbWriteTransaction<bool>(db, (txn) async {
      final currentAccountKey = await _currentContactAccountKey(
        txn,
        normalizedContact,
      );
      if (currentAccountKey == null ||
          currentAccountKey != normalizedExpectedKey) {
        return false;
      }

      final rows = await txn.query(
        'direct_contact_device_bindings',
        where: 'contact_account_peer_id = ? AND device_id = ?',
        whereArgs: <Object?>[normalizedContact, normalizedDeviceId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return false;
      }
      final row = DirectContactDeviceBinding.fromRow(rows.first);
      if (row.bindingFingerprint != normalizedFingerprint ||
          row.state != expectedState ||
          row.verifiedAccountSigningPublicKey != currentAccountKey) {
        return false;
      }

      final updated = await txn.update(
        'direct_contact_device_bindings',
        <String, Object?>{
          'state': nextState.name,
          'decided_at': normalizedDecidedAt,
        },
        // The WHERE clause repeats the full CAS so a concurrent writer that
        // slipped between the read and the update cannot be overwritten.
        where:
            'contact_account_peer_id = ? AND device_id = ? AND '
            'binding_fingerprint = ? AND state = ?',
        whereArgs: <Object?>[
          normalizedContact,
          normalizedDeviceId,
          normalizedFingerprint,
          expectedState.name,
        ],
      );
      if (updated != 1) {
        return false;
      }

      if (initializesRoster) {
        await _initializeRosterMetadata(
          txn,
          contactAccountPeerId: normalizedContact,
          at: normalizedDecidedAt,
        );
      }

      emitFlowEvent(
        layer: 'DB',
        event: event,
        details: {'deviceId': normalizedDeviceId},
      );
      return true;
    });
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_DECISION_ERROR',
      details: {'error': error.toString()},
    );
    return false;
  }
}

/// Marks the roster initialized, leaving the legacy target ACTIVE by default.
///
/// Idempotent: a second decision must not move `initialized_at` and must never
/// resurrect a legacy target the user already revoked.
Future<void> _initializeRosterMetadata(
  DatabaseExecutor txn, {
  required String contactAccountPeerId,
  required String at,
}) async {
  final existing = await txn.query(
    'direct_contact_device_roster_metadata',
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[contactAccountPeerId],
    limit: 1,
  );
  if (existing.isEmpty) {
    await txn.insert('direct_contact_device_roster_metadata', <String, Object?>{
      'contact_account_peer_id': contactAccountPeerId,
      'roster_initialized': 1,
      'legacy_target_state': 'active',
      'initialized_at': at,
      'legacy_revoked_at': null,
      'updated_at': at,
    });
    return;
  }
  if ((existing.first['roster_initialized'] as int? ?? 0) == 1) {
    return;
  }
  await txn.update(
    'direct_contact_device_roster_metadata',
    <String, Object?>{
      'roster_initialized': 1,
      'initialized_at': at,
      'updated_at': at,
    },
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[contactAccountPeerId],
  );
}

/// Explicitly verifies one PENDING binding, activating exactly that device.
///
/// Also initializes roster metadata with the legacy target still active: the
/// first decision must not silently cut off the contact's existing account
/// target.
Future<bool> dbVerifyDirectContactDeviceBinding(
  Database db, {
  required String contactAccountPeerId,
  required String deviceId,
  required String expectedFingerprint,
  required String expectedAccountSigningPublicKey,
  required String decidedAt,
}) {
  return _decideDirectContactDeviceBinding(
    db,
    contactAccountPeerId: contactAccountPeerId,
    deviceId: deviceId,
    expectedFingerprint: expectedFingerprint,
    expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
    expectedState: DirectContactDeviceBindingState.pending,
    nextState: DirectContactDeviceBindingState.active,
    decidedAt: decidedAt,
    initializesRoster: true,
    event: 'DIRECT_LINKED_DEVICE_VERIFIED',
  );
}

/// Explicitly rejects one PENDING binding.
///
/// Recording exact inactive authority (rather than deleting the row) is what
/// makes a replayed QR idempotent: without it the same device would be staged
/// and re-prompt forever.
Future<bool> dbRejectDirectContactDeviceBinding(
  Database db, {
  required String contactAccountPeerId,
  required String deviceId,
  required String expectedFingerprint,
  required String expectedAccountSigningPublicKey,
  required String decidedAt,
}) {
  return _decideDirectContactDeviceBinding(
    db,
    contactAccountPeerId: contactAccountPeerId,
    deviceId: deviceId,
    expectedFingerprint: expectedFingerprint,
    expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
    expectedState: DirectContactDeviceBindingState.pending,
    nextState: DirectContactDeviceBindingState.rejected,
    decidedAt: decidedAt,
    initializesRoster: true,
    event: 'DIRECT_LINKED_DEVICE_REJECTED',
  );
}

/// Explicitly revokes one ACTIVE binding. No decision auto-reactivates.
Future<bool> dbRevokeDirectContactDeviceBinding(
  Database db, {
  required String contactAccountPeerId,
  required String deviceId,
  required String expectedFingerprint,
  required String expectedAccountSigningPublicKey,
  required String decidedAt,
}) {
  return _decideDirectContactDeviceBinding(
    db,
    contactAccountPeerId: contactAccountPeerId,
    deviceId: deviceId,
    expectedFingerprint: expectedFingerprint,
    expectedAccountSigningPublicKey: expectedAccountSigningPublicKey,
    expectedState: DirectContactDeviceBindingState.active,
    nextState: DirectContactDeviceBindingState.revoked,
    decidedAt: decidedAt,
    initializesRoster: true,
    event: 'DIRECT_LINKED_DEVICE_REVOKED',
  );
}

/// Revokes the contact's DYNAMIC legacy account target.
///
/// This is a separate exact transaction from the binding decisions because the
/// legacy target is not a binding row: its peer and ML-KEM key live in
/// `contacts` and change under ordinary key rotation. Fabricating a legacy
/// binding row just to reuse the CAS above would freeze a value that is
/// legitimately mutable.
///
/// Requires the caller's expected account signing key AND the exact current
/// legacy peer/ML-KEM pair, so a revoke authored against a stale profile view
/// cannot cut off a target the user never actually saw. This is what makes
/// "initialized + all revoked" reachable without inventing a binding.
Future<bool> dbRevokeDirectContactLegacyTarget(
  Database db, {
  required String contactAccountPeerId,
  required String expectedAccountSigningPublicKey,
  required String expectedLegacyPeerId,
  required String expectedLegacyMlKemPublicKey,
  required String decidedAt,
}) async {
  if (_isBlank(contactAccountPeerId) ||
      _isBlank(expectedAccountSigningPublicKey) ||
      _isBlank(expectedLegacyPeerId) ||
      _isBlank(expectedLegacyMlKemPublicKey) ||
      _isBlank(decidedAt)) {
    return false;
  }

  final normalizedContact = contactAccountPeerId.trim();
  final normalizedExpectedKey = expectedAccountSigningPublicKey.trim();
  final normalizedLegacyPeer = expectedLegacyPeerId.trim();
  final normalizedLegacyMlKem = expectedLegacyMlKemPublicKey.trim();
  final normalizedDecidedAt = decidedAt.trim();

  try {
    return await dbWriteTransaction<bool>(db, (txn) async {
      final rows = await txn.query(
        'contacts',
        columns: const <String>['peer_id', 'public_key', 'ml_kem_public_key'],
        where: 'peer_id = ?',
        whereArgs: <Object?>[normalizedContact],
        limit: 1,
      );
      if (rows.isEmpty) {
        return false;
      }
      final row = rows.first;
      if (row['public_key'] != normalizedExpectedKey ||
          row['peer_id'] != normalizedLegacyPeer ||
          row['ml_kem_public_key'] != normalizedLegacyMlKem) {
        return false;
      }

      final existing = await txn.query(
        'direct_contact_device_roster_metadata',
        where: 'contact_account_peer_id = ?',
        whereArgs: <Object?>[normalizedContact],
        limit: 1,
      );
      if (existing.isEmpty) {
        // The legacy target may only be revoked as part of an initialized
        // roster; otherwise the contact would have no reachable target and no
        // recorded decision explaining why.
        await txn
            .insert('direct_contact_device_roster_metadata', <String, Object?>{
              'contact_account_peer_id': normalizedContact,
              'roster_initialized': 1,
              'legacy_target_state': 'revoked',
              'initialized_at': normalizedDecidedAt,
              'legacy_revoked_at': normalizedDecidedAt,
              'updated_at': normalizedDecidedAt,
            });
      } else {
        if (existing.first['legacy_target_state'] == 'revoked') {
          // Idempotent: already revoked.
          return true;
        }
        await txn.update(
          'direct_contact_device_roster_metadata',
          <String, Object?>{
            'roster_initialized': 1,
            'legacy_target_state': 'revoked',
            'initialized_at':
                existing.first['initialized_at'] ?? normalizedDecidedAt,
            'legacy_revoked_at': normalizedDecidedAt,
            'updated_at': normalizedDecidedAt,
          },
          where: 'contact_account_peer_id = ?',
          whereArgs: <Object?>[normalizedContact],
        );
      }

      emitFlowEvent(
        layer: 'DB',
        event: 'DIRECT_LINKED_DEVICE_LEGACY_TARGET_REVOKED',
        details: const {},
      );
      return true;
    });
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_LEGACY_TARGET_REVOKE_ERROR',
      details: {'error': error.toString()},
    );
    return false;
  }
}

/// Loads the full roster snapshot for one contact.
Future<DirectContactDeviceRoster> dbLoadDirectContactDeviceRoster(
  DatabaseExecutor db,
  String contactAccountPeerId,
) async {
  final normalizedContact = contactAccountPeerId.trim();
  final metadataRows = await db.query(
    'direct_contact_device_roster_metadata',
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[normalizedContact],
    limit: 1,
  );
  final bindingRows = await db.query(
    'direct_contact_device_bindings',
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[normalizedContact],
    orderBy: 'device_id ASC',
  );
  return DirectContactDeviceRoster(
    metadata: metadataRows.isEmpty
        ? DirectContactDeviceRosterMetadata.uninitialized(normalizedContact)
        : DirectContactDeviceRosterMetadata.fromRow(metadataRows.first),
    bindings: bindingRows.map(DirectContactDeviceBinding.fromRow).toList(),
  );
}

/// Resolves every currently authorized addressing target for one contact.
///
/// Resolution rules, in order:
///
/// * NOT initialized — the roster does not exist for this contact yet, so the
///   answer is exactly the unchanged legacy `ContactModel` target. Plan 360
///   changes no delivery behavior for a contact nobody has reviewed.
/// * Missing legacy ML-KEM key — that leg is NONDELIVERABLE and is dropped. A
///   peer with no key to encrypt to is not a target.
/// * Initialized — the dynamic legacy target is included only while it is
///   still authorized, PLUS every ACTIVE linked binding whose recorded
///   verified account key still equals the contact's current account key.
/// * Initialized with the legacy target revoked and no active bindings —
///   returns ZERO targets. The legacy fallback is never resurrected; a contact
///   the user deliberately cut off must not become reachable again because
///   their last device was revoked.
Future<List<DirectContactDeviceTarget>> dbResolveDirectContactDeviceTargets(
  DatabaseExecutor db, {
  required String contactAccountPeerId,
  required String? legacyMlKemPublicKey,
}) async {
  final normalizedContact = contactAccountPeerId.trim();
  final roster = await dbLoadDirectContactDeviceRoster(db, normalizedContact);

  final legacyTarget = _isBlank(legacyMlKemPublicKey)
      ? null
      : DirectContactDeviceTarget(
          peerId: normalizedContact,
          mlKemPublicKey: legacyMlKemPublicKey!.trim(),
          isLegacyAccountTarget: true,
        );

  if (!roster.metadata.rosterInitialized) {
    return <DirectContactDeviceTarget>[?legacyTarget];
  }

  final currentAccountKey = await _currentContactAccountKey(
    db,
    normalizedContact,
  );

  return <DirectContactDeviceTarget>[
    if (legacyTarget != null && !roster.metadata.legacyTargetRevoked)
      legacyTarget,
    for (final binding in roster.activeBindings)
      if (currentAccountKey != null &&
          binding.verifiedAccountSigningPublicKey == currentAccountKey)
        DirectContactDeviceTarget(
          peerId: binding.transportPeerId,
          mlKemPublicKey: binding.deviceMlKemPublicKey,
          isLegacyAccountTarget: false,
          deviceId: binding.deviceId,
        ),
  ];
}

/// Builds the persisted-contact forward fanout snapshot for one contact
/// (Plan 361).
///
/// Authority comes ONLY from the database: the persisted nonblocked contact
/// row supplies the account signing key and the dynamic legacy ML-KEM key, and
/// the v112 roster supplies the linked bindings. A caller-provided legacy
/// value is never accepted. Returns null — and the whole fanout stage fails
/// closed all-zero — when the contact is missing, blocked, or has no current
/// account signing key.
///
/// Target order is deterministic: the dynamic legacy target first while it is
/// authorized and deliverable, then every ACTIVE binding whose recorded
/// verified account key still equals the contact's current key, in stable
/// `device_id` order. The first target is the representative witness.
Future<DirectContactFanoutSnapshot?> dbReadDirectContactFanoutSnapshot(
  DatabaseExecutor db, {
  required String contactAccountPeerId,
}) async {
  final normalizedContact = contactAccountPeerId.trim();
  if (normalizedContact.isEmpty) return null;

  final contactRows = await db.query(
    'contacts',
    columns: const <String>[
      'peer_id',
      'public_key',
      'ml_kem_public_key',
      'is_blocked',
    ],
    where: 'peer_id = ?',
    whereArgs: <Object?>[normalizedContact],
    limit: 1,
  );
  if (contactRows.isEmpty) return null;
  final contact = contactRows.single;
  final accountKey = contact['public_key'];
  if (accountKey is! String || accountKey.trim().isEmpty) return null;
  final blocked = contact['is_blocked'];
  if (blocked is int ? blocked != 0 : blocked == true) return null;

  final roster = await dbLoadDirectContactDeviceRoster(db, normalizedContact);
  final legacyMlKem = contact['ml_kem_public_key'];
  final legacyDeliverable =
      legacyMlKem is String && legacyMlKem.trim().isNotEmpty;
  final legacyAuthorized =
      !roster.metadata.rosterInitialized ||
      !roster.metadata.legacyTargetRevoked;

  final targets = <DirectContactFanoutTargetFact>[
    if (legacyDeliverable && legacyAuthorized)
      DirectContactFanoutTargetFact(
        peerId: normalizedContact,
        mlKemPublicKey: legacyMlKem.trim(),
        isLegacyAccountTarget: true,
        fingerprint: computeDirectContactLegacyTargetFingerprint(
          contactAccountPeerId: normalizedContact,
          accountSigningPublicKey: accountKey,
          legacyMlKemPublicKey: legacyMlKem.trim(),
        ),
      ),
    if (roster.metadata.rosterInitialized)
      for (final binding in roster.activeBindings)
        if (binding.verifiedAccountSigningPublicKey == accountKey)
          DirectContactFanoutTargetFact(
            peerId: binding.transportPeerId,
            mlKemPublicKey: binding.deviceMlKemPublicKey,
            isLegacyAccountTarget: false,
            fingerprint: binding.bindingFingerprint,
            deviceId: binding.deviceId,
            transportPublicKey: binding.transportPublicKey,
          ),
  ];

  return DirectContactFanoutSnapshot(
    contactAccountPeerId: normalizedContact,
    contactAccountSigningPublicKey: accountKey,
    rosterInitialized: roster.metadata.rosterInitialized,
    targets: targets,
  );
}

/// How one authenticated transport peer maps to logical contact authority.
enum DirectTransportAuthorityKind {
  /// The transport IS the contact's own dynamic account target.
  legacy,

  /// The transport is one ACTIVE, key-current linked device of the contact.
  linked,
}

/// The exact reverse resolution from one authenticated physical transport to
/// AT MOST one current logical contact/account (Plan 361).
class DirectTransportAuthorityResolution {
  const DirectTransportAuthorityResolution.authorized({
    required DirectTransportAuthorityKind this.kind,
    required String this.contactAccountPeerId,
    required this.contactIsBlocked,
  }) : refusalReason = null;

  const DirectTransportAuthorityResolution.refused(this.refusalReason)
    : kind = null,
      contactAccountPeerId = null,
      contactIsBlocked = false;

  final DirectTransportAuthorityKind? kind;
  final String? contactAccountPeerId;

  /// Blocked state of the LOGICAL contact so per-kind incumbent blocked
  /// policy can be applied before decrypt. A blocked contact's LINKED
  /// transports refuse outright — blocking is exactly the signal that no new
  /// linked authority is wanted.
  final bool contactIsBlocked;
  final String? refusalReason;

  bool get authorized => kind != null;
}

/// Resolves one authenticated transport peer to exactly one current logical
/// contact, or refuses.
///
/// Refusals: unknown transport, pending/rejected/revoked binding, roster not
/// initialized for a linked claim, verified-key drift from the contact's
/// CURRENT account key, contact removed, blocked contact behind a linked
/// transport, a revoked legacy target, and a transport claimed simultaneously
/// by legacy AND linked authority (ambiguous).
///
/// Receive/receipt apply MUST re-run this inside its own SQL transaction so
/// revoke-first has zero durable effect and apply-first commits exactly once.
Future<DirectTransportAuthorityResolution>
dbResolveDirectTransportToLogicalContact(
  DatabaseExecutor db, {
  required String transportPeerId,
}) async {
  final normalizedTransport = transportPeerId.trim();
  if (normalizedTransport.isEmpty) {
    return const DirectTransportAuthorityResolution.refused('blank_transport');
  }

  final legacyRows = await db.query(
    'contacts',
    columns: const <String>['peer_id', 'public_key', 'is_blocked'],
    where: 'peer_id = ?',
    whereArgs: <Object?>[normalizedTransport],
    limit: 1,
  );
  final bindingRows = await db.query(
    'direct_contact_device_bindings',
    where: 'transport_peer_id = ?',
    whereArgs: <Object?>[normalizedTransport],
    limit: 2,
  );

  if (legacyRows.isNotEmpty && bindingRows.isNotEmpty) {
    return const DirectTransportAuthorityResolution.refused(
      'ambiguous_transport',
    );
  }

  if (legacyRows.isNotEmpty) {
    final contact = legacyRows.single;
    final accountKey = contact['public_key'];
    if (accountKey is! String || accountKey.trim().isEmpty) {
      return const DirectTransportAuthorityResolution.refused(
        'missing_account_key',
      );
    }
    final metadataRows = await db.query(
      'direct_contact_device_roster_metadata',
      where: 'contact_account_peer_id = ?',
      whereArgs: <Object?>[normalizedTransport],
      limit: 1,
    );
    if (metadataRows.isNotEmpty &&
        metadataRows.single['legacy_target_state'] == 'revoked') {
      return const DirectTransportAuthorityResolution.refused(
        'legacy_target_revoked',
      );
    }
    final blocked = contact['is_blocked'];
    return DirectTransportAuthorityResolution.authorized(
      kind: DirectTransportAuthorityKind.legacy,
      contactAccountPeerId: normalizedTransport,
      contactIsBlocked: blocked is int ? blocked != 0 : blocked == true,
    );
  }

  if (bindingRows.isEmpty) {
    return const DirectTransportAuthorityResolution.refused(
      'unknown_transport',
    );
  }
  if (bindingRows.length > 1) {
    return const DirectTransportAuthorityResolution.refused(
      'ambiguous_transport',
    );
  }
  final binding = DirectContactDeviceBinding.fromRow(bindingRows.single);
  if (binding.state != DirectContactDeviceBindingState.active) {
    return DirectTransportAuthorityResolution.refused(
      'binding_${binding.state.name}',
    );
  }
  final authority = await _currentContactAuthority(
    db,
    binding.contactAccountPeerId,
  );
  if (authority == null) {
    return const DirectTransportAuthorityResolution.refused('removed_contact');
  }
  if (authority.accountSigningPublicKey !=
      binding.verifiedAccountSigningPublicKey) {
    return const DirectTransportAuthorityResolution.refused(
      'contact_account_key_drift',
    );
  }
  final roster = await dbLoadDirectContactDeviceRoster(
    db,
    binding.contactAccountPeerId,
  );
  if (!roster.metadata.rosterInitialized) {
    return const DirectTransportAuthorityResolution.refused(
      'roster_not_initialized',
    );
  }
  if (authority.isBlocked) {
    return const DirectTransportAuthorityResolution.refused('blocked_contact');
  }
  return DirectTransportAuthorityResolution.authorized(
    kind: DirectTransportAuthorityKind.linked,
    contactAccountPeerId: binding.contactAccountPeerId,
    contactIsBlocked: false,
  );
}

/// Deletes one contact's roster metadata and bindings.
///
/// Called ONLY from inside the exact contact-deletion transaction. There is
/// deliberately no FK cascade: ordinary contact upsert uses SQLite REPLACE
/// semantics, so a cascade would destroy explicitly-verified device authority
/// on every routine key re-announce.
Future<void> dbDeleteDirectContactDeviceRoster(
  DatabaseExecutor txn,
  String contactAccountPeerId,
) async {
  final normalizedContact = contactAccountPeerId.trim();
  await txn.delete(
    'direct_contact_device_bindings',
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[normalizedContact],
  );
  await txn.delete(
    'direct_contact_device_roster_metadata',
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[normalizedContact],
  );
}
