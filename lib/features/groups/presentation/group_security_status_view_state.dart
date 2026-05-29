import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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

  bool get shouldShowCompactStatus =>
      !hasCurrentKey ||
      hasKeyChangeWarning ||
      hasIdentityWarnings ||
      hasUnverifiedMembers;

  String encryptionLabel(AppLocalizations l10n) => hasCurrentKey
      ? l10n.group_security_encrypted
      : l10n.group_security_pending;

  String keyEpochLabel(AppLocalizations l10n) {
    if (!hasCurrentKey || keyEpoch == null) {
      return l10n.group_security_no_key;
    }
    if (hasKeyChangeWarning) {
      return l10n.group_security_key_changed(keyEpoch!);
    }
    return l10n.group_security_current_key_epoch(keyEpoch!);
  }

  String verificationLabel(AppLocalizations l10n) {
    if (memberCount <= 0) {
      return l10n.group_security_no_members;
    }
    if (identityWarningCount == 0 && unverifiedMemberCount == 0) {
      return l10n.group_security_all_members_verified(memberCount);
    }
    return l10n.group_security_members_verified(
      verifiedMemberCount,
      memberCount,
    );
  }

  String verificationDetailLabel(AppLocalizations l10n) {
    if (identityWarningCount > 0) {
      return l10n.group_security_members_need_review(identityWarningCount);
    }
    if (unverifiedMemberCount > 0) {
      return l10n.group_security_members_unverified(unverifiedMemberCount);
    }
    return l10n.group_security_no_warnings;
  }

  String compactEncryptionLabel(AppLocalizations l10n) {
    if (!hasCurrentKey || keyEpoch == null) {
      return encryptionLabel(l10n);
    }
    return l10n.group_security_compact_encrypted_epoch(keyEpoch!);
  }

  String compactReviewLabel(AppLocalizations l10n) {
    if (identityWarningCount > 0) {
      return verificationDetailLabel(l10n);
    }
    if (hasKeyChangeWarning) {
      return keyEpochLabel(l10n);
    }
    return verificationLabel(l10n);
  }
}
