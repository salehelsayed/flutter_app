import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

typedef GroupMessageIdFactory = String Function();

/// Explicit activation authority for the Plan-364 strict content branch.
/// Existing callers that omit it stay on the byte-compatible legacy path.
class GroupContentAuthoringContext {
  const GroupContentAuthoringContext({
    required this.directLinkedDeviceSelector,
    required this.multiDeviceSyncEnabled,
    required this.authorityVersion,
    required this.inboxStore,
    this.linkedTransportCredential,
    this.requireLinkedTransportCredential = false,
    this.authoringDeviceId,
    this.authoringTransportPeerId,
    this.authoringPublicKey,
  });

  final DirectLinkedDeviceSelector directLinkedDeviceSelector;
  final bool multiDeviceSyncEnabled;
  final GroupContentAuthorityVersion? authorityVersion;
  final AckOrExpiryInboxStore? inboxStore;
  final LinkedTransportCredential? linkedTransportCredential;
  final bool requireLinkedTransportCredential;

  /// Exact runtime sender binding chosen by the production resolver. These
  /// fields travel together; explicit unit contexts may omit all three.
  final String? authoringDeviceId;
  final String? authoringTransportPeerId;
  final String? authoringPublicKey;
}

enum GroupContentAuthoringResolutionKind { legacyUninitialized, strict, refuse }

typedef GroupContentAuthoringResolution = ({
  GroupContentAuthoringResolutionKind kind,
  GroupContentAuthoringContext? context,
});

typedef ResolveGroupContentAuthoring =
    Future<GroupContentAuthoringResolution> Function({
      required String groupId,
      required String senderPeerId,
      required String senderPublicKey,
      String? senderDeviceId,
      String? senderTransportPeerId,
    });

final class StrictGroupContentAuthoringSnapshot {
  const StrictGroupContentAuthoringSnapshot({
    required this.group,
    required this.key,
    required this.members,
    required this.senderMember,
    required this.context,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.senderPublicKey,
    required this.recipientPeerIds,
  });

  final GroupModel group;
  final GroupKeyInfo key;
  final List<GroupMember> members;
  final GroupMember senderMember;
  final GroupContentAuthoringContext context;
  final String senderDeviceId;
  final String senderTransportPeerId;
  final String senderPublicKey;
  final List<String> recipientPeerIds;
}

typedef GroupContentAuthoringAdmission = ({
  GroupContentAuthoringResolutionKind kind,
  StrictGroupContentAuthoringSnapshot? snapshot,
});

final Expando<ResolveGroupContentAuthoring> _groupContentAuthoringResolvers =
    Expando<ResolveGroupContentAuthoring>('group_content_authoring_resolver');

/// Installs the production authoring decision at the use-case choke point.
///
/// A nullable context is deliberately not the contract: once a member has a
/// device roster, failure to resolve strict authority must refuse instead of
/// silently falling through to the legacy pubsub lane.
void setGroupContentAuthoringResolver(
  GroupRepository owner,
  ResolveGroupContentAuthoring? resolver,
) {
  _groupContentAuthoringResolvers[owner] = resolver;
}

/// True only for incumbent/test compositions that have no production
/// authoring resolver and did not explicitly select the strict unit seam.
///
/// Message and reaction entry/recheck paths share this predicate so an
/// initialized production resolver can never return legacy without being
/// rejected, while pre-364 resolver-less owners retain their behavior.
bool isResolverAbsentLegacyGroupContentAuthoring({
  required GroupRepository owner,
  required GroupContentAuthoringContext? explicitContext,
}) => _groupContentAuthoringResolvers[owner] == null && explicitContext == null;

Future<GroupContentAuthoringResolution> resolveGroupContentAuthoring({
  required GroupRepository resolverOwner,
  required String groupId,
  required String senderPeerId,
  required String senderPublicKey,
  required GroupMember senderMember,
  String? senderDeviceId,
  String? senderTransportPeerId,
  GroupContentAuthoringContext? explicitContext,
}) async {
  final resolver = _groupContentAuthoringResolvers[resolverOwner];
  // Production always gets the first decision, including for an empty member
  // device roster. An active linked installation may temporarily observe that
  // shape while its group projection catches up; it must refuse rather than
  // fall through to the ordinary-primary legacy transport.
  if (resolver != null) {
    final resolution = await resolver(
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
    );
    if (resolution.kind == GroupContentAuthoringResolutionKind.strict &&
        resolution.context != null) {
      return resolution;
    }
    if (resolution.kind ==
            GroupContentAuthoringResolutionKind.legacyUninitialized &&
        resolution.context == null) {
      return resolution;
    }
    return (kind: GroupContentAuthoringResolutionKind.refuse, context: null);
  }
  // Resolver absence is the incumbent/test composition seam. Production
  // installs its resolver before exposing any group authoring surface, so an
  // initialized production roster still reaches the fail-closed decision
  // above. Keeping the resolver-less owner legacy preserves pre-364 callers
  // that have no installation-authority composition at all.
  if (explicitContext == null) {
    return (
      kind: GroupContentAuthoringResolutionKind.legacyUninitialized,
      context: null,
    );
  }
  if (senderMember.devices.isEmpty) {
    return (
      kind: GroupContentAuthoringResolutionKind.legacyUninitialized,
      context: null,
    );
  }
  // An explicit context remains a unit seam only. A production owner has a
  // resolver installed above, so caller-carried context can never bypass the
  // current installation-role decision.
  return (
    kind: GroupContentAuthoringResolutionKind.strict,
    context: explicitContext,
  );
}

Future<GroupContentAuthoringResolution?> _classifyGroupContentAuthoringEntry({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  required String senderPublicKey,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  required DateTime? timestamp,
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required GroupContentAuthoringContext? explicitContext,
}) async {
  final group = await groupRepo.getGroup(groupId);
  if (group == null || group.selfRemovedAt != null || group.isDissolved) {
    return null;
  }
  final membershipCutoff =
      timestamp != null && !timestamp.toUtc().isBefore(group.createdAt.toUtc())
      ? timestamp
      : null;
  final membership = await _loadGroupSendMembership(
    groupRepo: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    membershipCutoff: membershipCutoff,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
  );
  GroupMember? sender;
  for (final candidate in membership.members) {
    if (candidate.peerId == senderPeerId) sender = candidate;
  }
  if (sender == null) return null;
  return resolveGroupContentAuthoring(
    resolverOwner: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderMember: sender,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    explicitContext: explicitContext,
  );
}

