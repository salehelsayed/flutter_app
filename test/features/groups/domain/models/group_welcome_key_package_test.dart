import 'dart:convert';

import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validMaterial = 'recipient-key-package-public-material-v1';
  final issuedAt = DateTime.utc(2026, 4, 30, 12);
  final expiresAt = DateTime.utc(2026, 5, 1, 12);

  GroupWelcomeKeyPackage makePackage({
    String packageId = 'recipient-package-1',
    String publicMaterial = validMaterial,
    String recipientPeerId = 'peer-recipient',
    String recipientDeviceId = 'device-recipient',
    String recipientTransportPeerId = 'transport-recipient',
    String recipientMlKemPublicKey = 'recipient-mlkem-key',
    String inviteId = 'invite-1',
    String groupId = 'group-1',
    int keyEpoch = 7,
    DateTime? issuedAtOverride,
    DateTime? expiresAtOverride,
  }) {
    return GroupWelcomeKeyPackage.create(
      packageId: packageId,
      publicMaterial: publicMaterial,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      inviteId: inviteId,
      groupId: groupId,
      keyEpoch: keyEpoch,
      issuedAt: issuedAtOverride ?? issuedAt,
      expiresAt: expiresAtOverride ?? expiresAt,
    );
  }

  group('GroupWelcomeKeyPackage', () {
    test('derives default package ids from local device ids', () {
      expect(
        defaultGroupWelcomeKeyPackageIdForDevice(' device-1 '),
        'key-package-device-1',
      );
      expect(defaultGroupWelcomeKeyPackageIdForDevice(' '), isNull);
      expect(defaultGroupWelcomeKeyPackageIdForDevice(null), isNull);
    });

    test('round-trips canonical package fields with a material hash', () {
      final package = makePackage();
      final parsed = GroupWelcomeKeyPackage.fromJson(package.toJson());

      expect(parsed, isNotNull);
      expect(parsed!.packageId, 'recipient-package-1');
      expect(parsed.publicMaterial, validMaterial);
      expect(
        parsed.publicMaterialHash,
        GroupWelcomeKeyPackage.hashPublicMaterial(validMaterial),
      );
      expect(parsed.recipientPeerId, 'peer-recipient');
      expect(parsed.recipientDeviceId, 'device-recipient');
      expect(parsed.recipientTransportPeerId, 'transport-recipient');
      expect(parsed.recipientMlKemPublicKey, 'recipient-mlkem-key');
      expect(parsed.inviteId, 'invite-1');
      expect(parsed.groupId, 'group-1');
      expect(parsed.keyEpoch, 7);
      expect(parsed.issuedAt, issuedAt);
      expect(parsed.expiresAt, expiresAt);

      final encoded = jsonEncode(package.toJson());
      expect(encoded, contains('publicMaterialHash'));
    });

    test('rejects malformed, stale, weak, or mismatched package fields', () {
      expect(makePackage().isStructurallyValid(at: issuedAt), isTrue);
      expect(
        makePackage(publicMaterial: 'weak').isStructurallyValid(at: issuedAt),
        isFalse,
      );
      expect(
        makePackage(packageId: ' ').isStructurallyValid(at: issuedAt),
        isFalse,
      );
      expect(
        makePackage(
          expiresAtOverride: issuedAt,
        ).isStructurallyValid(at: issuedAt),
        isFalse,
      );
      expect(
        makePackage(
          expiresAtOverride: issuedAt.add(const Duration(minutes: 5)),
        ).isStructurallyValid(at: issuedAt.add(const Duration(minutes: 6))),
        isFalse,
      );

      final tampered = makePackage().toJson();
      tampered['publicMaterial'] = '$validMaterial-tampered';
      expect(GroupWelcomeKeyPackage.fromJson(tampered), isNull);
    });

    test('matches only the intended invite and local recipient device', () {
      final package = makePackage();

      expect(
        package.matchesInviteAndRecipient(
          inviteId: 'invite-1',
          groupId: 'group-1',
          keyEpoch: 7,
          recipientPeerId: 'peer-recipient',
          recipientDeviceId: 'device-recipient',
          recipientTransportPeerId: 'transport-recipient',
          recipientMlKemPublicKey: 'recipient-mlkem-key',
          recipientKeyPackageId: 'recipient-package-1',
          recipientKeyPackagePublicMaterial: validMaterial,
        ),
        isTrue,
      );
      expect(
        package.matchesInviteAndRecipient(
          inviteId: 'invite-2',
          groupId: 'group-1',
          keyEpoch: 7,
          recipientPeerId: 'peer-recipient',
          recipientDeviceId: 'device-recipient',
          recipientTransportPeerId: 'transport-recipient',
          recipientMlKemPublicKey: 'recipient-mlkem-key',
          recipientKeyPackageId: 'recipient-package-1',
          recipientKeyPackagePublicMaterial: validMaterial,
        ),
        isFalse,
      );
      expect(
        package.matchesInviteAndRecipient(
          inviteId: 'invite-1',
          groupId: 'group-1',
          keyEpoch: 7,
          recipientPeerId: 'peer-recipient',
          recipientDeviceId: 'device-recipient',
          recipientTransportPeerId: 'transport-recipient',
          recipientMlKemPublicKey: 'recipient-mlkem-key',
          recipientKeyPackageId: 'recipient-package-1',
          recipientKeyPackagePublicMaterial: '$validMaterial-other',
        ),
        isFalse,
      );
    });
  });
}
