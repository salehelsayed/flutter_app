import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/announce_restored_device_use_case.dart';
import 'package:flutter_app/features/groups/application/group_device_announce_marker.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

/// R1: the startup hook that fires the (built) device-announce emit when a fresh
/// restore set the one-shot marker. Drives the marker lifecycle (D4).
void main() {
  late FakeSecureKeyStore store;
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late List<Map<String, Object?>> announceCalls;

  IdentityModel identity() => IdentityModel(
    peerId: 'bob-logical',
    publicKey: 'pk-bob',
    privateKey: 'sk-bob',
    mnemonic12: 'a b c d e f g h i j k l',
    mlKemPublicKey: 'mlkem-bob-fresh',
    username: 'Bob',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  );

  AnnounceRestoredDeviceToGroupsFn announceSpy(int returns) =>
      ({
        required bridge,
        required groupRepo,
        required selfPeerId,
        required accountSigningPublicKey,
        required accountSigningPrivateKey,
        required selfUsername,
        required announcedDevice,
      }) async {
        announceCalls.add({
          'selfPeerId': selfPeerId,
          'accountSigningPublicKey': accountSigningPublicKey,
          'deviceId': announcedDevice.deviceId,
          'transportPeerId': announcedDevice.transportPeerId,
          'deviceSigningPublicKey': announcedDevice.deviceSigningPublicKey,
          'mlKemPublicKey': announcedDevice.mlKemPublicKey,
        });
        return returns;
      };

  setUp(() {
    store = FakeSecureKeyStore();
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    announceCalls = [];
  });

  Future<void> run({
    required bool enabled,
    int announceReturns = 1,
    IdentityModel? id,
    String? transportPeerId = 'bob-transport',
  }) => maybeAnnounceRestoredDeviceOnStartup(
    secureKeyStore: store,
    bridge: bridge,
    groupRepo: groupRepo,
    identity: id ?? identity(),
    transportPeerId: transportPeerId,
    announce: announceSpy(announceReturns),
    multiDeviceSyncEnabled: enabled,
  );

  Future<void> addGroup({bool dissolved = false}) => groupRepo.saveGroup(
    GroupModel(
      id: dissolved ? 'g-dissolved' : 'g1',
      name: 'g',
      type: GroupType.chat,
      topicName: 't',
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: 'bob-logical',
      myRole: GroupRole.member,
      isDissolved: dissolved,
    ),
  );

  test('no marker → no announce, nothing cleared', () async {
    await addGroup();
    await run(enabled: true);
    expect(announceCalls, isEmpty);
  });

  test('flag OFF + marker → marker dropped (no churn), no announce', () async {
    await markGroupDeviceAnnouncePending(store);
    await run(enabled: false);
    expect(announceCalls, isEmpty);
    expect(await readGroupDeviceAnnounceMarker(store), isFalse);
  });

  test('flag ON: announces with the device binding and clears the marker', () async {
    await addGroup();
    await markGroupDeviceAnnouncePending(store);

    await run(enabled: true, announceReturns: 1);

    expect(announceCalls, hasLength(1));
    final call = announceCalls.single;
    expect(call['selfPeerId'], 'bob-transport');
    expect(call['deviceId'], 'bob-transport');
    expect(call['transportPeerId'], 'bob-transport');
    expect(call['deviceSigningPublicKey'], 'pk-bob');
    expect(call['mlKemPublicKey'], 'mlkem-bob-fresh');
    expect(call['accountSigningPublicKey'], 'pk-bob');
    expect(await readGroupDeviceAnnounceMarker(store), isFalse);
  });

  test('flag ON, publish failed for all groups → marker RETAINED for retry', () async {
    await addGroup();
    await markGroupDeviceAnnouncePending(store);

    await run(enabled: true, announceReturns: 0);

    expect(announceCalls, hasLength(1));
    expect(await readGroupDeviceAnnounceMarker(store), isTrue);
  });

  test('flag ON, no non-dissolved groups → marker cleared (nothing to do)', () async {
    await addGroup(dissolved: true);
    await markGroupDeviceAnnouncePending(store);

    await run(enabled: true, announceReturns: 0);

    expect(await readGroupDeviceAnnounceMarker(store), isFalse);
  });

  test('not ready (no transport peer id) → no announce, marker retained', () async {
    await addGroup();
    await markGroupDeviceAnnouncePending(store);

    await run(enabled: true, transportPeerId: null);

    expect(announceCalls, isEmpty);
    expect(await readGroupDeviceAnnounceMarker(store), isTrue);
  });
}