/// Revalidates a persisted strict-content authority and frozen physical ACL.
/// Callers must invoke this inside [runGroupAuthorityPhase].
Future<bool> strictGroupContentAuthorityMatchesAssumingPhase({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  required String senderAccountPublicKey,
  required String expectedSenderPublicKey,
  required String senderDeviceId,
  required String senderTransportPeerId,
  required List<String> expectedRecipientPeerIds,
  required GroupContentAuthorityVersion expectedAuthority,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) async {
  final group = await groupRepo.getGroup(groupId);
  final key = await groupRepo.getLatestKey(groupId);
  final membership = await _loadGroupSendMembership(
    groupRepo: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
  );
  GroupMember? sender;
  for (final member in membership.members) {
    if (member.peerId == senderPeerId) sender = member;
  }
  if (group == null ||
      group.selfRemovedAt != null ||
      group.isDissolved ||
      sender == null ||
      (group.type == GroupType.announcement &&
          (group.myRole != GroupRole.admin ||
              sender.role != MemberRole.admin)) ||
      key?.keyGeneration != expectedAuthority.keyEpoch) {
    return false;
  }
  final resolution = await resolveGroupContentAuthoring(
    resolverOwner: groupRepo,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderPublicKey: senderAccountPublicKey,
    senderMember: sender,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
  );
  final context = resolution.context;
  return resolution.kind == GroupContentAuthoringResolutionKind.strict &&
      context != null &&
      sameGroupContentAuthorityVersion(
        expectedAuthority,
        context.authorityVersion,
      ) &&
      _sameStrictPhysicalAuthority(
        after: membership.members,
        eligibleLogicalPeerIds: membership.recipientPeerIds,
        senderPeerId: senderPeerId,
        senderTransportPeerId: senderTransportPeerId,
        expectedRecipients: expectedRecipientPeerIds,
        senderDeviceId: senderDeviceId,
        senderPublicKey: expectedSenderPublicKey,
      );
}

/// Final read-only authority check run inside the same per-group membership
/// phase as message persistence and native delivery.
///
/// Callers that perform an external precursor (for example, a media upload)
/// can bind dispatch to the exact authority used by that precursor without
/// trying to nest another membership lock around [sendGroupMessage].
typedef CurrentGroupSendAuthorityCheck = Future<bool> Function();

String _diagnosticPrefix(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

GroupMessage _withPrivateMediaCustodyAnchor(
  GroupMessage message, {
  required bool hasCustody,
  required int anchoredAt,
}) {
  final policy = message.privateMediaPolicy;
  if (!hasCustody || !policy.isPrivate || message.mediaReceivedAt != null) {
    return message;
  }
  final expiresAt = policy.lifecycle == GroupMediaLifecycle.disappearing
      ? anchoredAt + (policy.durationSeconds! * 1000)
      : null;
  return message.copyWith(
    mediaReceivedAt: anchoredAt,
    mediaExpiresAt: expiresAt,
    mediaLastCheckedAt: expiresAt == null ? null : anchoredAt,
  );
}

void _signalPrivateMediaAnchor(GroupMessage before, GroupMessage after) {
  if (before.mediaExpiresAt == null && after.mediaExpiresAt != null) {
    signalGroupPrivateMediaExpiryChanged();
  }
}

/// Result of sending a group message.
enum SendGroupMessageResult {
  success,
  groupNotFound,
  groupDissolved,
  unauthorized,
  error,

  /// Publish succeeded but 0 peers were connected to the topic.
  /// The message was stored in the relay inbox as a fallback. This is live
  /// fanout evidence only, not recipient delivered/read receipt evidence.
  /// The returned [GroupMessage] still has status `'sent'` because the
  /// relay inbox accepted custody for offline delivery.
  successNoPeers,

  /// 210b: publish "succeeded" locally with ZERO live topic peers AND the
  /// relay-inbox custody attempt failed — the realistic offline-device
  /// geometry (gossipsub reports no error with an empty mesh; only the relay
  /// connect fails). Nothing left the device in any meaningful sense. The
  /// returned [GroupMessage] has the durable status `'queued_offline'`
  /// (clock, offline snackbar) and keeps its `inboxRetryPayload`, so the
  /// repush lane re-stores custody on reconnect and settles it to `'sent'`.
  /// Distinct from [successNoPeers] (custody WAS accepted → tick) and from
  /// the in-doubt `'pending'` (live peers may have received the publish).
  queuedOffline,
}

Future<({List<GroupMember> members, List<String> recipientPeerIds})>
_loadGroupSendMembership({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  DateTime? membershipCutoff,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
}) async {
  final inviteStatuses = inviteDeliveryAttemptRepo == null
      ? const <String, GroupInviteDeliveryStatus>{}
      : await inviteDeliveryAttemptRepo.getStatusesForGroupMembers(groupId);
  // Keep the live roster read last. Private-media callers use this helper as
  // their final async authority snapshot; reading members before the invite
  // await would let a demotion race through with a stale writer/admin role.
  final members = await groupRepo.getMembers(groupId);
  final normalizedCutoff = membershipCutoff?.toUtc();
  final normalizedSenderPeerId = senderPeerId.trim();
  final recipientPeerIds = members
      .where((member) {
        final peerId = member.peerId.trim();
        return (normalizedCutoff == null ||
                !member.joinedAt.toUtc().isAfter(normalizedCutoff)) &&
            hasDeliverableGroupMemberIdentity(member) &&
            peerId != normalizedSenderPeerId &&
            !isPersistedNonJoinedGroupInviteStatus(inviteStatuses[peerId]);
      })
      .map((member) => member.peerId.trim())
      .toSet()
      .toList();
  return (members: members, recipientPeerIds: recipientPeerIds);
}

List<String> _durableGroupRecipientPeerIds({
  required List<String> remoteRecipientPeerIds,
  required String senderPeerId,
  bool includeSenderPeerId = false,
}) {
  final recipients = <String>[];
  final seen = <String>{};
  void addRecipient(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty || seen.contains(normalized)) return;
    seen.add(normalized);
    recipients.add(normalized);
  }

  for (final peerId in remoteRecipientPeerIds) {
    addRecipient(peerId);
  }

  if (includeSenderPeerId) {
    addRecipient(senderPeerId);
  }

  return recipients;
}

List<String> _strictPhysicalGroupRecipientPeerIds({
  required List<GroupMember> members,
  required Iterable<String> eligibleLogicalPeerIds,
  required String senderPeerId,
  required String senderTransportPeerId,
}) {
  final eligible = <String>{...eligibleLogicalPeerIds, senderPeerId};
  final transportClaims = <String, int>{};
  for (final member in members) {
    if (!eligible.contains(member.peerId)) continue;
    for (final device in member.activeDevicesWithLegacyFallback()) {
      final transport = device.transportPeerId.trim();
      if (transport.isNotEmpty && transport != senderTransportPeerId) {
        transportClaims.update(
          transport,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }
  return transportClaims.entries
      .where((entry) => entry.value == 1)
      .map((entry) => entry.key)
      .toList()
    ..sort();
}

bool hasUniqueStrictGroupContentAuthorBinding({
  required List<GroupMember> members,
  required String senderPeerId,
  required String senderDeviceId,
  required String senderTransportPeerId,
  required String senderPublicKey,
}) {
  GroupMember? sender;
  for (final member in members) {
    if (member.peerId == senderPeerId) sender = member;
  }
  final exactClaims = sender?.activeDevices
      .where(
        (candidate) =>
            candidate.deviceId == senderDeviceId &&
            candidate.transportPeerId == senderTransportPeerId &&
            candidate.deviceSigningPublicKey == senderPublicKey,
      )
      .length;
  final transportClaims = members
      .expand((member) => member.activeDevicesWithLegacyFallback())
      .where((candidate) => candidate.transportPeerId == senderTransportPeerId)
      .length;
  return exactClaims == 1 && transportClaims == 1;
}

bool _sameStrictPhysicalAuthority({
  required List<GroupMember> after,
  required Iterable<String> eligibleLogicalPeerIds,
  required String senderPeerId,
  required String senderTransportPeerId,
  required List<String> expectedRecipients,
  required String senderDeviceId,
  required String senderPublicKey,
}) {
  final currentRecipients = _strictPhysicalGroupRecipientPeerIds(
    members: after,
    eligibleLogicalPeerIds: eligibleLogicalPeerIds,
    senderPeerId: senderPeerId,
    senderTransportPeerId: senderTransportPeerId,
  );
  if (!sameGroupPrivateMediaRecipientPeerIds(
    expectedRecipients,
    currentRecipients,
  )) {
    return false;
  }
  return hasUniqueStrictGroupContentAuthorBinding(
    members: after,
    senderPeerId: senderPeerId,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderPublicKey: senderPublicKey,
  );
}

bool sameGroupContentAuthorityVersion(
  GroupContentAuthorityVersion? left,
  GroupContentAuthorityVersion? right,
) =>
    left != null &&
    right != null &&
    left.eventAt.toUtc() == right.eventAt.toUtc() &&
    left.eventId == right.eventId &&
    left.keyEpoch == right.keyEpoch;

bool _sameLinkedTransportCredential(
  LinkedTransportCredential? left,
  LinkedTransportCredential? right,
) =>
    (left == null && right == null) ||
    (left != null &&
        right != null &&
        left.state == right.state &&
        left.accountPeerId == right.accountPeerId &&
        left.accountPublicKey == right.accountPublicKey &&
        left.deviceId == right.deviceId &&
        left.transportPeerId == right.transportPeerId &&
        left.transportPublicKey == right.transportPublicKey &&
        left.transportPrivateKey == right.transportPrivateKey);

bool sameGroupContentAuthoringContext(
  GroupContentAuthoringContext expected,
  GroupContentAuthoringContext current,
) =>
    expected.directLinkedDeviceSelector.allowsLinkedDeviceAuthoring ==
        current.directLinkedDeviceSelector.allowsLinkedDeviceAuthoring &&
    expected.multiDeviceSyncEnabled == current.multiDeviceSyncEnabled &&
    expected.requireLinkedTransportCredential ==
        current.requireLinkedTransportCredential &&
    _sameOptionalString(
      expected.authoringDeviceId,
      current.authoringDeviceId,
    ) &&
    _sameOptionalString(
      expected.authoringTransportPeerId,
      current.authoringTransportPeerId,
    ) &&
    _sameOptionalString(
      expected.authoringPublicKey,
      current.authoringPublicKey,
    ) &&
    current.inboxStore != null &&
    sameGroupContentAuthorityVersion(
      expected.authorityVersion,
      current.authorityVersion,
    ) &&
    _sameLinkedTransportCredential(
      expected.linkedTransportCredential,
      current.linkedTransportCredential,
    );

const groupContentAuthoringFutureSkew = Duration(minutes: 5);

bool validGroupContentAuthoringOrder({
  required GroupContentAuthorityVersion authority,
  required DateTime contentAt,
  required String contentEventId,
  DateTime? nowUtc,
}) {
  final at = contentAt.toUtc();
  if (at.isAfter(
    (nowUtc ?? DateTime.now()).toUtc().add(groupContentAuthoringFutureSkew),
  )) {
    return false;
  }
  final authorityAt = authority.eventAt.toUtc();
  final time = authorityAt.compareTo(at);
  return time < 0 ||
      (time == 0 && authority.eventId.compareTo(contentEventId) <= 0);
}

/// Exact set equality for a private-media relay recipient snapshot.
///
/// Empty/duplicate entries fail closed so a malformed persisted re-drive list
/// cannot compare equal after lossy normalization.
bool sameGroupPrivateMediaRecipientPeerIds(
  Iterable<String> left,
  Iterable<String> right,
) {
  Set<String>? normalized(Iterable<String> values) {
    final source = values.toList(growable: false);
    final result = <String>{};
    for (final value in source) {
      final peerId = value.trim();
      if (peerId.isEmpty || !result.add(peerId)) return null;
    }
    return result;
  }

  final normalizedLeft = normalized(left);
  final normalizedRight = normalized(right);
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft.length == normalizedRight.length &&
      normalizedLeft.containsAll(normalizedRight);
}

/// Exclusion by affirmative local evidence only (plan 318): a roster member is
/// dropped from the recipient set iff THIS device holds a persisted invite row
/// in a non-joined state for them. The add-member flow writes rows at stage
/// time ([recordPendingGroupInviteFanoutAttempts]) and the create flow at
/// invite-send-result time, so a null status can only mean the member predates
/// this device's observation (an incumbent) or was staged by another device —
/// both are included. Inferring "pending invitee" from a MISSING row lost
/// messages (F7: a later-joined admin silently excluded incumbents from relay
/// custody, which is the retrieval ACL), and include-on-doubt is the tradeoff
/// already accepted for non-tracker joiners (REG-119b) and the reaction lane.
/// `unknown` is a persisted row in an indeterminate state
/// (resend_group_invite_use_case writes it) — affirmative evidence,
/// conservatively excluded. Creator and joiner inclusion (REG-119/REG-119b)
/// are structural now: no inference arm exists to except them from. Do NOT
/// re-introduce a null-status inference here.
bool isPersistedNonJoinedGroupInviteStatus(GroupInviteDeliveryStatus? status) {
  return status == GroupInviteDeliveryStatus.sent ||
      status == GroupInviteDeliveryStatus.queued ||
      status == GroupInviteDeliveryStatus.needsResend ||
      status == GroupInviteDeliveryStatus.cannotSend ||
      status == GroupInviteDeliveryStatus.unknown;
}

String _classifyGroupPublishLiveFanout({
  required int? topicPeers,
  required int expectedRecipientCount,
}) {
  if (topicPeers == null) return 'legacy_unknown';
  if (topicPeers <= 0) return 'zero_peers';
  if (topicPeers < expectedRecipientCount) return 'partial_peers';
  return 'full_peers';
}

Map<String, dynamic> _groupPublishFanoutEvidence({
  required int? topicPeers,
  required int expectedRecipientCount,
  required bool? inboxOk,
}) {
  final evidence = <String, dynamic>{
    'expectedRecipientCount': expectedRecipientCount,
    'liveFanoutState': _classifyGroupPublishLiveFanout(
      topicPeers: topicPeers,
      expectedRecipientCount: expectedRecipientCount,
    ),
    'inboxStored': inboxOk ?? false,
    'inboxPending': inboxOk == null,
    'recipientReceiptClaimed': false,
  };
  if (topicPeers != null) {
    evidence['topicPeers'] = topicPeers;
  }
  return evidence;
}

bool _hasReliableGroupSendContract(Map<String, dynamic>? result) {
  if (result == null || result['ok'] != true) return false;
  return result.containsKey('publishSucceeded') &&
      result.containsKey('inboxStored') &&
      result.containsKey('expectedRecipientCount') &&
      (result.containsKey('topicPeerCount') ||
          result.containsKey('topicPeers'));
}

bool _reliableGroupSendUnavailable(Map<String, dynamic>? result) {
  if (result == null) return false;
  if (result['ok'] == true) return !_hasReliableGroupSendContract(result);
  final code = result['errorCode']?.toString();
  return code == 'UNKNOWN_COMMAND' ||
      code == 'MISSING_PLUGIN' ||
      code == 'NOT_IMPLEMENTED' ||
      code == 'UNIMPLEMENTED';
}

bool _reliableGroupSendTimedOut(Map<String, dynamic> result) {
  return result['ok'] != true &&
      result['errorCode']?.toString() == 'BRIDGE_TIMEOUT';
}

bool _reliablePublishSucceededWithoutCustody({
  required bool reliableOk,
  required bool publishSucceeded,
  required bool inboxOk,
  required int? topicPeers,
  required int expectedRecipientCount,
}) {
  return reliableOk &&
      publishSucceeded &&
      !inboxOk &&
      expectedRecipientCount > 0 &&
      topicPeers != null &&
      topicPeers <= 0;
}

int? _intResultField(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

List<String> _stringListResultField(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

String? _nativeReliableInboxRetryPayload({
  required String groupId,
  required Map<String, dynamic> result,
  required String? fallback,
}) {
  final envelope = result['envelope'];
  if (envelope is! String || envelope.trim().isEmpty) return fallback;
  final recipientPeerIds = _stringListResultField(result, 'recipientPeerIds');
  return jsonEncode({
    'groupId': groupId,
    'message': envelope,
    if (result.containsKey('recipientPeerIds'))
      'recipientPeerIds': recipientPeerIds,
  });
}

String _defaultGroupMessageIdFactory() => const Uuid().v4();

String? _normalizeLogicalDeliveryId(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

GroupMemberDeviceIdentity? _resolveOutgoingSenderDevice({
  required GroupMember? senderMember,
  required String senderPublicKey,
  String? requestedDeviceId,
  String? requestedTransportPeerId,
}) {
  if (senderMember == null || senderMember.devices.isEmpty) {
    return null;
  }

  final normalizedDeviceId = requestedDeviceId?.trim();
  final normalizedTransportPeerId = requestedTransportPeerId?.trim();

  for (final device in senderMember.activeDevices) {
    if (normalizedDeviceId != null &&
        normalizedDeviceId.isNotEmpty &&
        device.deviceId != normalizedDeviceId) {
      continue;
    }
    if (normalizedTransportPeerId != null &&
        normalizedTransportPeerId.isNotEmpty &&
        device.transportPeerId != normalizedTransportPeerId) {
      continue;
    }
    if (device.deviceSigningPublicKey == senderPublicKey) {
      return device;
    }
  }
  return null;
}

/// Read-only admission used by media/voice/share producers before they create
/// any group-owned row, artifact, background task or network effect.
///
/// The returned strict snapshot freezes the same physical ACL and signer tuple
/// that [sendGroupMessage] revalidates before arming protected content. A
/// legacy result authorizes only the incumbent uninitialized-primary route;
/// every ambiguous or incomplete initialized shape is a refusal.
Future<GroupContentAuthoringAdmission> prepareGroupContentAuthoringAdmission({
  required GroupRepository groupRepo,
  required String groupId,
  required String senderPeerId,
  required String senderPublicKey,
  String? senderDeviceId,
  String? senderTransportPeerId,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  GroupContentAuthoringContext? explicitContext,
}) => runGroupAuthorityPhase(
  groupId: groupId,
  action: () async {
    final group = await groupRepo.getGroup(groupId);
    final key = await groupRepo.getLatestKey(groupId);
    final membership = await _loadGroupSendMembership(
      groupRepo: groupRepo,
      groupId: groupId,
      senderPeerId: senderPeerId,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    );
    GroupMember? sender;
    for (final candidate in membership.members) {
      if (candidate.peerId == senderPeerId) sender = candidate;
    }
    if (group == null ||
        group.selfRemovedAt != null ||
        group.isDissolved ||
        key == null ||
        sender == null ||
        (group.type == GroupType.announcement &&
            (group.myRole != GroupRole.admin ||
                sender.role != MemberRole.admin))) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        snapshot: null,
      );
    }
    final resolution = await resolveGroupContentAuthoring(
      resolverOwner: groupRepo,
      groupId: groupId,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderMember: sender,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      explicitContext: explicitContext,
    );
    if (resolution.kind != GroupContentAuthoringResolutionKind.strict ||
        resolution.context == null) {
      return (kind: resolution.kind, snapshot: null);
    }
    final context = resolution.context!;
    final authority = context.authorityVersion;
    if (!context.directLinkedDeviceSelector.allowsLinkedDeviceAuthoring ||
        !context.multiDeviceSyncEnabled ||
        authority == null ||
        context.inboxStore == null ||
        authority.keyEpoch != key.keyGeneration) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        snapshot: null,
      );
    }
    final credential = context.linkedTransportCredential;
    final validCredential =
        credential != null &&
        credential.state == LinkedTransportCredentialState.active &&
        credential.accountPeerId == senderPeerId;
    if (context.requireLinkedTransportCredential && !validCredential) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        snapshot: null,
      );
    }
    final requestedPublicKey = validCredential
        ? credential.transportPublicKey
        : context.authoringPublicKey ?? senderPublicKey;
    final requestedDeviceId = validCredential
        ? credential.deviceId
        : context.authoringDeviceId ?? senderDeviceId;
    final requestedTransportPeerId = validCredential
        ? credential.transportPeerId
        : context.authoringTransportPeerId ?? senderTransportPeerId;
    final device = _resolveOutgoingSenderDevice(
      senderMember: sender,
      senderPublicKey: requestedPublicKey,
      requestedDeviceId: requestedDeviceId,
      requestedTransportPeerId: requestedTransportPeerId,
    );
    if (sender.devices.isNotEmpty && device == null) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        snapshot: null,
      );
    }
    final resolvedDeviceId = requestedDeviceId?.trim().isNotEmpty == true
        ? requestedDeviceId!.trim()
        : device?.deviceId ?? senderPeerId;
    final resolvedTransportPeerId =
        requestedTransportPeerId?.trim().isNotEmpty == true
        ? requestedTransportPeerId!.trim()
        : device?.transportPeerId ?? resolvedDeviceId;
    final resolvedPublicKey =
        device?.deviceSigningPublicKey ?? requestedPublicKey;
    if (!hasUniqueStrictGroupContentAuthorBinding(
      members: membership.members,
      senderPeerId: senderPeerId,
      senderDeviceId: resolvedDeviceId,
      senderTransportPeerId: resolvedTransportPeerId,
      senderPublicKey: resolvedPublicKey,
    )) {
      return const (
        kind: GroupContentAuthoringResolutionKind.refuse,
        snapshot: null,
      );
    }
    final recipients = _strictPhysicalGroupRecipientPeerIds(
      members: membership.members,
      eligibleLogicalPeerIds: membership.recipientPeerIds,
      senderPeerId: senderPeerId,
      senderTransportPeerId: resolvedTransportPeerId,
    );
    return (
      kind: GroupContentAuthoringResolutionKind.strict,
      snapshot: StrictGroupContentAuthoringSnapshot(
        group: group,
        key: key,
        members: List<GroupMember>.unmodifiable(membership.members),
        senderMember: sender,
        context: context,
        senderDeviceId: resolvedDeviceId,
        senderTransportPeerId: resolvedTransportPeerId,
        senderPublicKey: resolvedPublicKey,
        recipientPeerIds: List<String>.unmodifiable(recipients),
      ),
    );
  },
);

bool _sameOptionalString(String? left, String? right) =>
    (left == null || left.isEmpty ? null : left) ==
    (right == null || right.isEmpty ? null : right);

