import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

void main() {
  group('GroupMember', () {
    Map<String, dynamic> makeMap({
      String groupId = 'group-1',
      String peerId = 'peer-1',
      String? username = 'Alice',
      String role = 'writer',
      String? publicKey = 'pk-base64',
      String? mlKemPublicKey = 'mlkem-base64',
      String? devicesJson,
      String joinedAt = '2026-01-15T12:00:00.000Z',
    }) {
      return {
        'group_id': groupId,
        'peer_id': peerId,
        'username': username,
        'role': role,
        'public_key': publicKey,
        'ml_kem_public_key': mlKemPublicKey,
        'devices_json': ?devicesJson,
        'joined_at': joinedAt,
      };
    }

    test('fromMap/toMap round-trip preserves all fields', () {
      final map = makeMap();
      final model = GroupMember.fromMap(map);
      final result = model.toMap();

      expect(result['group_id'], 'group-1');
      expect(result['peer_id'], 'peer-1');
      expect(result['username'], 'Alice');
      expect(result['role'], 'writer');
      expect(result['public_key'], 'pk-base64');
      expect(result['ml_kem_public_key'], 'mlkem-base64');
      expect(result['joined_at'], '2026-01-15T12:00:00.000Z');
    });

    test('MemberRole enum converts correctly', () {
      expect(MemberRole.fromValue('admin'), MemberRole.admin);
      expect(MemberRole.fromValue('writer'), MemberRole.writer);
      expect(MemberRole.fromValue('reader'), MemberRole.reader);
      expect(MemberRole.admin.toValue(), 'admin');
      expect(MemberRole.writer.toValue(), 'writer');
      expect(MemberRole.reader.toValue(), 'reader');
    });

    test('equality based on groupId and peerId', () {
      final a = GroupMember.fromMap(makeMap(groupId: 'g1', peerId: 'p1'));
      final b = GroupMember.fromMap(
        makeMap(groupId: 'g1', peerId: 'p1', username: 'Bob'),
      );
      final c = GroupMember.fromMap(makeMap(groupId: 'g1', peerId: 'p2'));

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('device roster round-trip preserves active and revoked devices', () {
      final member = GroupMember(
        groupId: 'group-1',
        peerId: 'member-b',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'member-pk',
        mlKemPublicKey: 'legacy-mlkem',
        joinedAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
        devices: [
          const GroupMemberDeviceIdentity(
            deviceId: 'bob-phone',
            transportPeerId: '12D3KooWBobPhone',
            deviceSigningPublicKey: 'device-pk-phone',
            mlKemPublicKey: 'mlkem-phone',
            keyPackageId: 'kp-phone',
            keyPackagePublicMaterial: 'kp-pub-phone',
          ),
          GroupMemberDeviceIdentity(
            deviceId: 'bob-tablet',
            transportPeerId: '12D3KooWBobTablet',
            deviceSigningPublicKey: 'device-pk-tablet',
            mlKemPublicKey: 'mlkem-tablet',
            keyPackageId: 'kp-tablet',
            keyPackagePublicMaterial: 'kp-pub-tablet',
            status: GroupMemberDeviceStatus.revoked,
            revokedAt: DateTime.parse('2026-01-16T12:00:00.000Z'),
          ),
        ],
      );

      final row = member.toMap();
      final parsed = GroupMember.fromMap(Map<String, dynamic>.from(row));

      expect(parsed.devices, hasLength(2));
      expect(parsed.activeDevices.single.deviceId, 'bob-phone');
      expect(
        parsed.findDeviceByTransportPeerId('12D3KooWBobPhone')?.keyPackageId,
        'kp-phone',
      );
      expect(parsed.findDeviceById('bob-tablet'), isNull);
      expect(parsed.findDeviceById('bob-tablet', activeOnly: false), isNotNull);
    });

    test('config JSON preserves joined interval for invite replay', () {
      final joinedAt = DateTime.parse('2026-01-15T12:03:00.000Z');
      final member = GroupMember(
        groupId: 'group-1',
        peerId: 'member-b',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'member-pk',
        joinedAt: joinedAt,
      );

      final config = member.toConfigJson();
      final parsed = GroupMember.fromConfigMap(
        groupId: 'group-1',
        map: config,
        joinedAt: DateTime.parse('2026-01-16T12:00:00.000Z'),
      );

      expect(config['joinedAt'], '2026-01-15T12:03:00.000Z');
      expect(parsed.joinedAt, joinedAt);
    });

    test(
      'G3-006 fromConfigMap prefers explicit config joinedAt over existing',
      () {
        final existingJoinedAt = DateTime.parse('2026-01-15T12:00:00.000Z');
        final configJoinedAt = DateTime.parse('2026-01-15T12:30:00.000Z');
        final existing = GroupMember(
          groupId: 'group-1',
          peerId: 'member-b',
          username: 'Old Bob',
          role: MemberRole.writer,
          publicKey: 'old-pk',
          joinedAt: existingJoinedAt,
        );

        final parsed = GroupMember.fromConfigMap(
          groupId: 'group-1',
          existing: existing,
          map: {
            'peerId': 'member-b',
            'username': 'New Bob',
            'role': 'writer',
            'publicKey': 'new-pk',
            'joinedAt': configJoinedAt.toIso8601String(),
          },
        );

        expect(parsed.joinedAt, configJoinedAt);
        expect(parsed.username, 'New Bob');
        expect(parsed.publicKey, 'new-pk');
      },
    );

    test(
      'legacy fallback device is explicit and member equality stays scoped',
      () {
        final legacy = GroupMember.fromMap(makeMap(peerId: 'member-legacy'));

        expect(legacy.devices, isEmpty);
        expect(legacy.activeDevices, isEmpty);
        expect(legacy.activeDevicesWithLegacyFallback(), hasLength(1));
        expect(
          legacy.activeDevicesWithLegacyFallback().single.transportPeerId,
          'member-legacy',
        );

        final sameMemberWithDevice = legacy.copyWith(
          devices: [
            const GroupMemberDeviceIdentity(
              deviceId: 'new-device',
              transportPeerId: '12D3KooWNewDevice',
              deviceSigningPublicKey: 'device-pk',
            ),
          ],
        );
        expect(legacy, equals(sameMemberWithDevice));
      },
    );

    test('SV-012 rejects noncanonical peer id text variants', () {
      expect(groupMemberPeerIdRejectReason(' peer-1'), 'noncanonical_peer_id');
      expect(groupMemberPeerIdRejectReason('peer-1 '), 'noncanonical_peer_id');
      expect(groupMemberPeerIdRejectReason('peer\n1'), 'noncanonical_peer_id');
      expect(groupMemberPeerIdRejectReason(''), 'invalid_peer_id');
      expect(groupMemberPeerIdRejectReason(42), 'invalid_peer_id_type');
      expect(groupMemberPeerIdRejectReason('peer-1'), isNull);
    });

    test('SV-012 detects case-equivalent duplicate member identities', () {
      final existing = GroupMember(
        groupId: 'group-1',
        peerId: 'Peer-A',
        role: MemberRole.writer,
        joinedAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
      );
      final variant = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-a',
        role: MemberRole.writer,
        joinedAt: DateTime.parse('2026-01-15T12:01:00.000Z'),
      );

      expect(
        groupMemberDuplicatePeerIdVariantRejectReason([existing], variant),
        'duplicate_peer_id_variant:peer-a',
      );
      expect(
        groupConfigMemberKeyMaterialRejectReason({
          'members': [
            {'peerId': 'Peer-A', 'role': 'writer'},
            {'peerId': 'peer-a', 'role': 'admin'},
          ],
        }),
        'duplicate_peer_id_variant:peer-a',
      );
    });

    test(
      'G3-019 rejects invalid and duplicate device identities in config',
      () {
        expect(
          groupMemberConfigKeyMaterialRejectReason({
            'peerId': 'peer-a',
            'devices': [
              {'deviceId': 'device-a', 'deviceSigningPublicKey': 'device-pk-a'},
            ],
          }),
          'invalid_device_transport_peer_id',
        );
        expect(
          groupMemberConfigKeyMaterialRejectReason({
            'peerId': 'peer-a',
            'devices': [
              {'deviceId': 'device-a', 'transportPeerId': 'transport-a'},
            ],
          }),
          'invalid_device_signing_public_key',
        );
        expect(
          groupMemberConfigKeyMaterialRejectReason({
            'peerId': 'peer-a',
            'devices': [
              {
                'deviceId': 'device-a',
                'transportPeerId': 'transport-a',
                'deviceSigningPublicKey': 'device-pk-a',
              },
              {
                'deviceId': 'DEVICE-A',
                'transportPeerId': 'transport-a-tablet',
                'deviceSigningPublicKey': 'device-pk-a-tablet',
              },
            ],
          }),
          'duplicate_device_id:DEVICE-A',
        );
        expect(
          groupConfigMemberKeyMaterialRejectReason({
            'members': [
              {
                'peerId': 'peer-a',
                'devices': [
                  {
                    'deviceId': 'device-a',
                    'transportPeerId': 'transport-a',
                    'deviceSigningPublicKey': 'device-pk-a',
                  },
                  {
                    'deviceId': 'device-a',
                    'transportPeerId': 'transport-a-tablet',
                    'deviceSigningPublicKey': 'device-pk-a-tablet',
                  },
                ],
              },
            ],
          }),
          'duplicate_device_id:device-a:peer-a',
        );
      },
    );

    test('G3-019 preserves legacy device aliases during validation', () {
      expect(
        groupMemberConfigKeyMaterialRejectReason({
          'peerId': 'peer-a',
          'devices': [
            {
              'deviceId': 'device-a',
              'peerId': 'transport-a',
              'publicKey': 'device-pk-a',
              'keyPackagePublicKey': 'key-package-public-a',
            },
          ],
        }),
        isNull,
      );
    });
  });
}
