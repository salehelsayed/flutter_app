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
    // B4 per-device dimension. `null` (the default) keeps the exact account-level
    // v1 behaviour — devices are ignored on BOTH sides. Pass a list (the persisted
    // last-known device-set snapshot, possibly empty) to make the number + the
    // identityChanged flag device-aware: a member adding/swapping a device then
    // surfaces a warning even when the account keys are unchanged.
    List<GroupMemberDeviceIdentity>? savedDevices,
  }) {
    if (savedContact == null) {
      return null;
    }

    final currentPublicKey = _normalize(member.publicKey);
    final savedPublicKey = _normalize(savedContact.publicKey);
    if (currentPublicKey == null || savedPublicKey == null) {
      return null;
    }

    final useDeviceDimension = savedDevices != null;
    final currentDeviceFingerprints = useDeviceDimension
        ? _fingerprints(member.activeDevicesWithLegacyFallback())
        : const <String>[];
    final savedDeviceFingerprints = useDeviceDimension
        ? _fingerprints(savedDevices)
        : const <String>[];

    final currentMlKemPublicKey = _normalize(member.mlKemPublicKey);
    final savedMlKemPublicKey = _normalize(savedContact.mlKemPublicKey);
    final currentSafetyNumber = ContactSafetyNumber.build(
      peerId: member.peerId,
      publicKey: currentPublicKey,
      mlKemPublicKey: currentMlKemPublicKey,
      deviceFingerprints: currentDeviceFingerprints,
    );
    final savedSafetyNumber = ContactSafetyNumber.build(
      peerId: savedContact.peerId,
      publicKey: savedPublicKey,
      mlKemPublicKey: savedMlKemPublicKey,
      deviceFingerprints: savedDeviceFingerprints,
    );
    if (currentSafetyNumber == null || savedSafetyNumber == null) {
      return null;
    }

    return GroupMemberIdentitySafety(
      currentSafetyNumber: currentSafetyNumber,
      savedSafetyNumber: savedSafetyNumber,
      identityChanged:
          currentPublicKey != savedPublicKey ||
          currentMlKemPublicKey != savedMlKemPublicKey ||
          !_sameFingerprints(
            currentDeviceFingerprints,
            savedDeviceFingerprints,
          ),
    );
  }

  /// Sorted, stable per-device fingerprints (signing key + ML-KEM + keyPackage).
  static List<String> _fingerprints(List<GroupMemberDeviceIdentity> devices) {
    final fingerprints =
        devices
            .map(
              (device) =>
                  '${device.deviceSigningPublicKey.trim()}:'
                  '${device.mlKemPublicKey?.trim() ?? ''}:'
                  '${device.keyPackageId?.trim() ?? ''}',
            )
            .where((fingerprint) => fingerprint.replaceAll(':', '').isNotEmpty)
            .toList()
          ..sort();
    return fingerprints;
  }

  static bool _sameFingerprints(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
