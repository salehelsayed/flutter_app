import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_safety_number.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

class GroupMemberIdentitySafety {
  final String currentSafetyNumber;
  final String savedSafetyNumber;
  final bool identityChanged;

  const GroupMemberIdentitySafety({
    required this.currentSafetyNumber,
    required this.savedSafetyNumber,
    required this.identityChanged,
  });

  static GroupMemberIdentitySafety? compare({
    required GroupMember member,
    required ContactModel? savedContact,
  }) {
    if (savedContact == null) {
      return null;
    }

    final currentPublicKey = _normalize(member.publicKey);
    final savedPublicKey = _normalize(savedContact.publicKey);
    if (currentPublicKey == null || savedPublicKey == null) {
      return null;
    }

    final currentMlKemPublicKey = _normalize(member.mlKemPublicKey);
    final savedMlKemPublicKey = _normalize(savedContact.mlKemPublicKey);
    final currentSafetyNumber = ContactSafetyNumber.build(
      peerId: member.peerId,
      publicKey: currentPublicKey,
      mlKemPublicKey: currentMlKemPublicKey,
    );
    final savedSafetyNumber = ContactSafetyNumber.build(
      peerId: savedContact.peerId,
      publicKey: savedPublicKey,
      mlKemPublicKey: savedMlKemPublicKey,
    );
    if (currentSafetyNumber == null || savedSafetyNumber == null) {
      return null;
    }

    return GroupMemberIdentitySafety(
      currentSafetyNumber: currentSafetyNumber,
      savedSafetyNumber: savedSafetyNumber,
      identityChanged:
          currentPublicKey != savedPublicKey ||
          currentMlKemPublicKey != savedMlKemPublicKey,
    );
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
