import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';

class GroupSecurityStatusViewState {
  final bool hasCurrentKey;
  final int? keyEpoch;
  final DateTime? keyCreatedAt;
  final int memberCount;
  final int verifiedMemberCount;
  final int identityWarningCount;
  final int unverifiedMemberCount;

  const GroupSecurityStatusViewState({
    required this.hasCurrentKey,
    this.keyEpoch,
    this.keyCreatedAt,
    required this.memberCount,
    required this.verifiedMemberCount,
    required this.identityWarningCount,
    required this.unverifiedMemberCount,
  });

  factory GroupSecurityStatusViewState.fromSnapshot({
    required GroupKeyInfo? latestKey,
    required int memberCount,
    required Iterable<GroupMemberIdentitySafety> memberSafety,
    int locallyVerifiedMemberCount = 0,
  }) {
    final safetyList = memberSafety.toList(growable: false);
    final identityWarnings = safetyList
        .where((safety) => safety.identityChanged)
        .length;
    final locallyVerifiedMembers = locallyVerifiedMemberCount < 0
        ? 0
        : locallyVerifiedMemberCount;
    final verifiedMembers =
        (safetyList.where((safety) => !safety.identityChanged).length +
                locallyVerifiedMembers)
            .clamp(0, memberCount)
            .toInt();
    final unverifiedMembers = memberCount - verifiedMembers - identityWarnings;

    return GroupSecurityStatusViewState(
      hasCurrentKey:
          latestKey != null && latestKey.encryptedKey.trim().isNotEmpty,
      keyEpoch: latestKey?.keyGeneration,
      keyCreatedAt: latestKey?.createdAt,
      memberCount: memberCount,
      verifiedMemberCount: verifiedMembers,
      identityWarningCount: identityWarnings,
      unverifiedMemberCount: unverifiedMembers < 0 ? 0 : unverifiedMembers,
    );
  }

  bool get hasKeyChangeWarning => hasCurrentKey && (keyEpoch ?? 0) > 1;

  bool get hasIdentityWarnings => identityWarningCount > 0;

  bool get hasUnverifiedMembers => unverifiedMemberCount > 0;

  String get encryptionLabel =>
      hasCurrentKey ? 'End-to-end encrypted' : 'Encryption pending';

  String get keyEpochLabel {
    if (!hasCurrentKey || keyEpoch == null) {
      return 'No group key on this device';
    }
    if (hasKeyChangeWarning) {
      return 'Group key changed to epoch $keyEpoch';
    }
    return 'Current key epoch $keyEpoch';
  }

  String get verificationLabel {
    if (memberCount <= 0) {
      return 'No members to verify';
    }
    if (identityWarningCount == 0 && unverifiedMemberCount == 0) {
      return 'All $memberCount ${_plural(memberCount, 'member')} verified';
    }
    return '$verifiedMemberCount of $memberCount ${_plural(memberCount, 'member')} verified';
  }

  String get verificationDetailLabel {
    if (identityWarningCount > 0) {
      return '$identityWarningCount ${_plural(identityWarningCount, 'member')} needs verification review';
    }
    if (unverifiedMemberCount > 0) {
      return '$unverifiedMemberCount ${_plural(unverifiedMemberCount, 'member')} not verified from saved contacts';
    }
    return 'No verification warnings';
  }

  String get compactEncryptionLabel {
    if (!hasCurrentKey || keyEpoch == null) {
      return encryptionLabel;
    }
    return 'Encrypted - key epoch $keyEpoch';
  }

  String get compactReviewLabel {
    if (identityWarningCount > 0) {
      return verificationDetailLabel;
    }
    if (hasKeyChangeWarning) {
      return keyEpochLabel;
    }
    return verificationLabel;
  }

  static String _plural(int count, String singular) =>
      count == 1 ? singular : '${singular}s';
}