bool _canReuseOutgoingMessageId({
  required GroupMessage existing,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  String? quotedMessageId,
  String? logicalDeliveryId,
  required GroupPrivateMediaPolicy privateMediaPolicy,
}) {
  if (existing.isIncoming) return false;
  // 210: 'queued_offline' is a live re-usable optimistic row too — the
  // media/voice paths pre-persist the optimistic message before calling this use
  // case, so an offline pre-save must be reused (not treated as a collision that
  // mints a duplicate row with a fresh id).
  if (existing.status != 'sending' &&
      existing.status != 'failed' &&
      existing.status != 'pending' &&
      existing.status != GroupMessage.statusQueuedOffline) {
    return false;
  }
  if (existing.groupId != groupId || existing.senderPeerId != senderPeerId) {
    return false;
  }
  if (existing.text != text) return false;
  if (existing.privateMediaPolicy != privateMediaPolicy) return false;
  if (!_sameOptionalString(existing.quotedMessageId, quotedMessageId)) {
    return false;
  }
  final existingLogicalDeliveryId = _normalizeLogicalDeliveryId(
    existing.logicalDeliveryId,
  );
  final requestedLogicalDeliveryId = _normalizeLogicalDeliveryId(
    logicalDeliveryId,
  );
  if (existingLogicalDeliveryId != null &&
      requestedLogicalDeliveryId != null &&
      existingLogicalDeliveryId != requestedLogicalDeliveryId) {
    return false;
  }
  return existing.timestamp.toUtc().isAtSameMomentAs(timestamp.toUtc());
}

Future<String?> _resolveOutgoingMessageId({
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  required GroupMessageIdFactory messageIdFactory,
  String? requestedMessageId,
  String? quotedMessageId,
  String? logicalDeliveryId,
  required GroupPrivateMediaPolicy privateMediaPolicy,
}) async {
  String nextCandidate() => messageIdFactory().trim();
  var candidate = requestedMessageId?.trim().isNotEmpty == true
      ? requestedMessageId!.trim()
      : nextCandidate();

  for (var attempt = 0; attempt < 8; attempt++) {
    if (candidate.isEmpty) {
      candidate = nextCandidate();
      continue;
    }

    final existing = await msgRepo.getMessage(candidate);
    if (existing == null) return candidate;

    if (_canReuseOutgoingMessageId(
      existing: existing,
      groupId: groupId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      quotedMessageId: quotedMessageId,
      logicalDeliveryId: logicalDeliveryId,
      privateMediaPolicy: privateMediaPolicy,
    )) {
      return candidate;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_ID_COLLISION',
      details: {
        'messageId': candidate.length > 8
            ? candidate.substring(0, 8)
            : candidate,
        'attempt': attempt + 1,
      },
    );
    candidate = nextCandidate();
  }

  return null;
}

/// Wraps [callGroupInboxStore] in try/catch — returns true on success.
///
/// Never throws. The caller observes the outcome via the return value.
Future<bool> _tryInboxStore({
  required Bridge bridge,
  required String groupId,
  required String inboxPayload,
  List<String>? recipientPeerIds,
  bool preserveRecipientPeerIds = false,
}) async {
  try {
    await callGroupInboxStore(
      bridge,
      groupId,
      inboxPayload,
      recipientPeerIds: recipientPeerIds,
      preserveRecipientPeerIds: preserveRecipientPeerIds,
    );
    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
      details: {'error': e.toString()},
    );
    return false;
  }
}

Future<bool> _driveStrictGroupMessageCustody({
  required GroupMessageRepository repository,
  required AckOrExpiryInboxStore store,
  required GroupMessage expected,
  required String sourcePeerId,
  required String sourceEventId,
  required String sourceTimestamp,
  required Map<String, Object?> eventPayload,
  required Future<bool> Function() currentAuthorityMatches,
  required Future<bool> Function(Future<bool> Function() mutation)
  commitIfAuthorityMatches,
}) async {
  if (repository is! GroupMessageStrictContentCompletionRepository ||
      repository is! GroupInboxStoreRetryPayloadCasRepository ||
      expected.inboxRetryPayload == null) {
    return false;
  }
  final exact = repository as GroupMessageStrictContentCompletionRepository;
  final cas = repository as GroupInboxStoreRetryPayloadCasRepository;
  final initial = GroupContentRetryPayload.decode(expected.inboxRetryPayload!);
  for (final recipient in initial.pendingRecipientPeerIds) {
    if (!await currentAuthorityMatches()) return false;
    final current = await repository.getMessage(expected.id);
    if (current?.inboxRetryPayload == null) return false;
    final decoded = GroupContentRetryPayload.decode(
      current!.inboxRetryPayload!,
    );
    if (decoded.message != initial.message ||
        decoded.contentEventId != initial.contentEventId ||
        !decoded.pendingRecipientPeerIds.contains(recipient)) {
      return false;
    }
    try {
      await storeGroupContentRetryRecipient(
        store: store,
        inboxRetryPayload: current.inboxRetryPayload!,
        recipientPeerId: recipient,
      );
    } catch (_) {
      continue;
    }
    if (decoded.pendingRecipientPeerIds.length == 1) {
      return commitIfAuthorityMatches(
        () => exact.completeStrictContentIfExact(
          current,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
        ),
      );
    }
    final survivors = decoded.pendingRecipientPeerIds
        .where((candidate) => candidate != recipient)
        .toList(growable: false);
    if (!await commitIfAuthorityMatches(
      () => cas.replaceInboxRetryPayloadIfExact(
        current,
        decoded.encodeWithPending(survivors),
      ),
    )) {
      return false;
    }
  }
  return false;
}

Future<void> _persistOutgoingMedia({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required List<MediaAttachment>? attachments,
}) async {
  if (mediaAttachmentRepo == null ||
      attachments == null ||
      attachments.isEmpty) {
    return;
  }

  final messageIds = attachments
      .map((attachment) => attachment.messageId)
      .where((messageId) => messageId.isNotEmpty)
      .toSet();
  if (messageIds.length == 1) {
    final messageId = messageIds.first;
    final expectedIds = attachments.map((attachment) => attachment.id).toSet();
    final existing = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    final hasStaleUploadPending = existing.any(
      (attachment) =>
          attachment.downloadStatus == 'upload_pending' &&
          !expectedIds.contains(attachment.id),
    );
    if (hasStaleUploadPending) {
      await mediaAttachmentRepo.deleteAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
    }
  }

  for (final attachment in attachments) {
    await mediaAttachmentRepo.saveAttachment(
      attachment,
      owner: MediaOwnerLane.group,
    );
  }
}

Future<void> _rollbackNewOutgoingMedia({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required String messageId,
  required List<MediaAttachment> attachments,
}) async {
  if (mediaAttachmentRepo == null || attachments.isEmpty) return;
  final attachmentIds = attachments.map((attachment) => attachment.id).toSet();
  final rollback = mediaAttachmentRepo;
  if (rollback is NewMessageMediaPersistenceRollback) {
    await (rollback as NewMessageMediaPersistenceRollback)
        .rollbackNewMessageAttachments(
          messageId: messageId,
          attachmentIds: attachmentIds,
          owner: MediaOwnerLane.group,
        );
    return;
  }
  await mediaAttachmentRepo.deleteAttachmentsForMessage(
    messageId,
    owner: MediaOwnerLane.group,
  );
}

bool _isExpectedDurablePrePersistMessage(
  GroupMessage? durable,
  GroupMessage expected,
) =>
    durable != null &&
    durable.id == expected.id &&
    durable.groupId == expected.groupId &&
    durable.senderPeerId == expected.senderPeerId &&
    durable.transportPeerId == expected.transportPeerId &&
    durable.senderUsername == expected.senderUsername &&
    durable.text == expected.text &&
    durable.timestamp.toUtc() == expected.timestamp.toUtc() &&
    (durable.status == 'sending' ||
        durable.status == 'failed' ||
        durable.status == GroupMessage.statusQueuedOffline) &&
    !durable.isIncoming &&
    durable.lastSendAttemptAt?.toUtc() == expected.lastSendAttemptAt?.toUtc() &&
    durable.quotedMessageId == expected.quotedMessageId &&
    durable.logicalDeliveryId == expected.logicalDeliveryId &&
    durable.keyGeneration == expected.keyGeneration &&
    durable.isForwarded == expected.isForwarded &&
    durable.privateMediaPolicy == expected.privateMediaPolicy &&
    durable.mediaReceivedAt == expected.mediaReceivedAt &&
    durable.mediaExpiresAt == expected.mediaExpiresAt &&
    durable.mediaLastCheckedAt == expected.mediaLastCheckedAt &&
    durable.mediaConsumedAt == expected.mediaConsumedAt &&
    durable.mediaExpiredAt == expected.mediaExpiredAt &&
    durable.mediaCleanupPending == expected.mediaCleanupPending &&
    durable.createdAt.toUtc() == expected.createdAt.toUtc() &&
    durable.wireEnvelope == expected.wireEnvelope &&
    !durable.inboxStored &&
    durable.inboxRetryPayload == expected.inboxRetryPayload;

bool _sameWaveform(List<double>? left, List<double>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _isExpectedDurableOutgoingMedia(
  MediaAttachment durable,
  MediaAttachment expected,
) =>
    durable.id == expected.id &&
    durable.messageId == expected.messageId &&
    durable.ownerLane == MediaOwnerLane.group &&
    durable.mime == expected.mime &&
    durable.size == expected.size &&
    durable.mediaType == expected.mediaType &&
    durable.width == expected.width &&
    durable.height == expected.height &&
    durable.durationMs == expected.durationMs &&
    durable.localPath == expected.localPath &&
    durable.downloadStatus == expected.downloadStatus &&
    durable.createdAt == expected.createdAt &&
    _sameWaveform(durable.waveform, expected.waveform) &&
    durable.contentHash == expected.contentHash &&
    durable.thumbnailHash == expected.thumbnailHash &&
    durable.encryptionKeyBase64 == expected.encryptionKeyBase64 &&
    durable.encryptionNonce == expected.encryptionNonce &&
    durable.encryptionScheme == expected.encryptionScheme;

Future<bool> _areExpectedOutgoingMediaDurable({
  required MediaAttachmentRepository? mediaAttachmentRepo,
  required String messageId,
  required List<MediaAttachment> expected,
}) async {
  if (expected.isEmpty) return true;
  if (mediaAttachmentRepo == null) return false;
  final stored = await mediaAttachmentRepo.getAttachmentsForMessage(
    messageId,
    owner: MediaOwnerLane.group,
  );
  final storedById = {
    for (final attachment in stored) attachment.id: attachment,
  };
  if (stored.length != expected.length ||
      storedById.length != expected.length) {
    return false;
  }
  return expected.every((attachment) {
    final durable = storedById[attachment.id];
    return durable != null &&
        durable.messageId == messageId &&
        _isExpectedDurableOutgoingMedia(durable, attachment);
  });
}

bool _isSameOutgoingPrePersistAttempt(
  GroupMessage? durable,
  GroupMessage expected,
) =>
    durable != null &&
    durable.id == expected.id &&
    durable.groupId == expected.groupId &&
    durable.senderPeerId == expected.senderPeerId &&
    durable.privateMediaPolicy == expected.privateMediaPolicy &&
    !durable.isIncoming &&
    durable.lastSendAttemptAt?.toUtc() == expected.lastSendAttemptAt?.toUtc();

Future<void> _rollbackRejectedOutgoingParent({
  required GroupMessageRepository msgRepo,
  required GroupMessage? preExistingMessage,
  required GroupMessage expectedAttempt,
}) async {
  final durable = await msgRepo.getMessage(expectedAttempt.id);
  if (!_isSameOutgoingPrePersistAttempt(durable, expectedAttempt)) return;
  if (preExistingMessage == null) {
    final rollback = msgRepo;
    if (rollback is! GroupMembershipRepairDeletionRepository) {
      throw StateError(
        'outgoing pre-persist rollback requires non-tombstoning deletion',
      );
    }
    await (rollback as GroupMembershipRepairDeletionRepository)
        .deleteMessageForMembershipRepair(expectedAttempt.id);
    return;
  }
  await msgRepo.saveMessage(preExistingMessage);
}

List<MediaAttachment>? _sanitizeGroupMediaAttachments(
  List<MediaAttachment>? attachments,
) {
  if (attachments == null || attachments.isEmpty) return attachments;
  final sanitized = <MediaAttachment>[];
  for (final attachment in attachments) {
    try {
      final mimeSanitized = GroupMediaMimePolicy.sanitizeAttachment(attachment);
      final contentHashValidation =
          GroupMediaIntegrityPolicy.validateRequiredContentHash(
            mimeSanitized.contentHash,
          );
      if (!contentHashValidation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
          details: {
            'blobId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
            'reason': contentHashValidation.reason,
          },
        );
        return null;
      }
      if (!mimeSanitized.hasEncryptionMetadata) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
          details: {
            'blobId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
            'reason': 'missing_media_encryption_metadata',
          },
        );
        return null;
      }
      final thumbnailHashValidation =
          GroupMediaIntegrityPolicy.validateOptionalThumbnailHash(
            mimeSanitized.thumbnailHash,
          );
      if (!thumbnailHashValidation.isValid) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
          details: {
            'blobId': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
            'reason': thumbnailHashValidation.reason,
          },
        );
        return null;
      }
      sanitized.add(
        mimeSanitized.copyWith(
          contentHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            mimeSanitized.contentHash,
          ),
          thumbnailHash: GroupMediaIntegrityPolicy.normalizeSha256Hex(
            mimeSanitized.thumbnailHash,
          ),
        ),
      );
    } catch (_) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
        details: {
          'blobId': attachment.id.length > 8
              ? attachment.id.substring(0, 8)
              : attachment.id,
          'mime': attachment.mime,
          'mediaType': attachment.mediaType,
        },
      );
      return null;
    }
  }

  final sizeValidation = GroupMediaSizePolicy.validateAttachments(sanitized);
  if (!sizeValidation.isValid) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_REJECTED_INVALID_MEDIA',
      details: {'reason': sizeValidation.reason},
    );
    return null;
  }
  return sanitized;
}

bool _preparedGroupMediaManifestMatchesAttachments({
  required ProtectedGroupMediaManifest manifest,
  required List<MediaAttachment> attachments,
  required String caption,
}) {
  if (manifest.attachments.length != attachments.length) return false;
  final expectedCaption = caption.trim().isEmpty ? null : caption;
  for (var index = 0; index < manifest.attachments.length; index++) {
    if (manifest.attachments[index].caption !=
        (index == 0 ? expectedCaption : null)) {
      return false;
    }
  }
  final byId = <String, MediaAttachment>{
    for (final attachment in attachments) attachment.id: attachment,
  };
  if (byId.length != attachments.length) return false;
  for (final commitment in manifest.attachments) {
    final attachment = byId[commitment.attachmentId];
    if (attachment == null ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.mime != commitment.mime ||
        attachment.mediaType != commitment.mediaType ||
        attachment.width != commitment.width ||
        attachment.height != commitment.height ||
        attachment.durationMs != commitment.durationMs ||
        attachment.contentHash != commitment.ciphertextSha256 ||
        attachment.encryptionKeyBase64 != commitment.encryptionKeyBase64 ||
        attachment.encryptionNonce != commitment.encryptionNonce ||
        attachment.encryptionScheme != commitment.encryptionScheme ||
        !_sameWaveform(attachment.waveform, commitment.waveform)) {
      return false;
    }
  }
  return true;
}

