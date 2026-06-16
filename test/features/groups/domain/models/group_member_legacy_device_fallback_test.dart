import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_member.dart';

/// R5 lock test: migration 062 left existing members' devices_json NULL and no
/// migration ever backfills it. This is SAFE because GroupMember synthesizes a
/// single "legacy" device from the member's account keys on the fly, and every
/// device-aware path consumes it via activeDevicesWithLegacyFallback(). This test
/// locks that contract so nobody adds an unneeded backfill migration.
void main() {
  GroupMember member({String? publicKey = 'pk-bob', String? mlKem = 'mlkem-bob'}) =>
      GroupMember(
        groupId: 'g1',
        peerId: 'bob',
        role: MemberRole.writer,
        publicKey: publicKey,
        mlKemPublicKey: mlKem,
        devices: const [], // simulates an un-backfilled (NULL devices_json) row
        joinedAt: DateTime.utc(2026, 1, 1),
      );

  test('a device-less member resolves to a synthesized legacy device', () {
    final m = member();
    expect(m.devices, isEmpty);

    final legacy = m.legacyDeviceIdentity;
    expect(legacy, isNotNull);
    expect(legacy!.deviceId, 'bob', reason: 'legacy deviceId == peerId');
    expect(legacy.transportPeerId, 'bob');
    expect(legacy.deviceSigningPublicKey, 'pk-bob');
    expect(legacy.mlKemPublicKey, 'mlkem-bob');

    final fallback = m.activeDevicesWithLegacyFallback();
    expect(fallback, hasLength(1));
    expect(fallback.single.deviceId, 'bob');
  });

  test('fromMap with no devices_json still yields the legacy device', () {
    final m = GroupMember.fromMap({
      'group_id': 'g1',
      'peer_id': 'bob',
      'username': 'Bob',
      'role': 'writer',
      'public_key': 'pk-bob',
      'ml_kem_public_key': 'mlkem-bob',
      'joined_at': '2026-01-01T00:00:00.000Z',
      // 'devices_json' intentionally absent (pre-062 / un-backfilled row).
    });
    expect(m.devices, isEmpty);
    expect(m.activeDevicesWithLegacyFallback(), hasLength(1));
  });

  test('a member with NO account keys has no legacy device (non-deliverable)', () {
    final m = member(publicKey: null, mlKem: null);
    expect(m.legacyDeviceIdentity, isNull);
    expect(m.activeDevicesWithLegacyFallback(), isEmpty);
  });
}
