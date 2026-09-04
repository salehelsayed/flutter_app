import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class CallTrustedRosterSnapshot {
  CallTrustedRosterSnapshot({
    required this.contactAccountPeerId,
    required this.contactAccepted,
    required this.contactBlocked,
    required List<TrustedCallDeviceAuthority> devices,
  }) : devices = List<TrustedCallDeviceAuthority>.unmodifiable(devices);

  final String contactAccountPeerId;
  final bool contactAccepted;
  final bool contactBlocked;
  final List<TrustedCallDeviceAuthority> devices;

  @override
  String toString() =>
      'CallTrustedRosterSnapshot(accepted: $contactAccepted, '
      'blocked: $contactBlocked, devices: ${devices.length})';
}

abstract interface class CallTrustedRosterProvider {
  Future<CallTrustedRosterSnapshot> loadForContact(String contactAccountPeerId);

  /// Reverse-resolves an authenticated transport to one current device
  /// authority. Unknown, blocked, inactive, revoked, or ambiguous transports
  /// return null without exposing the underlying authority value.
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String authenticatedTransportPeerId,
  );
}

/// A stable epoch derived from all immutable authenticated device binding
/// material. Rotating any device key produces a different endpoint epoch.
int callDeviceKeyEpochFromFingerprint(String fingerprint) {
  final bytes = sha256.convert(utf8.encode(fingerprint)).bytes;
  // Keep all 53 integer bits that survive a JSON number round trip. This is
  // an equality witness, never an ordering counter; preferenceEpoch remains
  // the sole ordered endpoint field.
  var epoch = bytes[0] & 0x1f;
  for (var index = 1; index < 7; index++) {
    epoch = (epoch << 8) | bytes[index];
  }
  return epoch;
}

/// Production authority adapter over the accepted-contact table and the
/// current direct-device roster. Relay endpoint records are deliberately not
/// consulted here.
final class DatabaseCallTrustedRosterProvider
    implements CallTrustedRosterProvider {
  const DatabaseCallTrustedRosterProvider(this._database);

  final DatabaseExecutor _database;

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(
    String contactAccountPeerId,
  ) async {
    final normalizedAccount = contactAccountPeerId.trim();
    if (normalizedAccount.isEmpty) {
      return CallTrustedRosterSnapshot(
        contactAccountPeerId: '',
        contactAccepted: false,
        contactBlocked: false,
        devices: const <TrustedCallDeviceAuthority>[],
      );
    }

    final contactRows = await _database.query(
      'contacts',
      columns: const <String>['peer_id', 'is_blocked'],
      where: 'peer_id = ?',
      whereArgs: <Object?>[normalizedAccount],
      limit: 1,
    );
    if (contactRows.isEmpty) {
      return CallTrustedRosterSnapshot(
        contactAccountPeerId: normalizedAccount,
        contactAccepted: false,
        contactBlocked: false,
        devices: const <TrustedCallDeviceAuthority>[],
      );
    }
    final blockedValue = contactRows.single['is_blocked'];
    final blocked = blockedValue is int
        ? blockedValue != 0
        : blockedValue == true;
    if (blocked) {
      return CallTrustedRosterSnapshot(
        contactAccountPeerId: normalizedAccount,
        contactAccepted: true,
        contactBlocked: true,
        devices: const <TrustedCallDeviceAuthority>[],
      );
    }

    final snapshot = await dbReadDirectContactFanoutSnapshot(
      _database,
      contactAccountPeerId: normalizedAccount,
    );
    if (snapshot == null) {
      return CallTrustedRosterSnapshot(
        contactAccountPeerId: normalizedAccount,
        contactAccepted: true,
        contactBlocked: false,
        devices: const <TrustedCallDeviceAuthority>[],
      );
    }

    final devices = <TrustedCallDeviceAuthority>[];
    final seenTransportPeers = <String>{};
    for (final target in snapshot.targets) {
      final signingPublicKey =
          target.transportPublicKey ?? snapshot.contactAccountSigningPublicKey;
      if (!seenTransportPeers.add(target.peerId) ||
          target.peerId.trim().isEmpty ||
          target.mlKemPublicKey.trim().isEmpty ||
          signingPublicKey.trim().isEmpty) {
        continue;
      }
      devices.add(
        TrustedCallDeviceAuthority(
          accountPeerId: snapshot.contactAccountPeerId,
          devicePeerId: target.peerId,
          linked: true,
          deviceKeyEpoch: callDeviceKeyEpochFromFingerprint(target.fingerprint),
          signingPublicKey: signingPublicKey,
          mlKemPublicKey: target.mlKemPublicKey,
        ),
      );
    }
    return CallTrustedRosterSnapshot(
      contactAccountPeerId: normalizedAccount,
      contactAccepted: true,
      contactBlocked: false,
      devices: devices,
    );
  }

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String authenticatedTransportPeerId,
  ) async {
    final normalizedTransport = authenticatedTransportPeerId.trim();
    if (normalizedTransport.isEmpty) return null;
    final resolution = await dbResolveDirectTransportToLogicalContact(
      _database,
      transportPeerId: normalizedTransport,
    );
    final accountPeerId = resolution.contactAccountPeerId;
    if (!resolution.authorized ||
        resolution.contactIsBlocked ||
        accountPeerId == null) {
      return null;
    }
    final roster = await loadForContact(accountPeerId);
    if (!roster.contactAccepted || roster.contactBlocked) return null;
    final matches = roster.devices
        .where((device) => device.devicePeerId == normalizedTransport)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }
}