GroupPrivateMediaAttachmentKind _groupPrivateAttachmentKind(
  MediaAttachment attachment,
) {
  final mime = attachment.mime.trim().toLowerCase();
  if (mime == 'image/gif') return GroupPrivateMediaAttachmentKind.gif;
  if (mime.startsWith('image/')) return GroupPrivateMediaAttachmentKind.image;
  if (mime.startsWith('video/')) return GroupPrivateMediaAttachmentKind.video;
  if (mime.startsWith('audio/')) return GroupPrivateMediaAttachmentKind.audio;
  return GroupPrivateMediaAttachmentKind.file;
}

bool _isEligiblePrivateGroupMessageShape({
  required GroupPrivateMediaPolicy policy,
  required String text,
  required String? quotedMessageId,
  required bool isForwarded,
  required List<MediaAttachment> attachments,
}) {
  if (!policy.isPrivate) return false;
  final kind = attachments.length == 1
      ? _groupPrivateAttachmentKind(attachments.single)
      : GroupPrivateMediaAttachmentKind.unknown;
  return policy
      .validatedFor(
        GroupPrivateMediaEligibility(
          attachmentCount: attachments.length,
          attachmentKind: kind,
          hasTextOrCaption: text.trim().isNotEmpty,
          hasQuote: quotedMessageId?.trim().isNotEmpty == true,
          isForward: isForwarded,
        ),
      )
      .isPrivate;
}

bool _matchesExpectedPrivateGroupMediaRequest({
  required GroupMessage expected,
  required String? requestedMessageId,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  required String? quotedMessageId,
  required bool isForwarded,
  required GroupPrivateMediaPolicy privateMediaPolicy,
}) =>
    expected.id == requestedMessageId?.trim() &&
    expected.groupId == groupId &&
    expected.senderPeerId == senderPeerId &&
    expected.text == text &&
    expected.timestamp.toUtc() == timestamp.toUtc() &&
    _sameOptionalString(expected.quotedMessageId, quotedMessageId) &&
    expected.isForwarded == isForwarded &&
    expected.privateMediaPolicy == privateMediaPolicy &&
    !expected.isIncoming;

class GroupPrivateMediaSendQualification {
  GroupPrivateMediaSendQualification({
    required Iterable<GroupMember> members,
    required Iterable<String> recipientPeerIds,
  }) : members = List<GroupMember>.unmodifiable(members),
       recipientPeerIds = List<String>.unmodifiable(recipientPeerIds);

  final List<GroupMember> members;
  final List<String> recipientPeerIds;
}

bool sameExactGroupPrivateMediaDispatchParent(
  GroupMessage durable,
  GroupMessage expected,
) =>
    durable.id == expected.id &&
    durable.groupId == expected.groupId &&
    durable.senderPeerId == expected.senderPeerId &&
    durable.transportPeerId == expected.transportPeerId &&
    durable.senderUsername == expected.senderUsername &&
    durable.text == expected.text &&
    durable.timestamp.toUtc() == expected.timestamp.toUtc() &&
    durable.lastSendAttemptAt?.toUtc() == expected.lastSendAttemptAt?.toUtc() &&
    durable.quotedMessageId == expected.quotedMessageId &&
    durable.logicalDeliveryId == expected.logicalDeliveryId &&
    durable.keyGeneration == expected.keyGeneration &&
    durable.status == expected.status &&
    durable.isIncoming == expected.isIncoming &&
    durable.isForwarded == expected.isForwarded &&
    durable.privateMediaPolicy == expected.privateMediaPolicy &&
    durable.mediaReceivedAt == expected.mediaReceivedAt &&
    durable.mediaExpiresAt == expected.mediaExpiresAt &&
    durable.mediaLastCheckedAt == expected.mediaLastCheckedAt &&
    durable.mediaConsumedAt == expected.mediaConsumedAt &&
    durable.mediaExpiredAt == expected.mediaExpiredAt &&
    durable.mediaCleanupPending == expected.mediaCleanupPending &&
    durable.createdAt.toUtc() == expected.createdAt.toUtc() &&
    durable.wireEnvelope == expected.wireEnvelope &&
    durable.inboxStored == expected.inboxStored &&
    durable.inboxRetryPayload == expected.inboxRetryPayload &&
    durable.retryAttemptCount == expected.retryAttemptCount &&
    durable.nextEligibleAt?.toUtc() == expected.nextEligibleAt?.toUtc();

/// Reloads and fail-closed qualifies the exact current private parent while
/// returning the current roster-derived fanout snapshot.
Future<GroupPrivateMediaSendQualification?>
qualifyCurrentPrivateGroupMediaSend({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required GroupMessage expectedParent,
  required String senderPeerId,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  bool includeSenderPeerIdInDurableRecipients = false,
}) async {
  final policy = expectedParent.privateMediaPolicy;
  if (!policy.isPrivate ||
      senderPeerId.trim().isEmpty ||
      expectedParent.senderPeerId != senderPeerId) {
    return null;
  }
  try {
    final durable = await msgRepo.getMessage(expectedParent.id);
    if (durable == null ||
        !sameExactGroupPrivateMediaDispatchParent(durable, expectedParent) ||
        durable.isIncoming) {
      return null;
    }
    final group = await groupRepo.getGroup(expectedParent.groupId);
    if (group == null ||
        group.isDissolved ||
        (group.type != GroupType.chat &&
            group.type != GroupType.announcement)) {
      return null;
    }
    final latestKey = await groupRepo.getLatestKey(expectedParent.groupId);
    if (latestKey == null ||
        latestKey.keyGeneration != expectedParent.keyGeneration) {
      return null;
    }

    // Key lookup is an async race boundary. Reload both local group authority
    // and the current roster after it; `_loadGroupSendMembership` deliberately
    // performs its roster read last so no later await can launder a demotion
    // into upload, retry, reliable-send, fallback, or inbox-store work.
    final currentGroup = await groupRepo.getGroup(expectedParent.groupId);
    if (currentGroup == null ||
        currentGroup.isDissolved ||
        (currentGroup.type != GroupType.chat &&
            currentGroup.type != GroupType.announcement)) {
      return null;
    }
    final membershipCutoff =
        !expectedParent.timestamp.toUtc().isBefore(
          currentGroup.createdAt.toUtc(),
        )
        ? expectedParent.timestamp
        : null;
    final membership = await _loadGroupSendMembership(
      groupRepo: groupRepo,
      groupId: expectedParent.groupId,
      senderPeerId: senderPeerId,
      membershipCutoff: membershipCutoff,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    );
    if (membership.members.isEmpty) return null;
    GroupMember? sender;
    for (final member in membership.members) {
      if (member.peerId == senderPeerId) {
        sender = member;
        break;
      }
    }
    if (sender == null ||
        !GroupPrivateMediaAvailability.hasEligibleCurrentAuthorRole(
          groupType: currentGroup.type,
          localRole: currentGroup.myRole,
          memberRole: sender.role,
        )) {
      return null;
    }
    return GroupPrivateMediaSendQualification(
      members: membership.members,
      recipientPeerIds: _durableGroupRecipientPeerIds(
        remoteRecipientPeerIds: membership.recipientPeerIds,
        senderPeerId: senderPeerId,
        includeSenderPeerId: includeSenderPeerIdInDurableRecipients,
      ),
    );
  } catch (_) {
    return null;
  }
}

/// Reloads and fail-closed qualifies the exact current private parent.
///
/// Ordinary rows retain their existing permissive send behavior. Unsupported
/// rows and private rows whose group, roster, writer role, key, or exact parent
/// changed are denied before upload, publication, or inbox-store work.
Future<bool> requalifyCurrentPrivateGroupMediaSend({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required GroupMessage expectedParent,
  required String senderPeerId,
}) async {
  final policy = expectedParent.privateMediaPolicy;
  if (policy.isOrdinary) return true;
  return await qualifyCurrentPrivateGroupMediaSend(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        expectedParent: expectedParent,
        senderPeerId: senderPeerId,
      ) !=
      null;
}

/// Runs the initial private-media upload only after the exact optimistic
/// policy-bearing parent has been durably reloaded and current discussion
/// authorization has been requalified.
///
/// Ordinary uploads preserve their existing path. Unsupported or unavailable
/// private policy fails closed without invoking [upload].
Future<T?> runQualifiedPrivateGroupMediaInitialUpload<T>({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required GroupMessage expectedParent,
  required String senderPeerId,
  required GroupPrivateMediaAvailability privateMediaAvailability,
  List<String>? expectedAllowedPeerIds,
  required Future<T?> Function() upload,
}) async {
  final policy = expectedParent.privateMediaPolicy;
  if (policy.isOrdinary) return upload();
  if (policy.isUnsupported || !privateMediaAvailability.isEnabled) {
    return null;
  }
  final qualification = await qualifyCurrentPrivateGroupMediaSend(
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    expectedParent: expectedParent,
    senderPeerId: senderPeerId,
  );
  if (qualification == null) return null;
  final expectedAcl = expectedAllowedPeerIds;
  if (expectedAcl != null &&
      !sameGroupPrivateMediaRecipientPeerIds(
        expectedAcl,
        groupMediaAllowedPeersForMembers(qualification.members),
      )) {
    return null;
  }
  return upload();
}

/// Sends a message to a group.
///
/// Owns optimistic persistence for ALL production callers:
/// 1. Validates group exists + sender authorized
/// 2. Pre-persists row with status `'sending'` + wireEnvelope + inboxRetryPayload
/// 3. Kicks off publish + inbox store concurrently
/// 4. Reads topicPeers from publish result as live fanout, not delivery ACK
/// 5. Applies 4-way result matrix to determine final status
///
/// Go's GroupPublish handles encryption and signing internally,
/// so it needs the sender's public and private keys.
Future<(SendGroupMessageResult, GroupMessage?)> sendGroupMessage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? messageId,
  String? logicalDeliveryId,
  GroupMessageIdFactory? messageIdFactory,
  DateTime? timestamp,
  String? quotedMessageId,
  // 236: explicit internal Forward marker. Rides the encrypted payload extras
  // plus every durable retry/replay map; never any outer routing field.
  bool isForwarded = false,
  GroupPrivateMediaPolicy privateMediaPolicy =
      const GroupPrivateMediaPolicy.ordinary(),
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,

  /// The exact private parent qualified by a caller before an awaited upload
  /// or retry-preparation gap. When supplied, dispatch must still target this
  /// same durable row; deletion or drift may not recreate it or mint a sibling.
  GroupMessage? expectedPrivateParentBeforeDispatch,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  bool emitTimingEvent = true,
  bool includeSenderPeerIdInDurableRecipients = false,
  int Function()? privateMediaNowMs,
  GroupMessage? expectedRetryParentBeforeDispatch,
  CurrentGroupSendAuthorityCheck? currentAuthorityCheck,
  GroupContentAuthoringContext? groupContentAuthoring,
  PreparedGroupMediaManifestAuthority? preparedGroupMediaManifest,
}) async {
  Future<(SendGroupMessageResult, GroupMessage?)> runSend({
    required bool legacyMembershipActionPhaseHeld,
    GroupContentAuthoringResolution? entryAuthoringResolution,
  }) => _sendGroupMessageWithAuthorityRecheck(
    bridge: bridge,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    groupId: groupId,
    text: text,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderUsername: senderUsername,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    messageId: messageId,
    logicalDeliveryId: logicalDeliveryId,
    messageIdFactory: messageIdFactory,
    timestamp: timestamp,
    quotedMessageId: quotedMessageId,
    isForwarded: isForwarded,
    privateMediaPolicy: privateMediaPolicy,
    privateMediaAvailability: privateMediaAvailability,
    expectedPrivateParentBeforeDispatch: expectedPrivateParentBeforeDispatch,
    expectedRetryParentBeforeDispatch: expectedRetryParentBeforeDispatch,
    mediaAttachments: mediaAttachments,
    mediaAttachmentRepo: mediaAttachmentRepo,
    inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
    emitTimingEvent: emitTimingEvent,
    includeSenderPeerIdInDurableRecipients:
        includeSenderPeerIdInDurableRecipients,
    privateMediaNowMs: privateMediaNowMs,
    currentAuthorityCheck: currentAuthorityCheck,
    groupContentAuthoring: groupContentAuthoring,
    preparedGroupMediaManifest: preparedGroupMediaManifest,
    legacyMembershipActionPhaseHeld: legacyMembershipActionPhaseHeld,
    entryAuthoringResolution: entryAuthoringResolution,
  );

  // An explicit context is a strict-only unit seam. It can never select the
  // uninitialized legacy transport, so enter the normal short snapshot phase
  // directly and avoid an extra roster read before the in-lock drift check.
  if (groupContentAuthoring != null) {
    return runSend(legacyMembershipActionPhaseHeld: false);
  }

  // With no production resolver installed, this is an incumbent/test
  // composition. Finish its legacy operation inside the original whole-send
  // membership phase. Production installs the resolver before authoring, so
  // initialized production authority cannot enter this seam.
  if (_groupContentAuthoringResolvers[groupRepo] == null) {
    return runGroupMembershipActionIfNeeded(
      groupId: groupId,
      membershipActionPhaseHeld: isGroupMembershipActionPhaseHeld(groupId),
      action: () => runSend(legacyMembershipActionPhaseHeld: true),
    );
  }

  // Classify under the shared queue. The uninitialized ordinary-primary keeps
  // its incumbent whole-operation PGC-010 phase, while strict/refused content
  // releases this short classification phase before candidate crypto and
  // protected recipient delivery.
  var legacySelected = false;
  GroupContentAuthoringResolution? entryRefusal;
  (SendGroupMessageResult, GroupMessage?)? legacyResult;
  await runGroupMembershipActionIfNeeded<void>(
    groupId: groupId,
    membershipActionPhaseHeld: isGroupMembershipActionPhaseHeld(groupId),
    action: () async {
      final entryAuthoringResolution =
          await _classifyGroupContentAuthoringEntry(
            groupRepo: groupRepo,
            groupId: groupId,
            senderPeerId: senderPeerId,
            senderPublicKey: senderPublicKey,
            senderDeviceId: senderDeviceId,
            senderTransportPeerId: senderTransportPeerId,
            timestamp: timestamp,
            inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
            explicitContext: groupContentAuthoring,
          );
      legacySelected =
          entryAuthoringResolution?.kind ==
          GroupContentAuthoringResolutionKind.legacyUninitialized;
      if (entryAuthoringResolution?.kind ==
          GroupContentAuthoringResolutionKind.refuse) {
        entryRefusal = entryAuthoringResolution;
      }
      if (legacySelected) {
        // Resolve once more inside the complete legacy action. Authority
        // initialization that races classification therefore refuses before
        // persistence or network dispatch.
        legacyResult = await runSend(legacyMembershipActionPhaseHeld: true);
      }
    },
  );
  if (legacySelected) return legacyResult!;

  // The action-phase classification above is only a branch hint. Strict and
  // refused attempts take an authoritative snapshot under the shared
  // protected phase. A fail-closed refusal may be carried forward because a
  // stale refusal can only reject; it can never authorize persistence.
  return runSend(
    legacyMembershipActionPhaseHeld: false,
    entryAuthoringResolution: entryRefusal,
  );
}

