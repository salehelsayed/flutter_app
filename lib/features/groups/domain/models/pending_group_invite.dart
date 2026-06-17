import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

const pendingGroupInviteTtl = Duration(days: 7);

class PendingGroupInvite {
  final String groupId;
  final String inviteId;
  final String payloadJson;
  final String groupName;
  final GroupType groupType;
  final String? groupDescription;
  final String? avatarBlobId;
  final String? avatarMime;
  final String senderPeerId;
  final String senderUsername;

  /// The inviter's account-level ML-KEM public key, captured from the invite's
  /// membership-freshness proof at receive time. Lets a decline-ack be
  /// encrypted to a non-contact inviter (G1) without a contacts lookup.
  /// Nullable: legacy rows and invites without a freshness proof carry none.
  final String? mlKemPublicKey;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? metadataUpdatedAt;
  final DateTime receivedAt;
  final DateTime expiresAt;

  const PendingGroupInvite({
    required this.groupId,
    required this.inviteId,
    required this.payloadJson,
    required this.groupName,
    required this.groupType,
    this.groupDescription,
    this.avatarBlobId,
    this.avatarMime,
    required this.senderPeerId,
    required this.senderUsername,
    this.mlKemPublicKey,
    required this.createdBy,
    required this.createdAt,
    this.metadataUpdatedAt,
    required this.receivedAt,
    required this.expiresAt,
  });

  factory PendingGroupInvite.fromMap(Map<String, dynamic> map) {
    return PendingGroupInvite(
      groupId: map['group_id'] as String,
      inviteId: map['invite_id'] as String,
      payloadJson: map['payload_json'] as String,
      groupName: map['group_name'] as String,
      groupType: GroupType.fromValue(map['group_type'] as String),
      groupDescription: map['group_description'] as String?,
      avatarBlobId: map['avatar_blob_id'] as String?,
      avatarMime: map['avatar_mime'] as String?,
      senderPeerId: map['sender_peer_id'] as String,
      senderUsername: map['sender_username'] as String,
      mlKemPublicKey: map['inviter_mlkem_public_key'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      metadataUpdatedAt: map['metadata_updated_at'] != null
          ? DateTime.parse(map['metadata_updated_at'] as String)
          : null,
      receivedAt: DateTime.parse(map['received_at'] as String),
      expiresAt: DateTime.parse(map['expires_at'] as String),
    );
  }

  factory PendingGroupInvite.fromPayload(
    GroupInvitePayload payload, {
    required DateTime receivedAt,
    Duration ttl = pendingGroupInviteTtl,
  }) {
    final config = payload.groupConfig;
    final groupType = _parseGroupType(config['groupType'] as String?);
    final createdAt = _parseTimestamp(config['createdAt'] as String?);
    final metadataUpdatedAt = _parseOptionalTimestamp(
      config['metadataUpdatedAt'] as String?,
    );
    final resolvedReceivedAt = receivedAt.toUtc();
    final localExpiry = resolvedReceivedAt.add(ttl);
    final policyExpiry = payload.invitePolicy.expiresAt.toUtc();
    final expiresAt = policyExpiry.isBefore(localExpiry)
        ? policyExpiry
        : localExpiry;

    // The wire payload carries the inviter's ML-KEM key inside the membership
    // freshness proof's inviter snapshot (GroupMember.toConfigJson). Capture it
    // so a later decline-ack can encrypt to a non-contact inviter (G1).
    final inviterMlKemPublicKey = _inviterMlKemFromProof(
      payload.membershipFreshnessProof,
    );

    return PendingGroupInvite(
      groupId: payload.groupId,
      inviteId: payload.id,
      payloadJson: payload.toJson(),
      groupName: config['name'] as String? ?? 'Unnamed Group',
      groupType: groupType,
      groupDescription: config['description'] as String?,
      avatarBlobId: config['avatarBlobId'] as String?,
      avatarMime: config['avatarMime'] as String?,
      senderPeerId: payload.senderPeerId,
      senderUsername: payload.senderUsername,
      mlKemPublicKey: inviterMlKemPublicKey,
      createdBy: config['createdBy'] as String? ?? payload.senderPeerId,
      createdAt: createdAt,
      metadataUpdatedAt: metadataUpdatedAt,
      receivedAt: resolvedReceivedAt,
      expiresAt: expiresAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'group_id': groupId,
      'invite_id': inviteId,
      'payload_json': payloadJson,
      'group_name': groupName,
      'group_type': groupType.toValue(),
      'group_description': groupDescription,
      'avatar_blob_id': avatarBlobId,
      'avatar_mime': avatarMime,
      'sender_peer_id': senderPeerId,
      'sender_username': senderUsername,
      'inviter_mlkem_public_key': mlKemPublicKey,
      'created_by': createdBy,
      'created_at': createdAt.toUtc().toIso8601String(),
      'metadata_updated_at': metadataUpdatedAt?.toUtc().toIso8601String(),
      'received_at': receivedAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  GroupInvitePayload? toPayload() => GroupInvitePayload.fromJson(payloadJson);

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());

  static String? _inviterMlKemFromProof(
    GroupInviteMembershipFreshnessProof? proof,
  ) {
    if (proof == null) {
      return null;
    }
    final raw = proof.inviterMemberSnapshot['mlKemPublicKey'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw;
    }
    return null;
  }

  static GroupType _parseGroupType(String? value) {
    try {
      return GroupType.fromValue(value ?? 'chat');
    } catch (_) {
      return GroupType.chat;
    }
  }

  static DateTime _parseTimestamp(String? value) {
    if (value == null) {
      return DateTime.now().toUtc();
    }
    return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
  }

  static DateTime? _parseOptionalTimestamp(String? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}
