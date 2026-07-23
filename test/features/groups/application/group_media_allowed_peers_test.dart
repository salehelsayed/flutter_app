import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

void main() {
  GroupMemberDeviceIdentity device(
    String deviceId,
    String transportPeerId, {
    GroupMemberDeviceStatus status = GroupMemberDeviceStatus.active,
    DateTime? revokedAt,
  }) {
    return GroupMemberDeviceIdentity(
      deviceId: deviceId,
      transportPeerId: transportPeerId,
      deviceSigningPublicKey: 'signing-$deviceId',
      status: status,
      revokedAt: revokedAt,
    );
  }

  GroupMember member(
    String peerId, {
    List<GroupMemberDeviceIdentity> devices =
        const <GroupMemberDeviceIdentity>[],
  }) {
    return GroupMember(
      groupId: 'group-1',
      peerId: peerId,
      username: peerId,
      role: MemberRole.writer,
      publicKey: 'pk-$peerId',
      mlKemPublicKey: 'mlkem-$peerId',
      devices: devices,
      joinedAt: DateTime.utc(2026, 5, 14),
    );
  }

  test('PL-005 builds media allowedPeers from unique active member rows', () {
    final allowedPeers = groupMediaAllowedPeersForMembers([
      member(' peer-admin '),
      member('peer-bob'),
      member(''),
      member('peer-bob'),
      member('peer-charlie'),
    ]);

    expect(allowedPeers, ['peer-admin', 'peer-bob', 'peer-charlie']);
  });

  test(
    'P269 group media ACL uses active device transport identities with revoked-safe legacy fallback',
    () {
      final allRevoked = member(
        'account-all-revoked',
        devices: [
          device(
            'device-revoked-status',
            'transport-revoked-status',
            status: GroupMemberDeviceStatus.revoked,
          ),
          device(
            'device-revoked-at',
            'transport-revoked-at',
            revokedAt: DateTime.utc(2026, 7, 21),
          ),
        ],
      );
      final legacyOnly = member(' legacy-account-transport ');

      final allowedPeers = groupMediaAllowedPeersForMembers([
        member(
          'account-alice',
          devices: [
            device('device-alice-z', ' transport-z '),
            device('device-alice-a', 'transport-a'),
            device('device-alice-z-duplicate', 'transport-z'),
            device('device-alice-blank', '   '),
            device(
              'device-alice-revoked',
              'transport-revoked-status',
              status: GroupMemberDeviceStatus.revoked,
            ),
            device(
              'device-alice-revoked-at',
              'transport-revoked-at',
              revokedAt: DateTime.utc(2026, 7, 20),
            ),
          ],
        ),
        member(
          'account-bob',
          devices: [
            device('device-bob-duplicate', 'transport-a'),
            // A device ID equal to its transport is a valid production shape.
            device('transport-b', ' transport-b '),
          ],
        ),
        allRevoked,
        legacyOnly,
      ]);

      expect(allowedPeers, [
        'transport-z',
        'transport-a',
        'transport-b',
        'legacy-account-transport',
      ]);
      for (final forbidden in const [
        'account-alice',
        'account-bob',
        'account-all-revoked',
        'device-alice-z',
        'device-alice-a',
        'device-bob-duplicate',
        'transport-revoked-status',
        'transport-revoked-at',
        '',
      ]) {
        expect(allowedPeers, isNot(contains(forbidden)));
      }

      // An explicit roster remains authoritative even when every entry is
      // revoked; the account-level legacy identity must not be resurrected.
      expect(groupMediaAllowedPeersForMembers([allRevoked]), isEmpty);

      // Legacy account transport remains supported only when there is no
      // explicit device roster at all.
      expect(groupMediaAllowedPeersForMembers([legacyOnly]), [
        'legacy-account-transport',
      ]);
      expect(
        groupMediaAllowedPeersForMembers([
          member(
            'account-explicit-blank',
            devices: [device('device-explicit-blank', '   ')],
          ),
        ]),
        isEmpty,
      );
    },
  );
}