Future<(SendGroupMessageResult, GroupMessage?)>
_sendGroupMessageWithAuthorityRecheck({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String senderUsername,
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? messageId,
  String? logicalDeliveryId,
  GroupMessageIdFactory? messageIdFactory,
  DateTime? timestamp,
  String? quotedMessageId,
  bool isForwarded = false,
  GroupPrivateMediaPolicy privateMediaPolicy =
      const GroupPrivateMediaPolicy.ordinary(),
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,
  GroupMessage? expectedPrivateParentBeforeDispatch,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  bool emitTimingEvent = true,
  bool includeSenderPeerIdInDurableRecipients = false,
  int Function()? privateMediaNowMs,
  GroupMessage? expectedRetryParentBeforeDispatch,
  CurrentGroupSendAuthorityCheck? currentAuthorityCheck,
  GroupContentAuthoringContext? groupContentAuthoring,
  PreparedGroupMediaManifestAuthority? preparedGroupMediaManifest,
  bool legacyMembershipActionPhaseHeld = false,
  GroupContentAuthoringResolution? entryAuthoringResolution,
}) async {
  int currentPrivateMediaNowMs() =>
      privateMediaNowMs?.call() ??
      DateTime.now().toUtc().millisecondsSinceEpoch;

  final sendStopwatch = Stopwatch()..start();
  final sanitizedText = sanitizeMessageText(text);
  final hasMedia = mediaAttachments != null && mediaAttachments.isNotEmpty;
  int? prepareMs;
  int? publishMs;
  int? inboxMs;
  void emitGroupSendTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    if (!emitTimingEvent) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'hasMedia': hasMedia,
        'prepareMs': ?prepareMs,
        'publishMs': ?publishMs,
        'inboxMs': ?inboxMs,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SEND_MSG_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'textLength': sanitizedText.length,
    },
  );

  // 1. Load group from repo (verify exists)
  final group = await groupRepo.getGroup(groupId);
  if (group == null || group.selfRemovedAt != null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_NOT_FOUND',
      details: {},
    );
    emitGroupSendTiming(outcome: 'group_not_found');
    return (SendGroupMessageResult.groupNotFound, null);
  }

  if (group.isDissolved) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (group.dissolvedAt != null)
          'dissolvedAt': group.dissolvedAt!.toUtc().toIso8601String(),
      },
    );
    emitGroupSendTiming(outcome: 'group_dissolved');
    return (SendGroupMessageResult.groupDissolved, null);
  }

  if (privateMediaPolicy.isPrivate &&
      !privateMediaAvailability.canAuthorPrivateMedia(group.type)) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'private_media_unavailable'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }

  if (group.type == GroupType.announcement && isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'groupType': group.type.toValue(),
      },
    );
    emitGroupSendTiming(outcome: 'group_recovery_pending');
    return (SendGroupMessageResult.error, null);
  }

  // 2. Check role authorization (announcement: only admin can send)
  if (group.type == GroupType.announcement && group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'type': group.type.toValue(), 'role': group.myRole.toValue()},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {
        'groupType': group.type.toValue(),
        'role': group.myRole.toValue(),
      },
    );
    return (SendGroupMessageResult.unauthorized, null);
  }

  // 2b. Reject empty messages (no text and no media)
  if (sanitizedText.trim().isEmpty && !hasMedia) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_EMPTY',
      details: {},
    );
    emitGroupSendTiming(outcome: 'empty');
    return (SendGroupMessageResult.error, null);
  }

  final groupMediaAttachments = _sanitizeGroupMediaAttachments(
    mediaAttachments,
  );
  if (hasMedia && groupMediaAttachments == null) {
    emitGroupSendTiming(outcome: 'invalid_media');
    return (SendGroupMessageResult.error, null);
  }
  if (preparedGroupMediaManifest != null && !hasMedia) {
    emitGroupSendTiming(outcome: 'invalid_media');
    return (SendGroupMessageResult.error, null);
  }
  if (privateMediaPolicy.isUnsupported ||
      (privateMediaPolicy.isPrivate &&
          !_isEligiblePrivateGroupMessageShape(
            policy: privateMediaPolicy,
            text: sanitizedText,
            quotedMessageId: quotedMessageId,
            isForwarded: isForwarded,
            attachments: groupMediaAttachments ?? const <MediaAttachment>[],
          ))) {
    emitGroupSendTiming(outcome: 'invalid_private_media_policy');
    return (SendGroupMessageResult.error, null);
  }
  if (privateMediaPolicy.isPrivate &&
      ((group.type != GroupType.chat && group.type != GroupType.announcement) ||
          senderPeerId.trim().isEmpty ||
          senderPublicKey.trim().isEmpty ||
          senderPrivateKey.trim().isEmpty)) {
    emitGroupSendTiming(outcome: 'unauthorized');
    return (SendGroupMessageResult.unauthorized, null);
  }

  // 3. Prepare all parameters
  final prepareStopwatch = Stopwatch()..start();
  final now = timestamp ?? DateTime.now().toUtc();
  final sendAttemptAt = DateTime.now().toUtc();
  final membershipCutoff =
      timestamp != null && !timestamp.toUtc().isBefore(group.createdAt.toUtc())
      ? timestamp
      : null;
  late final ({
    GroupKeyInfo? key,
    ({List<GroupMember> members, List<String> recipientPeerIds}) membership,
    GroupMember? senderMember,
    GroupContentAuthoringResolution authoring,
  })
  authoritySnapshot;
  try {
    Future<
      ({
        GroupKeyInfo? key,
        ({List<GroupMember> members, List<String> recipientPeerIds}) membership,
        GroupMember? senderMember,
        GroupContentAuthoringResolution authoring,
      })
    >
    loadSnapshot() async {
      final membershipFuture = _loadGroupSendMembership(
        groupRepo: groupRepo,
        groupId: groupId,
        senderPeerId: senderPeerId,
        membershipCutoff: membershipCutoff,
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      );
      final keyFuture = groupRepo.getLatestKey(groupId);
      final membership = await membershipFuture;
      GroupMember? snapshotSender;
      for (final member in membership.members) {
        if (member.peerId == senderPeerId) snapshotSender = member;
      }
      final authoring =
          entryAuthoringResolution ??
          (snapshotSender == null
              ? (_groupContentAuthoringResolvers[groupRepo] == null &&
                        groupContentAuthoring == null
                    ? const (
                        kind: GroupContentAuthoringResolutionKind
                            .legacyUninitialized,
                        context: null,
                      )
                    : const (
                        kind: GroupContentAuthoringResolutionKind.refuse,
                        context: null,
                      ))
              : await resolveGroupContentAuthoring(
                  resolverOwner: groupRepo,
                  groupId: groupId,
                  senderPeerId: senderPeerId,
                  senderPublicKey: senderPublicKey,
                  senderMember: snapshotSender,
                  senderDeviceId: senderDeviceId,
                  senderTransportPeerId: senderTransportPeerId,
                  explicitContext: groupContentAuthoring,
                ));
      return (
        key: await keyFuture,
        membership: membership,
        senderMember: snapshotSender,
        authoring: authoring,
      );
    }

    authoritySnapshot = await runGroupAuthorityPhaseIfNeeded(
      groupId: groupId,
      authorityPhaseHeld:
          legacyMembershipActionPhaseHeld || isGroupAuthorityPhaseHeld(groupId),
      action: loadSnapshot,
    );
  } catch (_) {
    if (privateMediaPolicy.isPrivate) {
      emitGroupSendTiming(
        outcome: 'unauthorized',
        details: {'reason': 'roster_unavailable'},
      );
      return (SendGroupMessageResult.unauthorized, null);
    }
    rethrow;
  }
  final entryAuthoringKind = authoritySnapshot.authoring.kind;
  if (!legacyMembershipActionPhaseHeld &&
      entryAuthoringKind ==
          GroupContentAuthoringResolutionKind.legacyUninitialized) {
    // Preserve the incumbent PGC-010 contract for the uninitialized ordinary
    // primary: its complete persistence + network action stays serialized
    // against membership mutations. Strict Plan-364 content deliberately does
    // not take this path because candidate crypto and recipient delivery must
    // not monopolize the authority queue.
    return runGroupMembershipActionIfNeeded(
      groupId: groupId,
      membershipActionPhaseHeld: isGroupMembershipActionPhaseHeld(groupId),
      action: () => _sendGroupMessageWithAuthorityRecheck(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: text,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderTransportPeerId,
        messageId: messageId,
        logicalDeliveryId: logicalDeliveryId,
        messageIdFactory: messageIdFactory,
        timestamp: timestamp,
        quotedMessageId: quotedMessageId,
        isForwarded: isForwarded,
        privateMediaPolicy: privateMediaPolicy,
        privateMediaAvailability: privateMediaAvailability,
        expectedPrivateParentBeforeDispatch:
            expectedPrivateParentBeforeDispatch,
        mediaAttachments: mediaAttachments,
        mediaAttachmentRepo: mediaAttachmentRepo,
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
        emitTimingEvent: emitTimingEvent,
        includeSenderPeerIdInDurableRecipients:
            includeSenderPeerIdInDurableRecipients,
        privateMediaNowMs: privateMediaNowMs,
        expectedRetryParentBeforeDispatch: expectedRetryParentBeforeDispatch,
        currentAuthorityCheck: currentAuthorityCheck,
        groupContentAuthoring: groupContentAuthoring,
        preparedGroupMediaManifest: preparedGroupMediaManifest,
        legacyMembershipActionPhaseHeld: true,
        entryAuthoringResolution: entryAuthoringResolution,
      ),
    );
  }
  if (legacyMembershipActionPhaseHeld &&
      entryAuthoringKind !=
          GroupContentAuthoringResolutionKind.legacyUninitialized) {
    // Authority initialized between the pre-lock snapshot and lock
    // acquisition. Refuse this stale legacy attempt; a new invocation can
    // enter the strict short-phase branch with a fresh credential and ACL.
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'legacy_authority_initialized_during_entry'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (currentAuthorityCheck != null && !await currentAuthorityCheck()) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'expected_authority_drifted'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final sendMembership = authoritySnapshot.membership;
  final members = sendMembership.members;
  final senderConfigured = members.any(
    (member) => member.peerId == senderPeerId,
  );
  final currentSenderMember = authoritySnapshot.senderMember;
  if (privateMediaPolicy.isPrivate &&
      (currentSenderMember == null ||
          !privateMediaAvailability.canCurrentMemberAuthorPrivateMedia(
            groupType: group.type,
            localRole: group.myRole,
            memberRole: currentSenderMember.role,
          ))) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'private_sender_not_writer'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (!senderConfigured &&
      (members.isNotEmpty || group.myRole != GroupRole.admin)) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'reason': 'sender_not_member'},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'sender_not_member'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final latestKey = authoritySnapshot.key;
  if (!senderConfigured && latestKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNAUTHORIZED',
      details: {'reason': 'sender_not_member'},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'sender_not_member'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (latestKey == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_BOOTSTRAP_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'role': group.myRole.toValue(),
      },
    );
    emitGroupSendTiming(
      outcome: 'bootstrap_pending',
      details: {'role': group.myRole.toValue()},
    );
    return (SendGroupMessageResult.error, null);
  }
  if (privateMediaPolicy.isPrivate && members.isEmpty) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'empty_membership'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (group.type == GroupType.chat && members.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    emitGroupSendTiming(
      outcome: 'group_dissolved',
      details: {'reason': 'empty_membership'},
    );
    return (SendGroupMessageResult.groupDissolved, null);
  }
  if (expectedPrivateParentBeforeDispatch != null &&
      expectedRetryParentBeforeDispatch != null &&
      !identical(
        expectedPrivateParentBeforeDispatch,
        expectedRetryParentBeforeDispatch,
      )) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'conflicting_expected_parents'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final expectedDispatchParent =
      expectedPrivateParentBeforeDispatch ?? expectedRetryParentBeforeDispatch;
  String? resolvedMessageId;
  if (expectedDispatchParent != null) {
    final qualification = privateMediaPolicy.isPrivate
        ? await qualifyCurrentPrivateGroupMediaSend(
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            expectedParent: expectedDispatchParent,
            senderPeerId: senderPeerId,
            inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
            includeSenderPeerIdInDurableRecipients:
                includeSenderPeerIdInDurableRecipients,
          )
        : null;
    final currentParent = await msgRepo.getMessage(expectedDispatchParent.id);
    if ((privateMediaPolicy.isPrivate && qualification == null) ||
        currentParent == null ||
        !sameExactGroupPrivateMediaDispatchParent(
          currentParent,
          expectedDispatchParent,
        ) ||
        !_matchesExpectedPrivateGroupMediaRequest(
          expected: expectedDispatchParent,
          requestedMessageId: messageId,
          groupId: groupId,
          senderPeerId: senderPeerId,
          text: sanitizedText,
          timestamp: now,
          quotedMessageId: quotedMessageId,
          isForwarded: isForwarded,
          privateMediaPolicy: privateMediaPolicy,
        )) {
      emitGroupSendTiming(
        outcome: 'unauthorized',
        details: {'reason': 'private_expected_parent_drifted'},
      );
      return (SendGroupMessageResult.unauthorized, currentParent);
    }
    resolvedMessageId = expectedDispatchParent.id;
  } else {
    resolvedMessageId = await _resolveOutgoingMessageId(
      msgRepo: msgRepo,
      groupId: groupId,
      senderPeerId: senderPeerId,
      text: sanitizedText,
      timestamp: now,
      quotedMessageId: quotedMessageId,
      logicalDeliveryId: logicalDeliveryId,
      privateMediaPolicy: privateMediaPolicy,
      requestedMessageId: messageId,
      messageIdFactory: messageIdFactory ?? _defaultGroupMessageIdFactory,
    );
  }
  if (resolvedMessageId == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_ID_COLLISION_UNRESOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    emitGroupSendTiming(outcome: 'message_id_collision');
    return (SendGroupMessageResult.error, null);
  }
  final resolvedLogicalDeliveryId =
      _normalizeLogicalDeliveryId(logicalDeliveryId) ?? resolvedMessageId;
  final keyEpoch = latestKey.keyGeneration;
  final senderMember = currentSenderMember;
  final initializedDeviceAuthority = senderMember?.devices.isNotEmpty == true;
  final authoringResolution = authoritySnapshot.authoring;
  final resolverAbsentLegacy =
      legacyMembershipActionPhaseHeld &&
      isResolverAbsentLegacyGroupContentAuthoring(
        owner: groupRepo,
        explicitContext: groupContentAuthoring,
      );
  if (authoringResolution.kind == GroupContentAuthoringResolutionKind.refuse ||
      (initializedDeviceAuthority &&
          !resolverAbsentLegacy &&
          authoringResolution.kind !=
              GroupContentAuthoringResolutionKind.strict)) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'strict_group_content_authority_unavailable'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final strictContext = authoringResolution.context;
  final strictSelected = strictContext != null;
  final hasQuote = quotedMessageId?.isNotEmpty == true;
  final eligibleForwardedMedia =
      isForwarded &&
      hasMedia &&
      !hasQuote &&
      (groupMediaAttachments ?? const <MediaAttachment>[]).every(
        (attachment) =>
            attachment.mediaType == 'image' || attachment.mediaType == 'video',
      );
  if (strictSelected &&
      (!strictContext.directLinkedDeviceSelector.allowsLinkedDeviceAuthoring ||
          !strictContext.multiDeviceSyncEnabled ||
          strictContext.authorityVersion == null ||
          strictContext.inboxStore == null ||
          (hasMedia && preparedGroupMediaManifest == null) ||
          (!hasMedia && preparedGroupMediaManifest != null) ||
          (isForwarded && !eligibleForwardedMedia) ||
          !privateMediaPolicy.isOrdinary ||
          (!hasMedia && sanitizedText.trim().isEmpty) ||
          sanitizedText.trimLeft().startsWith(r'{"__sys":') ||
          (group.type == GroupType.announcement &&
              senderMember?.role != MemberRole.admin))) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'strict_group_content_not_qualified'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  if (strictSelected &&
      !validGroupContentAuthoringOrder(
        authority: strictContext.authorityVersion!,
        contentAt: now,
        contentEventId: resolvedMessageId,
      )) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'strict_group_content_order_invalid'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final linkedCredential = strictSelected
      ? strictContext.linkedTransportCredential
      : null;
  final validLinkedCredential =
      linkedCredential != null &&
      linkedCredential.state == LinkedTransportCredentialState.active &&
      linkedCredential.accountPeerId == senderPeerId;
  if (strictSelected &&
      strictContext.requireLinkedTransportCredential &&
      !validLinkedCredential) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'strict_group_content_missing_credential'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final requestedSigningPublicKey = validLinkedCredential
      ? linkedCredential.transportPublicKey
      : strictContext?.authoringPublicKey ?? senderPublicKey;
  final requestedSigningPrivateKey = validLinkedCredential
      ? linkedCredential.transportPrivateKey
      : senderPrivateKey;
  final requestedSigningDeviceId = validLinkedCredential
      ? linkedCredential.deviceId
      : strictContext?.authoringDeviceId ?? senderDeviceId;
  final requestedSigningTransportPeerId = validLinkedCredential
      ? linkedCredential.transportPeerId
      : strictContext?.authoringTransportPeerId ?? senderTransportPeerId;
  final resolvedSenderDevice = _resolveOutgoingSenderDevice(
    senderMember: senderMember,
    senderPublicKey: requestedSigningPublicKey,
    requestedDeviceId: requestedSigningDeviceId,
    requestedTransportPeerId: requestedSigningTransportPeerId,
  );
  if (senderMember?.devices.isNotEmpty == true &&
      resolvedSenderDevice == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_UNBOUND_DEVICE',
      details: {'reason': 'sender_device_not_registered'},
    );
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'sender_device_not_registered'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final resolvedSenderDeviceId =
      requestedSigningDeviceId?.trim().isNotEmpty == true
      ? requestedSigningDeviceId!.trim()
      : resolvedSenderDevice?.deviceId ?? senderPeerId;
  final resolvedSenderTransportPeerId =
      requestedSigningTransportPeerId?.trim().isNotEmpty == true
      ? requestedSigningTransportPeerId!.trim()
      : resolvedSenderDevice?.transportPeerId ?? resolvedSenderDeviceId;
  final resolvedSenderDevicePublicKey =
      resolvedSenderDevice?.deviceSigningPublicKey ?? requestedSigningPublicKey;
  if (strictSelected &&
      !hasUniqueStrictGroupContentAuthorBinding(
        members: members,
        senderPeerId: senderPeerId,
        senderDeviceId: resolvedSenderDeviceId,
        senderTransportPeerId: resolvedSenderTransportPeerId,
        senderPublicKey: resolvedSenderDevicePublicKey,
      )) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'strict_group_content_ambiguous_sender_binding'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }

  final recipientPeerIds = strictSelected
      ? _strictPhysicalGroupRecipientPeerIds(
          members: members,
          eligibleLogicalPeerIds: sendMembership.recipientPeerIds,
          senderPeerId: senderPeerId,
          senderTransportPeerId: resolvedSenderTransportPeerId,
        )
      : _durableGroupRecipientPeerIds(
          remoteRecipientPeerIds: sendMembership.recipientPeerIds,
          senderPeerId: senderPeerId,
          includeSenderPeerId: includeSenderPeerIdInDurableRecipients,
        );
  final strictMediaManifest = strictSelected
      ? preparedGroupMediaManifest?.manifest
      : null;
  if (strictSelected &&
      strictMediaManifest != null &&
      (!strictMediaManifest.matchesAuthority(
            expectedGroupId: groupId,
            expectedMessageId: resolvedMessageId,
            expectedRecipientPeerIds: recipientPeerIds,
          ) ||
          !_preparedGroupMediaManifestMatchesAttachments(
            manifest: strictMediaManifest,
            attachments: groupMediaAttachments ?? const <MediaAttachment>[],
            caption: sanitizedText,
          ))) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'strict_group_media_manifest_mismatch'},
    );
    return (SendGroupMessageResult.unauthorized, null);
  }
  final mediaJson = strictSelected
      ? null
      : groupMediaAttachments?.map((a) => a.toJson()).toList();
  final strictMediaManifestJson = strictMediaManifest?.encode();
  final expectedRecipientCount = recipientPeerIds.length;
  final resolvedGroupName = group.name.trim();
  // 3b. Build wireEnvelope (plaintext publish params for retry - NO senderPrivateKey)
  final wireEnvelope = jsonEncode({
    'groupId': groupId,
    'text': sanitizedText,
    'senderPeerId': senderPeerId,
    'senderDeviceId': resolvedSenderDeviceId,
    'transportPeerId': resolvedSenderTransportPeerId,
    'senderPublicKey': strictSelected
        ? resolvedSenderDevicePublicKey
        : senderPublicKey,
    'senderUsername': senderUsername,
    'messageId': resolvedMessageId,
    'logicalDeliveryId': resolvedLogicalDeliveryId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
    'mediaManifest': ?strictMediaManifestJson,
    if (strictMediaManifest != null)
      'mediaManifestHash': strictMediaManifest.fingerprintSha256,
    if (isForwarded) 'isForwarded': true,
    ...?privateMediaPolicy.toWireExtras(),
  });

  // 3c. Build inboxRetryPayload (exact inputs for callGroupInboxStore)
  final inboxPayload = jsonEncode({
    'groupId': groupId,
    if (resolvedGroupName.isNotEmpty) 'groupName': resolvedGroupName,
    'senderId': senderPeerId,
    'senderDeviceId': resolvedSenderDeviceId,
    'transportPeerId': resolvedSenderTransportPeerId,
    'senderUsername': senderUsername,
    'keyEpoch': keyEpoch,
    'text': sanitizedText,
    'timestamp': strictSelected
        ? fixedGroupContentUtc(now)
        : now.toIso8601String(),
    'messageId': resolvedMessageId,
    'logicalDeliveryId': resolvedLogicalDeliveryId,
    if (quotedMessageId != null && quotedMessageId.isNotEmpty)
      'quotedMessageId': quotedMessageId,
    if (mediaJson != null && mediaJson.isNotEmpty) 'media': mediaJson,
    'mediaManifest': ?strictMediaManifestJson,
    if (strictMediaManifest != null)
      'mediaManifestHash': strictMediaManifest.fingerprintSha256,
    if (isForwarded) 'isForwarded': true,
    ...?privateMediaPolicy.toWireExtras(),
  });
  String? replayEnvelope;
  String? inboxRetryPayload;
  try {
    replayEnvelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: inboxPayload,
      senderPeerId: senderPeerId,
      senderPublicKey: resolvedSenderDevicePublicKey,
      senderPrivateKey: requestedSigningPrivateKey,
      keyInfo: latestKey,
      messageId: resolvedMessageId,
      senderDeviceId: resolvedSenderDeviceId,
      senderTransportPeerId: resolvedSenderTransportPeerId,
      senderKeyPackageId: resolvedSenderDevice?.keyPackageId,
      recipientPeerIds: recipientPeerIds,
      contentAuthorityVersion: strictSelected
          ? strictContext.authorityVersion
          : null,
      contentEventId: strictSelected ? resolvedMessageId : null,
      mediaManifest: strictMediaManifest,
    );
    inboxRetryPayload = strictSelected && recipientPeerIds.isNotEmpty
        ? jsonEncode(<String, Object?>{
            'groupId': groupId,
            'message': replayEnvelope,
            'custodyContract': ackOrExpiryInboxCustodyContract,
            'custodyKind': groupContentCustodyKind,
            'recipientPeerIds': recipientPeerIds,
          })
        : strictSelected
        ? null
        : jsonEncode({
            'groupId': groupId,
            'message': replayEnvelope,
            'recipientPeerIds': recipientPeerIds,
          });
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_REPLAY_ENVELOPE_FAILED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': e.toString(),
      },
    );
    if (strictSelected) {
      emitGroupSendTiming(
        outcome: 'unauthorized',
        details: {'reason': 'strict_group_content_crypto_failed'},
      );
      return (SendGroupMessageResult.unauthorized, null);
    }
  }

  // 4. Pre-persist outgoing row with status 'sending' BEFORE bridge call
  final prePersistMessage = GroupMessage(
    id: resolvedMessageId,
    groupId: groupId,
    senderPeerId: senderPeerId,
    transportPeerId: resolvedSenderTransportPeerId,
    senderUsername: senderUsername,
    text: sanitizedText,
    timestamp: now,
    lastSendAttemptAt: sendAttemptAt,
    quotedMessageId: quotedMessageId,
    logicalDeliveryId: resolvedLogicalDeliveryId,
    keyGeneration: keyEpoch,
    isForwarded: isForwarded,
    privateMediaPolicy: privateMediaPolicy,
    status: strictSelected ? GroupMessage.statusQueuedOffline : 'sending',
    isIncoming: false,
    createdAt: now,
    wireEnvelope: strictSelected ? inboxPayload : wireEnvelope,
    inboxStored: false,
    inboxRetryPayload: inboxRetryPayload,
  );
  final strictEventPayload = strictSelected
      ? buildLocalProtectedGroupContentEventPayload(
          replayEnvelope: replayEnvelope!,
          payload: Map<String, Object?>.from(
            jsonDecode(inboxPayload) as Map<String, dynamic>,
          ),
        )
      : null;
  final strictSourceEventId = strictSelected
      ? localProtectedGroupMessageSourceEventId(resolvedMessageId)
      : null;
  final strictSourceTimestamp = strictSelected
      ? fixedGroupContentUtc(now)
      : null;

  final stampedGroupMediaAttachments =
      groupMediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false) ??
      const <MediaAttachment>[];
  final preExistingMessage = await msgRepo.getMessage(resolvedMessageId);
  var strictDurableOwnerCommitted = false;
  if (expectedDispatchParent != null &&
      (preExistingMessage == null ||
          !sameExactGroupPrivateMediaDispatchParent(
            preExistingMessage,
            expectedDispatchParent,
          ))) {
    emitGroupSendTiming(
      outcome: 'unauthorized',
      details: {'reason': 'private_expected_parent_drifted_before_persist'},
    );
    return (SendGroupMessageResult.unauthorized, preExistingMessage);
  }
  try {
    Future<void> persistCandidate() async {
      if (!strictSelected) {
        if (!legacyMembershipActionPhaseHeld ||
            !isGroupMembershipActionPhaseHeld(groupId)) {
          throw StateError(
            'legacy group send membership action phase was not held',
          );
        }
      } else {
        final recheckedGroup = await groupRepo.getGroup(groupId);
        final recheckedKey = await groupRepo.getLatestKey(groupId);
        final recheckedMembership = await _loadGroupSendMembership(
          groupRepo: groupRepo,
          groupId: groupId,
          senderPeerId: senderPeerId,
          membershipCutoff: membershipCutoff,
          inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
        );
        GroupMember? recheckedSender;
        for (final candidate in recheckedMembership.members) {
          if (candidate.peerId == senderPeerId) recheckedSender = candidate;
        }
        final currentResolution = recheckedSender == null
            ? const (
                kind: GroupContentAuthoringResolutionKind.refuse,
                context: null,
              )
            : await resolveGroupContentAuthoring(
                resolverOwner: groupRepo,
                groupId: groupId,
                senderPeerId: senderPeerId,
                senderPublicKey: senderPublicKey,
                senderMember: recheckedSender,
                senderDeviceId: senderDeviceId,
                senderTransportPeerId: senderTransportPeerId,
                explicitContext: groupContentAuthoring,
              );
        final authorityShapeMatches =
            currentResolution.kind ==
                GroupContentAuthoringResolutionKind.strict &&
            currentResolution.context != null &&
            sameGroupContentAuthoringContext(
              strictContext,
              currentResolution.context!,
            );
        final senderRoleMatches =
            recheckedSender != null &&
            (recheckedGroup?.type != GroupType.announcement ||
                (recheckedGroup?.myRole == GroupRole.admin &&
                    recheckedSender.role == MemberRole.admin));
        if (recheckedGroup == null ||
            recheckedGroup.selfRemovedAt != null ||
            recheckedGroup.isDissolved ||
            recheckedKey?.keyGeneration != keyEpoch ||
            !senderRoleMatches ||
            !authorityShapeMatches ||
            (currentAuthorityCheck != null && !await currentAuthorityCheck()) ||
            !_sameStrictPhysicalAuthority(
              after: recheckedMembership.members,
              eligibleLogicalPeerIds: recheckedMembership.recipientPeerIds,
              senderPeerId: senderPeerId,
              senderTransportPeerId: resolvedSenderTransportPeerId,
              expectedRecipients: recipientPeerIds,
              senderDeviceId: resolvedSenderDeviceId,
              senderPublicKey: resolvedSenderDevicePublicKey,
            )) {
          throw StateError('group content authority drifted');
        }
        if (strictMediaManifest != null &&
            !await preparedGroupMediaManifest!.claimAndVerify(
              groupId: groupId,
              messageId: resolvedMessageId!,
              recipientPeerIds: recipientPeerIds,
            )) {
          throw StateError('group media manifest durable authority refused');
        }
      }

      if (strictSelected && recipientPeerIds.isEmpty) {
        if (msgRepo is! GroupMessageStrictLocalTerminalRepository ||
            !await (msgRepo as GroupMessageStrictLocalTerminalRepository)
                .stageAndCompleteStrictLocalContent(
                  prePersistMessage,
                  sourcePeerId: senderPeerId,
                  sourceEventId: strictSourceEventId!,
                  sourceTimestamp: strictSourceTimestamp!,
                  eventPayload: strictEventPayload!,
                )) {
          throw StateError('strict local message terminal commit rejected');
        }
        strictDurableOwnerCommitted = true;
        final terminal = await msgRepo.getMessage(prePersistMessage.id);
        if (terminal == null ||
            terminal.status != 'sent' ||
            !terminal.inboxStored ||
            terminal.inboxRetryPayload != null) {
          throw StateError('strict local message terminal readback rejected');
        }
        return;
      }
      if (strictSelected) {
        if (msgRepo is! GroupMessageStrictPreparedRepository ||
            !await (msgRepo as GroupMessageStrictPreparedRepository)
                .stageStrictContentPrepared(
                  prePersistMessage,
                  sourcePeerId: senderPeerId,
                  sourceEventId:
                      localPreparedProtectedGroupMessageSourceEventId(
                        resolvedMessageId!,
                      ),
                  sourceTimestamp: strictSourceTimestamp!,
                  preparedEventPayload:
                      buildLocalProtectedGroupContentPreparedEventPayload(
                        eventPayload: strictEventPayload!,
                        ownerKind: 'group_message',
                        ownerId: resolvedMessageId,
                        ownerStatus: prePersistMessage.status,
                        inboxRetryPayload: inboxRetryPayload!,
                      ),
                )) {
          throw StateError('strict message prepared commit rejected');
        }
        strictDurableOwnerCommitted = true;
        final prepared = await msgRepo.getMessage(prePersistMessage.id);
        if (!_isExpectedDurablePrePersistMessage(prepared, prePersistMessage)) {
          throw StateError('strict message prepared readback rejected');
        }
        return;
      }

      await _persistOutgoingMedia(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: stampedGroupMediaAttachments,
      );
      final mediaWereDurableBeforeParent =
          await _areExpectedOutgoingMediaDurable(
            mediaAttachmentRepo: mediaAttachmentRepo,
            messageId: prePersistMessage.id,
            expected: stampedGroupMediaAttachments,
          );
      if (!mediaWereDurableBeforeParent) {
        throw StateError('outgoing group media pre-persist was rejected');
      }
      if (expectedDispatchParent != null) {
        final currentParent = await msgRepo.getMessage(prePersistMessage.id);
        if (currentParent == null ||
            !sameExactGroupPrivateMediaDispatchParent(
              currentParent,
              expectedDispatchParent,
            )) {
          throw StateError(
            'private expected parent drifted during persistence',
          );
        }
      }
      await msgRepo.saveMessage(prePersistMessage);
      final durableMessage = await msgRepo.getMessage(prePersistMessage.id);
      final mediaAreDurable = await _areExpectedOutgoingMediaDurable(
        mediaAttachmentRepo: mediaAttachmentRepo,
        messageId: prePersistMessage.id,
        expected: stampedGroupMediaAttachments,
      );
      if (!_isExpectedDurablePrePersistMessage(
            durableMessage,
            prePersistMessage,
          ) ||
          !mediaAreDurable) {
        throw StateError(
          'outgoing group parent/media pre-persist was rejected',
        );
      }
    }

    await runGroupAuthorityPhaseIfNeeded(
      groupId: groupId,
      authorityPhaseHeld:
          legacyMembershipActionPhaseHeld || isGroupAuthorityPhaseHeld(groupId),
      action: persistCandidate,
    );
  } catch (error) {
    if (strictDurableOwnerCommitted) {
      prepareStopwatch.stop();
      prepareMs = prepareStopwatch.elapsedMilliseconds;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_STRICT_DURABLE_HANDOFF_RETAINED',
        details: {
          'messageId': _diagnosticPrefix(resolvedMessageId),
          'error': error.toString(),
        },
      );
      emitGroupSendTiming(outcome: 'strict_durable_handoff_retained');
      return (SendGroupMessageResult.queuedOffline, prePersistMessage);
    }
    try {
      await _rollbackRejectedOutgoingParent(
        msgRepo: msgRepo,
        preExistingMessage: preExistingMessage,
        expectedAttempt: prePersistMessage,
      );
    } catch (rollbackError) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_PRE_PERSIST_PARENT_ROLLBACK_FAILED',
        details: {
          'messageId': _diagnosticPrefix(resolvedMessageId),
          'error': rollbackError.toString(),
        },
      );
    }
    if (preExistingMessage == null) {
      try {
        await _rollbackNewOutgoingMedia(
          mediaAttachmentRepo: mediaAttachmentRepo,
          messageId: resolvedMessageId,
          attachments: stampedGroupMediaAttachments,
        );
      } catch (rollbackError) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_SEND_MSG_PRE_PERSIST_ROLLBACK_FAILED',
          details: {
            'messageId': _diagnosticPrefix(resolvedMessageId),
            'error': rollbackError.toString(),
          },
        );
      }
    }
    prepareStopwatch.stop();
    prepareMs = prepareStopwatch.elapsedMilliseconds;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_PRE_PERSIST_FAILED',
      details: {
        'messageId': _diagnosticPrefix(resolvedMessageId),
        'error': error.toString(),
      },
    );
    emitGroupSendTiming(outcome: 'pre_persist_failed');
    return (SendGroupMessageResult.error, preExistingMessage);
  }
  prepareStopwatch.stop();
  prepareMs = prepareStopwatch.elapsedMilliseconds;

  if (privateMediaPolicy.isPrivate) {
    final qualification = await qualifyCurrentPrivateGroupMediaSend(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      expectedParent: prePersistMessage,
      senderPeerId: senderPeerId,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      includeSenderPeerIdInDurableRecipients:
          includeSenderPeerIdInDurableRecipients,
    );
    if (qualification == null ||
        !sameGroupPrivateMediaRecipientPeerIds(
          recipientPeerIds,
          qualification.recipientPeerIds,
        )) {
      final failedPrivateMessage = prePersistMessage.copyWith(status: 'failed');
      await msgRepo.saveMessage(failedPrivateMessage);
      emitGroupSendTiming(
        outcome: 'unauthorized',
        details: {'reason': 'private_requalification_failed'},
      );
      return (SendGroupMessageResult.unauthorized, failedPrivateMessage);
    }
  }

  if (strictSelected) {
    Future<bool> strictAuthorityMatchesAssumingPhase() async {
      final currentGroup = await groupRepo.getGroup(groupId);
      final currentKey = await groupRepo.getLatestKey(groupId);
      final currentMembership = await _loadGroupSendMembership(
        groupRepo: groupRepo,
        groupId: groupId,
        senderPeerId: senderPeerId,
        membershipCutoff: membershipCutoff,
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      );
      GroupMember? currentSender;
      for (final candidate in currentMembership.members) {
        if (candidate.peerId == senderPeerId) currentSender = candidate;
      }
      if (currentGroup == null ||
          currentGroup.selfRemovedAt != null ||
          currentGroup.isDissolved ||
          currentKey?.keyGeneration != keyEpoch ||
          currentSender == null ||
          (currentGroup.type == GroupType.announcement &&
              (currentGroup.myRole != GroupRole.admin ||
                  currentSender.role != MemberRole.admin))) {
        return false;
      }
      final resolution = await resolveGroupContentAuthoring(
        resolverOwner: groupRepo,
        groupId: groupId,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderMember: currentSender,
        senderDeviceId: senderDeviceId,
        senderTransportPeerId: senderTransportPeerId,
        explicitContext: groupContentAuthoring,
      );
      return resolution.kind == GroupContentAuthoringResolutionKind.strict &&
          resolution.context != null &&
          sameGroupContentAuthoringContext(
            strictContext,
            resolution.context!,
          ) &&
          _sameStrictPhysicalAuthority(
            after: currentMembership.members,
            eligibleLogicalPeerIds: currentMembership.recipientPeerIds,
            senderPeerId: senderPeerId,
            senderTransportPeerId: resolvedSenderTransportPeerId,
            expectedRecipients: recipientPeerIds,
            senderDeviceId: resolvedSenderDeviceId,
            senderPublicKey: resolvedSenderDevicePublicKey,
          ) &&
          (currentAuthorityCheck == null || await currentAuthorityCheck());
    }

    Future<bool> currentStrictAuthorityMatches() => runGroupAuthorityPhase(
      groupId: groupId,
      action: strictAuthorityMatchesAssumingPhase,
    );
    Future<bool> commitIfStrictAuthorityMatches(
      Future<bool> Function() mutation,
    ) => runGroupAuthorityPhase(
      groupId: groupId,
      action: () async {
        if (!await strictAuthorityMatchesAssumingPhase()) return false;
        return mutation();
      },
    );
    if (recipientPeerIds.isEmpty) {
      final terminal = await msgRepo.getMessage(resolvedMessageId);
      if (terminal == null ||
          terminal.status != 'sent' ||
          !terminal.inboxStored ||
          terminal.inboxRetryPayload != null) {
        emitGroupSendTiming(outcome: 'strict_local_terminal_pending');
        return (SendGroupMessageResult.queuedOffline, prePersistMessage);
      }
      emitGroupSendTiming(outcome: 'strict_local_terminal');
      return (SendGroupMessageResult.success, terminal);
    }
    final completed = await _driveStrictGroupMessageCustody(
      repository: msgRepo,
      store: strictContext.inboxStore!,
      expected: prePersistMessage,
      sourcePeerId: senderPeerId,
      sourceEventId: strictSourceEventId!,
      sourceTimestamp: strictSourceTimestamp!,
      eventPayload: strictEventPayload!,
      currentAuthorityMatches: currentStrictAuthorityMatches,
      commitIfAuthorityMatches: commitIfStrictAuthorityMatches,
    );
    final current = await msgRepo.getMessage(resolvedMessageId);
    emitGroupSendTiming(
      outcome: completed ? 'strict_custody_complete' : 'strict_custody_pending',
    );
    return (
      completed
          ? SendGroupMessageResult.success
          : SendGroupMessageResult.queuedOffline,
      current ?? prePersistMessage,
    );
  }

  final reliableStopwatch = Stopwatch()..start();
  Map<String, dynamic> reliableResult;
  try {
    reliableResult = await callGroupSendReliable(
      bridge,
      groupId: groupId,
      text: sanitizedText,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername,
      senderDeviceId: resolvedSenderDeviceId,
      senderTransportPeerId: resolvedSenderTransportPeerId,
      senderDevicePublicKey: resolvedSenderDevicePublicKey,
      senderKeyPackageId: resolvedSenderDevice?.keyPackageId,
      messageId: resolvedMessageId,
      logicalDeliveryId: resolvedLogicalDeliveryId,
      groupName: resolvedGroupName,
      timestamp: now,
      quotedMessageId: quotedMessageId,
      media: mediaJson,
      isForwarded: isForwarded,
      privateMediaPolicy: privateMediaPolicy.toWireExtras(),
      recipientPeerIds: recipientPeerIds,
      preserveRecipientPeerIds: true,
    );
  } catch (e) {
    reliableResult = {
      'ok': false,
      'errorCode': 'RELIABLE_SEND_FAILED',
      'errorMessage': e.toString(),
    };
  }
  reliableStopwatch.stop();
  if (!_reliableGroupSendUnavailable(reliableResult)) {
    publishMs = reliableStopwatch.elapsedMilliseconds;
    final reliableOk = reliableResult['ok'] == true;
    final publishSucceeded = reliableResult['publishSucceeded'] == true;
    final inboxOk = reliableResult['inboxStored'] == true;
    final topicPeers =
        _intResultField(reliableResult, 'topicPeerCount') ??
        _intResultField(reliableResult, 'topicPeers');
    // GAP 2: prefer the post-publish connected-topic-peer count (the Go recount
    // that captures peers which subscribed during the pre-publish settle window
    // and were delivered to by floodPublish) as the delivery signal; fall back
    // to the pre-publish mesh snapshot when the field is absent (older Go
    // binary) — byte-equivalent to today until the Go half ships.
    final connectedTopicPeers = _intResultField(
      reliableResult,
      'connectedTopicPeerCount',
    );
    final effectiveTopicPeers = connectedTopicPeers ?? topicPeers;
    final reliableExpectedRecipientCount =
        _intResultField(reliableResult, 'expectedRecipientCount') ??
        expectedRecipientCount;
    final retryPayload = inboxOk
        ? null
        : _nativeReliableInboxRetryPayload(
            groupId: groupId,
            result: reliableResult,
            fallback: prePersistMessage.inboxRetryPayload,
          );
    final reliableTimedOut = _reliableGroupSendTimedOut(reliableResult);
    final publishWithoutCustody = _reliablePublishSucceededWithoutCustody(
      reliableOk: reliableOk,
      publishSucceeded: publishSucceeded,
      inboxOk: inboxOk,
      topicPeers: effectiveTopicPeers,
      expectedRecipientCount: reliableExpectedRecipientCount,
    );

    if (reliableTimedOut || publishWithoutCustody) {
      // 210b: the two shapes are NOT the same lane. A bridge timeout is
      // genuinely in-doubt (the publish may have gone out) → 'pending' (amber
      // tick). Publish-without-custody is definitive — zero live topic peers
      // AND no relay custody, i.e. the realistic offline-device geometry —
      // → durable 'queued_offline' (clock + offline snackbar), self-healed by
      // the repush lane on reconnect. The shapes are mutually exclusive
      // (timeout ⇒ ok:false; without-custody ⇒ ok:true).
      final inDoubtMessage = _withPrivateMediaCustodyAnchor(
        prePersistMessage.copyWith(
          status: publishWithoutCustody
              ? GroupMessage.statusQueuedOffline
              : 'pending',
          wireEnvelope: reliableTimedOut
              ? prePersistMessage.wireEnvelope
              : null,
          inboxStored: inboxOk,
          inboxRetryPayload: retryPayload,
        ),
        hasCustody: inboxOk,
        anchoredAt: currentPrivateMediaNowMs(),
      );
      await msgRepo.saveMessage(inDoubtMessage);
      _signalPrivateMediaAnchor(prePersistMessage, inDoubtMessage);
      await _persistOutgoingMedia(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: groupMediaAttachments
            ?.map(
              (attachment) => attachment.copyWith(messageId: resolvedMessageId),
            )
            .toList(growable: false),
      );

      final reason = reliableTimedOut
          ? 'bridge_timeout'
          : 'live_publish_without_custody';
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_RELIABLE_IN_DOUBT',
        details: {
          'messageId': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
          'reason': reason,
          'deliveryMode': reliableResult['deliveryMode'],
          ..._groupPublishFanoutEvidence(
            topicPeers: topicPeers,
            expectedRecipientCount: reliableExpectedRecipientCount,
            inboxOk: inboxOk,
          ),
        },
      );
      emitGroupSendTiming(
        outcome: 'reliable_in_doubt',
        details: {
          'status': inDoubtMessage.status,
          'reason': reason,
          'deliveryMode': reliableResult['deliveryMode'],
          ..._groupPublishFanoutEvidence(
            topicPeers: topicPeers,
            expectedRecipientCount: reliableExpectedRecipientCount,
            inboxOk: inboxOk,
          ),
        },
      );
      return (
        publishWithoutCustody
            ? SendGroupMessageResult.queuedOffline
            : SendGroupMessageResult.success,
        inDoubtMessage,
      );
    }

    if (!reliableOk || (!publishSucceeded && !inboxOk)) {
      final failedMessage = _withPrivateMediaCustodyAnchor(
        prePersistMessage.copyWith(
          status: 'failed',
          inboxStored: inboxOk,
          inboxRetryPayload: retryPayload,
        ),
        // Relay inbox acceptance is custody even when the paired live publish
        // reports a definitive error. A disappearing sender copy must start
        // its one-time local clock at that custody boundary.
        hasCustody: inboxOk,
        anchoredAt: currentPrivateMediaNowMs(),
      );
      await msgRepo.saveMessage(failedMessage);
      _signalPrivateMediaAnchor(prePersistMessage, failedMessage);
      emitGroupSendTiming(
        outcome: 'reliable_failed',
        details: {
          'deliveryMode': reliableResult['deliveryMode'],
          ..._groupPublishFanoutEvidence(
            topicPeers: topicPeers,
            expectedRecipientCount: reliableExpectedRecipientCount,
            inboxOk: inboxOk,
          ),
        },
      );
      return (SendGroupMessageResult.error, failedMessage);
    }

    final canMarkSent =
        reliableExpectedRecipientCount <= 0 ||
        inboxOk ||
        (publishSucceeded && (effectiveTopicPeers ?? 0) > 0);
    if (!canMarkSent && (effectiveTopicPeers ?? 0) <= 0) {
      await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
      final failedMessage = prePersistMessage.copyWith(
        status: 'failed',
        inboxStored: false,
        inboxRetryPayload: retryPayload,
      );
      emitGroupSendTiming(
        outcome: 'zero_peers_inbox_failed',
        details: _groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: reliableExpectedRecipientCount,
          inboxOk: false,
        ),
      );
      return (SendGroupMessageResult.error, failedMessage);
    }

    final finalMessage = _withPrivateMediaCustodyAnchor(
      prePersistMessage.copyWith(
        status: canMarkSent ? 'sent' : 'pending',
        wireEnvelope: null,
        inboxStored: inboxOk,
        inboxRetryPayload: retryPayload,
      ),
      hasCustody: canMarkSent,
      anchoredAt: currentPrivateMediaNowMs(),
    );
    await msgRepo.saveMessage(finalMessage);
    _signalPrivateMediaAnchor(prePersistMessage, finalMessage);
    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: groupMediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );
    emitFlowEvent(
      layer: 'FL',
      event: topicPeers == 0 && inboxOk
          ? 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS'
          : 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'deliveryMode': reliableResult['deliveryMode'],
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: reliableExpectedRecipientCount,
          inboxOk: inboxOk,
        ),
      },
    );
    emitGroupSendTiming(
      outcome: topicPeers == 0 && inboxOk ? 'success_no_peers' : 'success',
      details: {
        'status': finalMessage.status,
        'deliveryMode': reliableResult['deliveryMode'],
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: reliableExpectedRecipientCount,
          inboxOk: inboxOk,
        ),
      },
    );
    return (
      topicPeers == 0 && inboxOk
          ? SendGroupMessageResult.successNoPeers
          : SendGroupMessageResult.success,
      finalMessage,
    );
  }

  // An unavailable reliable command enters a second bridge dispatch path.
  // Re-run both current authority and exact recipient-set comparison after the
  // awaited command so a revocation during capability fallback cannot publish
  // or store the already-built private replay envelope.
  if (privateMediaPolicy.isPrivate) {
    final fallbackQualification = await qualifyCurrentPrivateGroupMediaSend(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      expectedParent: prePersistMessage,
      senderPeerId: senderPeerId,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      includeSenderPeerIdInDurableRecipients:
          includeSenderPeerIdInDurableRecipients,
    );
    if (fallbackQualification == null ||
        !sameGroupPrivateMediaRecipientPeerIds(
          recipientPeerIds,
          fallbackQualification.recipientPeerIds,
        )) {
      final failedPrivateMessage = prePersistMessage.copyWith(status: 'failed');
      await msgRepo.saveMessage(failedPrivateMessage);
      emitGroupSendTiming(
        outcome: 'unauthorized',
        details: {'reason': 'private_fallback_requalification_failed'},
      );
      return (SendGroupMessageResult.unauthorized, failedPrivateMessage);
    }
  }

  // 5. Start publish + inbox store concurrently
  final publishStopwatch = Stopwatch()..start();
  final publishFuture = callGroupPublish(
    bridge,
    groupId: groupId,
    text: sanitizedText,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderUsername: senderUsername,
    senderDeviceId: resolvedSenderDeviceId,
    senderTransportPeerId: resolvedSenderTransportPeerId,
    senderDevicePublicKey: resolvedSenderDevicePublicKey,
    senderKeyPackageId: resolvedSenderDevice?.keyPackageId,
    messageId: resolvedMessageId,
    logicalDeliveryId: resolvedLogicalDeliveryId,
    groupName: resolvedGroupName,
    timestamp: now,
    quotedMessageId: quotedMessageId,
    media: mediaJson,
    isForwarded: isForwarded,
    privateMediaPolicy: privateMediaPolicy.toWireExtras(),
  );
  bool? inboxResult;
  final inboxStopwatch = Stopwatch()..start();
  final inboxFuture =
      (replayEnvelope == null
              ? Future<bool>.value(false)
              : _tryInboxStore(
                  bridge: bridge,
                  groupId: groupId,
                  inboxPayload: replayEnvelope,
                  recipientPeerIds: recipientPeerIds,
                  preserveRecipientPeerIds: true,
                ))
          .then((value) {
            inboxStopwatch.stop();
            inboxMs = inboxStopwatch.elapsedMilliseconds;
            inboxResult = value;
            return value;
          });

  // 6. Await publish — determines success/failure
  Map<String, dynamic>? publishResult;
  bool publishOk = false;
  String? publishErrorCode;

  try {
    publishResult = await publishFuture;
    publishStopwatch.stop();
    publishMs = publishStopwatch.elapsedMilliseconds;
    publishOk = publishResult['ok'] == true;
    publishErrorCode = publishResult['errorCode']?.toString();

    if (!publishOk) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_ERROR',
        details: {
          'groupId': _diagnosticPrefix(groupId),
          'keyEpoch': keyEpoch,
          'messageId': _diagnosticPrefix(resolvedMessageId),
          'errorCode': publishErrorCode,
        },
      );
    }
  } catch (e) {
    publishStopwatch.stop();
    publishMs = publishStopwatch.elapsedMilliseconds;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ERROR',
      details: {'error': e.toString()},
    );
  }

  // 7. Apply result matrix. Only block on durable inbox when live publish
  // cannot confirm delivery.
  if (!publishOk) {
    final inboxOk = await inboxFuture;
    if (publishErrorCode == 'BRIDGE_TIMEOUT' && inboxOk) {
      // The foreground publish confirmation timed out, but the relay inbox
      // accepted custody for delivery. Surface this as a successful durable
      // send instead of a false failure on the sender.
      final sentMessage = _withPrivateMediaCustodyAnchor(
        prePersistMessage.copyWith(
          status: 'sent',
          wireEnvelope: null,
          inboxStored: true,
          inboxRetryPayload: null,
        ),
        hasCustody: true,
        anchoredAt: currentPrivateMediaNowMs(),
      );
      await msgRepo.saveMessage(sentMessage);
      _signalPrivateMediaAnchor(prePersistMessage, sentMessage);

      await _persistOutgoingMedia(
        mediaAttachmentRepo: mediaAttachmentRepo,
        attachments: groupMediaAttachments
            ?.map(
              (attachment) => attachment.copyWith(messageId: resolvedMessageId),
            )
            .toList(growable: false),
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_SEND_MSG_USE_CASE_TIMEOUT_INBOX_FALLBACK',
        details: {
          'messageId': resolvedMessageId.length > 8
              ? resolvedMessageId.substring(0, 8)
              : resolvedMessageId,
        },
      );
      emitGroupSendTiming(
        outcome: 'success',
        details: {
          'status': sentMessage.status,
          'via': 'inbox_timeout_fallback',
        },
      );
      return (SendGroupMessageResult.success, sentMessage);
    }

    // Publish failed — preserve publish retry inputs while persisting the
    // observed inbox outcome from the same in-flight inbox future.
    final failedMessage = _withPrivateMediaCustodyAnchor(
      prePersistMessage.copyWith(
        status: 'failed',
        inboxStored: inboxOk,
        inboxRetryPayload: inboxOk ? null : prePersistMessage.inboxRetryPayload,
      ),
      // The fallback inbox future is an independent durable-custody result.
      // Do not lose its disappearing-media anchor merely because live publish
      // failed with a non-timeout error.
      hasCustody: inboxOk,
      anchoredAt: currentPrivateMediaNowMs(),
    );
    await msgRepo.saveMessage(failedMessage);
    _signalPrivateMediaAnchor(prePersistMessage, failedMessage);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_PUBLISH_FAILED',
      details: {
        'groupId': _diagnosticPrefix(groupId),
        'keyEpoch': keyEpoch,
        'messageId': _diagnosticPrefix(resolvedMessageId),
        'errorCode': publishErrorCode,
        'inboxOk': inboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'publish_failed',
      details: {'inboxStored': inboxOk},
    );
    return (SendGroupMessageResult.error, failedMessage);
  }

  // Publish succeeded — read topicPeers as live topic fanout only.
  final topicPeers = publishResult?.containsKey('topicPeers') == true
      ? publishResult!['topicPeers'] as int?
      : null;

  if (topicPeers == null) {
    // Missing topicPeers key — legacy success (backward compat, assume peers > 0)
    final resolvedInboxOk = inboxResult ?? await inboxFuture;
    final finalMessage = _withPrivateMediaCustodyAnchor(
      prePersistMessage.copyWith(
        status: resolvedInboxOk == true ? 'sent' : 'pending',
        wireEnvelope: null,
        inboxStored: resolvedInboxOk == true,
        inboxRetryPayload: resolvedInboxOk == true
            ? null
            : prePersistMessage.inboxRetryPayload,
      ),
      // A successful legacy publish is live custody even when the old bridge
      // omitted its peer-count field.
      hasCustody: true,
      anchoredAt: currentPrivateMediaNowMs(),
    );
    await msgRepo.saveMessage(finalMessage);
    _signalPrivateMediaAnchor(prePersistMessage, finalMessage);

    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: groupMediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'legacy': true,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
        'inboxOk': resolvedInboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'success',
      details: {
        'status': finalMessage.status,
        'legacy': true,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
      },
    );
    return (SendGroupMessageResult.success, finalMessage);
  }

  if (topicPeers > 0) {
    // Normal success: explicit live peers make the message visibly sent.
    // Offline inbox custody remains tracked separately for retry.
    final resolvedInboxOk = inboxResult ?? await inboxFuture;
    final finalMessage = _withPrivateMediaCustodyAnchor(
      prePersistMessage.copyWith(
        status: 'sent',
        wireEnvelope: null,
        inboxStored: resolvedInboxOk == true,
        inboxRetryPayload: resolvedInboxOk == true
            ? null
            : prePersistMessage.inboxRetryPayload,
      ),
      hasCustody: true,
      anchoredAt: currentPrivateMediaNowMs(),
    );
    await msgRepo.saveMessage(finalMessage);
    _signalPrivateMediaAnchor(prePersistMessage, finalMessage);

    await _persistOutgoingMedia(
      mediaAttachmentRepo: mediaAttachmentRepo,
      attachments: groupMediaAttachments
          ?.map(
            (attachment) => attachment.copyWith(messageId: resolvedMessageId),
          )
          .toList(growable: false),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
        'inboxOk': resolvedInboxOk,
      },
    );
    emitGroupSendTiming(
      outcome: 'success',
      details: {
        'status': finalMessage.status,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: resolvedInboxOk,
        ),
      },
    );
    return (SendGroupMessageResult.success, finalMessage);
  }

  // topicPeers == 0
  final inboxOk = await inboxFuture;
  if (inboxOk) {
    // 0-peer + inbox OK → successNoPeers, but persist as a successful send.
    // The relay inbox has already accepted durable delivery for offline peers,
    // so a permanent "pending" clock is misleading in the UI.
    final sentMessage = _withPrivateMediaCustodyAnchor(
      prePersistMessage.copyWith(
        status: 'sent',
        wireEnvelope: null,
        inboxStored: true,
        inboxRetryPayload: null,
      ),
      hasCustody: true,
      anchoredAt: currentPrivateMediaNowMs(),
    );
    await msgRepo.saveMessage(sentMessage);
    _signalPrivateMediaAnchor(prePersistMessage, sentMessage);

    // Save media attachments
    if (groupMediaAttachments != null && mediaAttachmentRepo != null) {
      for (final a in groupMediaAttachments) {
        await mediaAttachmentRepo.saveAttachment(
          a.copyWith(messageId: resolvedMessageId),
          owner: MediaOwnerLane.group,
        );
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        'status': sentMessage.status,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: true,
        ),
      },
    );
    emitGroupSendTiming(
      outcome: 'success_no_peers',
      details: {
        'status': sentMessage.status,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: true,
        ),
      },
    );
    return (SendGroupMessageResult.successNoPeers, sentMessage);
  } else {
    // 0-peer + inbox fail → error
    await msgRepo.updateMessageStatus(resolvedMessageId, 'failed');
    final failedMessage = prePersistMessage.copyWith(status: 'failed');

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SEND_MSG_USE_CASE_ZERO_PEERS_INBOX_FAILED',
      details: {
        'messageId': resolvedMessageId.length > 8
            ? resolvedMessageId.substring(0, 8)
            : resolvedMessageId,
        ..._groupPublishFanoutEvidence(
          topicPeers: topicPeers,
          expectedRecipientCount: expectedRecipientCount,
          inboxOk: false,
        ),
      },
    );
    emitGroupSendTiming(
      outcome: 'zero_peers_inbox_failed',
      details: _groupPublishFanoutEvidence(
        topicPeers: topicPeers,
        expectedRecipientCount: expectedRecipientCount,
        inboxOk: false,
      ),
    );
    return (SendGroupMessageResult.error, failedMessage);
  }
}
