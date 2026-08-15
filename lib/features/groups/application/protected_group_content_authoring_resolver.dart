import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

typedef GroupContentAuthoringIdentity = ({String peerId, String publicKey});

typedef LoadGroupContentAuthoringIdentity =
    Future<GroupContentAuthoringIdentity?> Function();
typedef LoadGroupContentAuthoringMember =
    Future<GroupMember?> Function(String groupId, String peerId);
typedef LoadGroupContentInstallationAuthority =
    Future<LinkedInstallationAuthoritySnapshot> Function(
      String expectedAccountPeerId,
    );
typedef LoadLatestSettledGroupContentAuthority =
    Future<AuthenticatedGroupAuthorityProof?> Function(String groupId);
typedef ReadCurrentGroupContentTransportPeerId = String? Function();

/// Builds the single role/device/authority decision used by production group
/// content authoring and by device-level convergence proofs.
///
/// Every dependency is read on each invocation. The returned resolver does not
/// retain a group, member, transport, or authority snapshot across the keyed
/// phase owned by the send use cases.
ResolveGroupContentAuthoring buildProtectedGroupContentAuthoringResolver({
  required LoadGroupContentAuthoringIdentity loadIdentity,
  required LoadGroupContentAuthoringMember loadMember,
  required LoadGroupContentInstallationAuthority loadInstallationAuthority,
  required LoadLatestSettledGroupContentAuthority loadLatestSettledAuthority,
  required ReadCurrentGroupContentTransportPeerId readCurrentTransportPeerId,
  required AckOrExpiryInboxStore inboxStore,
  required DirectLinkedDeviceSelector directLinkedDeviceSelector,
  required bool multiDeviceSyncEnabled,
  void Function()? onResolved,
}) {
  return ({
    required String groupId,
    required String senderPeerId,
    required String senderPublicKey,
    String? senderDeviceId,
    String? senderTransportPeerId,
  }) async {
    onResolved?.call();
    final identity = await loadIdentity();
    if (identity == null ||
        identity.peerId != senderPeerId ||
        identity.publicKey != senderPublicKey) {
      return (kind: GroupContentAuthoringResolutionKind.refuse, context: null);
    }
    final member = await loadMember(groupId, senderPeerId);
    if (member == null) {
      return (kind: GroupContentAuthoringResolutionKind.refuse, context: null);
    }
    // Installation role owns the fallback decision. In particular, an active
    // linked secondary with a temporarily empty group-device projection may
    // never resurrect the account-keyed legacy transport.
    final installation = await loadInstallationAuthority(identity.peerId);
    if (installation.refusesStartup) {
      return (kind: GroupContentAuthoringResolutionKind.refuse, context: null);
    }
    if (member.devices.isEmpty) {
      if (!installation.isOrdinaryPrimary) {
        return (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        );
      }
      return (
        kind: GroupContentAuthoringResolutionKind.legacyUninitialized,
        context: null,
      );
    }
    final proof = await loadLatestSettledAuthority(groupId);
    if (proof == null) {
      return (kind: GroupContentAuthoringResolutionKind.refuse, context: null);
    }

    LinkedTransportCredential? linkedCredential;
    var requireLinkedCredential = false;
    String? authoringDeviceId;
    String? authoringTransportPeerId;
    String? authoringPublicKey;
    if (installation.isActiveLinkedSecondary) {
      linkedCredential = installation.credential;
      final device = member.findDeviceById(linkedCredential?.deviceId);
      if (linkedCredential == null ||
          device == null ||
          device.transportPeerId != linkedCredential.transportPeerId ||
          device.deviceSigningPublicKey !=
              linkedCredential.transportPublicKey) {
        return (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        );
      }
      requireLinkedCredential = true;
      authoringDeviceId = device.deviceId;
      authoringTransportPeerId = device.transportPeerId;
      authoringPublicKey = device.deviceSigningPublicKey;
    } else if (installation.isOrdinaryPrimary) {
      final runtimeTransportPeerId = readCurrentTransportPeerId()?.trim();
      if (runtimeTransportPeerId == null || runtimeTransportPeerId.isEmpty) {
        return (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        );
      }
      final binding = resolveGroupSenderDeviceBindingFromMember(
        member: member,
        preferredDeviceId: senderDeviceId,
        preferredTransportPeerId:
            senderTransportPeerId ?? runtimeTransportPeerId,
        senderPublicKey: senderPublicKey,
      );
      if (!binding.hasDevice ||
          binding.transportPeerId != runtimeTransportPeerId ||
          binding.devicePublicKey != senderPublicKey) {
        return (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        );
      }
      authoringDeviceId = binding.deviceId;
      authoringTransportPeerId = binding.transportPeerId;
      authoringPublicKey = binding.devicePublicKey;
    } else {
      return (kind: GroupContentAuthoringResolutionKind.refuse, context: null);
    }

    return (
      kind: GroupContentAuthoringResolutionKind.strict,
      context: GroupContentAuthoringContext(
        directLinkedDeviceSelector: directLinkedDeviceSelector,
        multiDeviceSyncEnabled: multiDeviceSyncEnabled,
        authorityVersion: GroupContentAuthorityVersion(
          eventAt: proof.eventAt,
          eventId: proof.eventId,
          keyEpoch: proof.keyEpoch,
        ),
        inboxStore: inboxStore,
        linkedTransportCredential: linkedCredential,
        requireLinkedTransportCredential: requireLinkedCredential,
        authoringDeviceId: authoringDeviceId,
        authoringTransportPeerId: authoringTransportPeerId,
        authoringPublicKey: authoringPublicKey,
      ),
    );
  };
}
