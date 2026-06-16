import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_member_identity_safety.dart';

/// B4: GroupMemberIdentitySafety.compare gains an optional device dimension.
/// `savedDevices: null` (default) must keep the EXACT account-level v1 behaviour.
void main() {
  GroupMember member({
    String publicKey = 'pk-bob',
    String mlKem = 'mlkem-bob',
    List<GroupMemberDeviceIdentity> devices = const [],
  }) => GroupMember(
    groupId: 'g1',
    peerId: 'bob',
    role: MemberRole.writer,
    publicKey: publicKey,
    mlKemPublicKey: mlKem,
    devices: devices,
    joinedAt: DateTime.utc(2026, 1, 1),
  );

  ContactModel contact({String publicKey = 'pk-bob', String mlKem = 'mlkem-bob'}) =>
      ContactModel(
        peerId: 'bob',
        username: 'Bob',
        publicKey: publicKey,
        rendezvous: 'rv',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00Z',
        mlKemPublicKey: mlKem,
      );

  GroupMemberDeviceIdentity device(String id, String mlKem) =>
      GroupMemberDeviceIdentity(
        deviceId: id,
        transportPeerId: id,
        deviceSigningPublicKey: 'sign-$id',
        mlKemPublicKey: mlKem,
      );

  group('account-level (savedDevices == null) — unchanged v1 behaviour', () {
    test('no change when account keys match', () {
      final result = GroupMemberIdentitySafety.compare(
        member: member(),
        savedContact: contact(),
      );
      expect(result, isNotNull);
      expect(result!.identityChanged, isFalse);
    });

    test('identityChanged when the account key differs (devices ignored)', () {
      final result = GroupMemberIdentitySafety.compare(
        member: member(devices: [device('bob-tablet', 'mlkem-x')]),
        savedContact: contact(publicKey: 'pk-bob-rotated'),
      );
      expect(result!.identityChanged, isTrue);
    });
  });

  group('device-aware (savedDevices provided)', () {
    test('no change when device sets match', () {
      final devices = [device('bob-phone', 'mlkem-phone')];
      final result = GroupMemberIdentitySafety.compare(
        member: member(devices: devices),
        savedContact: contact(),
        savedDevices: devices,
      );
      expect(result!.identityChanged, isFalse);
    });

    test(
      'identityChanged when a device is ADDED even with identical account keys',
      () {
        final saved = [device('bob-phone', 'mlkem-phone')];
        final current = [
          device('bob-phone', 'mlkem-phone'),
          device('bob-tablet', 'mlkem-tablet'),
        ];
        final result = GroupMemberIdentitySafety.compare(
          member: member(devices: current),
          savedContact: contact(),
          savedDevices: saved,
        );
        expect(result!.identityChanged, isTrue);
        expect(result.currentSafetyNumber, isNot(result.savedSafetyNumber));
      },
    );

    test('identityChanged when a device key is SWAPPED', () {
      final saved = [device('bob-phone', 'mlkem-old')];
      final current = [device('bob-phone', 'mlkem-new')];
      final result = GroupMemberIdentitySafety.compare(
        member: member(devices: current),
        savedContact: contact(),
        savedDevices: saved,
      );
      expect(result!.identityChanged, isTrue);
    });
  });
}
