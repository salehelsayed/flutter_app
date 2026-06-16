import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_device_announce_marker.dart';
import 'package:flutter_app/features/groups/application/group_system_publish_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

/// Injection seam for [announceRestoredDeviceToGroups] (the receiver-facing
/// param surface; the real fn's extra optional params default).
typedef AnnounceRestoredDeviceToGroupsFn =
    Future<int> Function({
      required Bridge bridge,
      required GroupRepository groupRepo,
      required String selfPeerId,
      required String accountSigningPublicKey,
      required String accountSigningPrivateKey,
      required String selfUsername,
      required GroupMemberDeviceIdentity announcedDevice,
    });

/// B1b emit half (Part B of 12-P2): after a restore, announce this device's
/// fresh per-device identity to every group it belongs to, so a sibling/admin
/// can admit it ([admitSiblingDeviceIfTrusted]) and the existing distribution
/// runner re-distributes the current group key to it.
///
/// The announce is signed with the ACCOUNT key (the only key a freshly-restored
/// device shares with the roster — restore re-mints the ML-KEM key but the
/// ed25519 identity key comes from the mnemonic), so the receiver can
/// authenticate it without the new device being pre-rostered.
///
/// Flag-gated (default-OFF). Best-effort per group: one group's publish failure
/// never aborts the others. Returns the number of groups successfully announced.
Future<int> announceRestoredDeviceToGroups({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String selfPeerId,
  required String accountSigningPublicKey,
  required String accountSigningPrivateKey,
  required String selfUsername,
  required GroupMemberDeviceIdentity announcedDevice,
  DateTime Function()? nowUtc,
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
}) async {
  if (!multiDeviceSyncEnabled) {
    return 0;
  }
  final now = (nowUtc ?? () => DateTime.now().toUtc())().toUtc();
  final groups = await groupRepo.getAllGroups();
  var announced = 0;

  for (final group in groups) {
    if (group.isDissolved) {
      continue;
    }
    final sourceEventId =
        'device_announce:${group.id}:${announcedDevice.deviceId}:'
        '${now.toIso8601String()}';
    final systemPayload = <String, dynamic>{
      '__sys': 'device_announce',
      'eventAt': now.toIso8601String(),
      'sourceEventId': sourceEventId,
      'announcedDevice': {
        'deviceId': announcedDevice.deviceId,
        'transportPeerId': announcedDevice.transportPeerId,
        'deviceSigningPublicKey': announcedDevice.deviceSigningPublicKey,
        if (announcedDevice.mlKemPublicKey != null)
          'mlKemPublicKey': announcedDevice.mlKemPublicKey,
        if (announcedDevice.keyPackageId != null)
          'keyPackageId': announcedDevice.keyPackageId,
        if (announcedDevice.keyPackagePublicMaterial != null)
          'keyPackagePublicMaterial': announcedDevice.keyPackagePublicMaterial,
      },
    };

    try {
      final signed = await signGroupSystemTransitionPayload(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: group.id,
        transitionType: 'device_announce',
        sourceEventId: sourceEventId,
        eventAt: now,
        actorPeerId: selfPeerId,
        actorUsername: selfUsername,
        actorSigningPublicKey: accountSigningPublicKey,
        actorPrivateKey: accountSigningPrivateKey,
        actorDeviceId: announcedDevice.deviceId,
        actorTransportPeerId: announcedDevice.transportPeerId,
        actorKeyPackageId: announcedDevice.keyPackageId,
        systemPayload: systemPayload,
      );
      final encoded = jsonEncode(signed);
      await publishGroupSystemMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: group.id,
        text: encoded,
        senderPeerId: selfPeerId,
        senderPublicKey: accountSigningPublicKey,
        senderPrivateKey: accountSigningPrivateKey,
        messageId: sourceEventId,
        replayPlaintext: encoded,
        senderUsername: selfUsername,
        senderDeviceId: announcedDevice.deviceId,
        senderTransportPeerId: announcedDevice.transportPeerId,
        senderDevicePublicKey: announcedDevice.deviceSigningPublicKey,
        senderKeyPackageId: announcedDevice.keyPackageId,
      );
      announced++;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DEVICE_ANNOUNCE_PUBLISH_ERROR',
        details: {
          'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_DEVICE_ANNOUNCE_COMPLETE',
    details: {'announced': announced, 'groups': groups.length},
  );
  return announced;
}

/// R1 startup hook: if a freshly-restored device set the one-shot announce
/// marker, build its own per-device binding from local identity + the live
/// transport peer id and announce to its groups, then clear the marker.
///
/// Restore re-mints the ML-KEM key but the ed25519 identity key comes from the
/// mnemonic, so the announce is account-key-signed and the announced device
/// carries the NEW ML-KEM public key (the runner re-distributes the current
/// group key to it on admission).
///
/// Marker lifecycle (D4): cleared when the feature is OFF in this build (no
/// churn), when there is nothing to announce, or once at least one group was
/// announced to; RETAINED for a retry next startup on a transient all-groups
/// publish failure or when identity / transport peer id are not yet available.
/// Never throws — startup must not be blocked.
Future<void> maybeAnnounceRestoredDeviceOnStartup({
  required SecureKeyStore secureKeyStore,
  required Bridge bridge,
  required GroupRepository groupRepo,
  required IdentityModel? identity,
  required String? transportPeerId,
  AnnounceRestoredDeviceToGroupsFn announce = announceRestoredDeviceToGroups,
  bool multiDeviceSyncEnabled = kMultiDeviceSyncEnabled,
}) async {
  try {
    if (!await readGroupDeviceAnnounceMarker(secureKeyStore)) {
      return;
    }
    // Feature OFF in this build: drop the marker so it doesn't re-check every
    // startup. (The flag is compile-time, so it cannot flip within a build.)
    if (!multiDeviceSyncEnabled) {
      await clearGroupDeviceAnnounceMarker(secureKeyStore);
      return;
    }
    final peerId = transportPeerId?.trim();
    if (identity == null || peerId == null || peerId.isEmpty) {
      // Not ready (no identity / transport peer id yet) — retry next startup.
      return;
    }
    final announced = await announce(
      bridge: bridge,
      groupRepo: groupRepo,
      selfPeerId: peerId,
      accountSigningPublicKey: identity.publicKey,
      accountSigningPrivateKey: identity.privateKey,
      selfUsername: identity.username,
      announcedDevice: GroupMemberDeviceIdentity(
        deviceId: peerId,
        transportPeerId: peerId,
        deviceSigningPublicKey: identity.publicKey,
        mlKemPublicKey: identity.mlKemPublicKey,
      ),
    );
    final hasNonDissolvedGroup = (await groupRepo.getAllGroups()).any(
      (group) => !group.isDissolved,
    );
    if (announced > 0 || !hasNonDissolvedGroup) {
      await clearGroupDeviceAnnounceMarker(secureKeyStore);
    }
    // else: a transient all-groups publish failure — retain for retry.
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_DEVICE_ANNOUNCE_ON_STARTUP_ERROR',
      details: {'error': e.toString()},
    );
  }
}
