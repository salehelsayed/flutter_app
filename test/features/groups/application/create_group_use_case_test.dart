import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

const _gl005ForbiddenPublicRouteKeys = {
  'visibility',
  'ispublic',
  'discoverable',
  'isdiscoverable',
  'openjoin',
  'allowopenjoin',
  'joinpolicy',
  'invitelink',
  'joinlink',
  'publicpreview',
  'publiclisting',
  'publiccatalog',
  'publicroom',
  'publicgroup',
};

void _expectNoPublicRouteFields(Object? value, {String path = 'payload'}) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key.replaceAll(RegExp(r'[_-]'), '').toLowerCase();
      expect(
        _gl005ForbiddenPublicRouteKeys,
        isNot(contains(normalized)),
        reason: 'GL-005 forbids public/open route field "$key" at $path',
      );
      _expectNoPublicRouteFields(entry.value, path: '$path.$key');
    }
  } else if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      _expectNoPublicRouteFields(item, path: '$path[$index]');
      index++;
    }
  }
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();

    // Set up bridge response for group:create (Go returns groupKey + keyEpoch)
    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': 'test-group-id',
      'topicName': '/mknoon/group/test-group-id',
      'groupKey': 'test-group-key-base64',
      'keyEpoch': 1,
    };
    // Fallback: bridge response for group.keygen (used when create doesn't return key)
    bridge.responses['group.keygen'] = {
      'ok': true,
      'groupKey': 'test-group-key-base64',
    };
  });

  test('creates group successfully', () async {
    final result = await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'Test Group',
      type: GroupType.chat,
      creatorPeerId: 'peer-123',
      creatorPublicKey: 'pk-123',
      creatorMlKemPublicKey: 'mlkem-pk-123',
    );

    expect(result.name, 'Test Group');
    expect(result.type, GroupType.chat);
    expect(result.id, 'test-group-id');
    expect(result.topicName, '/mknoon/group/test-group-id');
    expect(result.myRole, GroupRole.admin);
  });

  test(
    'GL-005 create payloads use only supported private group variants and no public route flags',
    () async {
      final supportedTypes = {
        GroupType.chat: 'chat',
        GroupType.announcement: 'announcement',
        GroupType.qa: 'qa',
      };

      for (final entry in supportedTypes.entries) {
        final localBridge = FakeBridge();
        final localGroupRepo = InMemoryGroupRepository();
        final groupId = 'gl005-${entry.value}-group';
        localBridge.responses['group:create'] = {
          'ok': true,
          'groupId': groupId,
          'topicName': '/mknoon/group/$groupId',
          'groupKey': 'gl005-group-key-${entry.value}',
          'keyEpoch': 1,
        };

        final result = await createGroup(
          bridge: localBridge,
          groupRepo: localGroupRepo,
          name: 'GL-005 ${entry.value}',
          type: entry.key,
          creatorPeerId: 'peer-creator',
          creatorPublicKey: 'pk-creator',
          creatorMlKemPublicKey: 'mlkem-pk-creator',
          description: 'Private invite-only group',
        );

        final createMessage = localBridge.sentMessages.firstWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:create',
        );
        final createPayload =
            (jsonDecode(createMessage) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;

        expect(createPayload['groupType'], entry.value);
        expect(supportedTypes.values, contains(createPayload['groupType']));
        _expectNoPublicRouteFields(createPayload);
        expect(result.type, entry.key);
        expect(await localGroupRepo.getMembers(groupId), hasLength(1));
      }
    },
  );

  test('throws on empty name', () async {
    expect(
      () => createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: '',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws on bridge error', () async {
    bridge.responses['group:create'] = {
      'ok': false,
      'errorCode': 'BRIDGE_ERROR',
      'errorMessage': 'Something went wrong',
    };

    expect(
      () => createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Test Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('saves group, member, and key to repo', () async {
    await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'Test Group',
      type: GroupType.chat,
      creatorPeerId: 'peer-123',
      creatorPublicKey: 'pk-123',
      creatorMlKemPublicKey: 'mlkem-pk-123',
    );

    // Group saved
    final savedGroup = await groupRepo.getGroup('test-group-id');
    expect(savedGroup, isNotNull);
    expect(savedGroup!.name, 'Test Group');

    // Member saved
    final members = await groupRepo.getMembers('test-group-id');
    expect(members.length, 1);
    expect(members.first.peerId, 'peer-123');

    // Key saved
    final key = await groupRepo.getLatestKey('test-group-id');
    expect(key, isNotNull);
    expect(key!.encryptedKey, 'test-group-key-base64');
    expect(key.keyGeneration, 1);
  });

  test(
    'persists creator identity and initial bridge epoch on create',
    () async {
      const groupId = 'initial-state-group-id';
      const topicName = '/mknoon/group/initial-state-group-id';
      const creatorPeerId = 'peer-creator-device-001';
      const creatorUsername = 'Creator Device';
      const creatorPublicKey = 'ed25519-public-key-base64';
      const creatorMlKemPublicKey = 'ml-kem-public-key-base64';
      const initialGroupKey = 'bridge-initial-group-key-base64';
      const initialKeyEpoch = 7;

      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': groupId,
        'topicName': topicName,
        'groupKey': initialGroupKey,
        'keyEpoch': initialKeyEpoch,
      };

      final beforeCreate = DateTime.now().toUtc();
      final result = await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Initial State Group',
        type: GroupType.chat,
        creatorPeerId: creatorPeerId,
        creatorPublicKey: creatorPublicKey,
        creatorMlKemPublicKey: creatorMlKemPublicKey,
        creatorUsername: creatorUsername,
      );
      final afterCreate = DateTime.now().toUtc();

      expect(result.id, groupId);
      expect(result.topicName, topicName);
      expect(result.createdBy, creatorPeerId);
      expect(result.myRole, GroupRole.admin);

      final savedGroup = await groupRepo.getGroup(groupId);
      expect(savedGroup, isNotNull);
      expect(savedGroup!.id, groupId);
      expect(savedGroup.name, 'Initial State Group');
      expect(savedGroup.type, GroupType.chat);
      expect(savedGroup.topicName, topicName);
      expect(savedGroup!.createdBy, creatorPeerId);
      expect(savedGroup.myRole, GroupRole.admin);
      expect(savedGroup.createdAt, result.createdAt);

      final members = await groupRepo.getMembers(groupId);
      expect(members, hasLength(1));
      expect(members.single.peerId, creatorPeerId);

      final creatorMember = await groupRepo.getMember(groupId, creatorPeerId);
      expect(creatorMember, isNotNull);
      expect(creatorMember!.username, creatorUsername);
      expect(creatorMember.role, MemberRole.admin);
      expect(creatorMember.publicKey, creatorPublicKey);
      expect(creatorMember.mlKemPublicKey, creatorMlKemPublicKey);
      expect(
        creatorMember.joinedAt.isAtSameMomentAs(savedGroup.createdAt),
        isTrue,
      );
      expect(creatorMember.joinedAt.isBefore(beforeCreate), isFalse);
      expect(creatorMember.joinedAt.isAfter(afterCreate), isFalse);

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, initialKeyEpoch);
      expect(latestKey.encryptedKey, initialGroupKey);
      expect(latestKey.createdAt, savedGroup.createdAt);

      final epochKey = await groupRepo.getKeyByGeneration(
        groupId,
        initialKeyEpoch,
      );
      expect(epochKey, isNotNull);
      expect(epochKey!.keyGeneration, initialKeyEpoch);
      expect(epochKey.encryptedKey, initialGroupKey);
      expect(epochKey.createdAt, savedGroup.createdAt);
    },
  );

  test('appends signed initial membership event on create', () async {
    const groupId = 'signed-initial-group-id';
    const topicName = '/mknoon/group/signed-initial-group-id';
    const creatorPeerId = 'peer-creator-device-001';
    const creatorUsername = 'Creator Device';
    const creatorPublicKey = 'ed25519-public-key-base64';
    const creatorMlKemPublicKey = 'ml-kem-public-key-base64';
    const creatorPrivateKey = 'creator-private-key-base64';
    const initialGroupKey = 'bridge-initial-group-key-base64';
    const initialKeyEpoch = 7;
    const signature = 'signed-create-event-base64';
    final appendedEntries = <Map<String, Object?>>[];

    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': groupId,
      'topicName': topicName,
      'groupKey': initialGroupKey,
      'keyEpoch': initialKeyEpoch,
    };
    bridge.responses['payload.sign'] = {'ok': true, 'signature': signature};

    final result = await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'Signed Initial State Group',
      type: GroupType.chat,
      creatorPeerId: creatorPeerId,
      creatorPublicKey: creatorPublicKey,
      creatorMlKemPublicKey: creatorMlKemPublicKey,
      creatorUsername: creatorUsername,
      creatorPrivateKey: creatorPrivateKey,
      appendGroupEventLogEntry:
          ({
            required groupId,
            required eventType,
            required sourcePeerId,
            required sourceEventId,
            required sourceTimestamp,
            required payload,
            createdAt,
          }) async {
            final entry = <String, Object?>{
              'groupId': groupId,
              'eventType': eventType,
              'sourcePeerId': sourcePeerId,
              'sourceEventId': sourceEventId,
              'sourceTimestamp': sourceTimestamp,
              'payload': payload,
              'createdAt': createdAt,
            };
            appendedEntries.add(entry);
            return entry;
          },
    );

    expect(result.id, groupId);
    expect(bridge.commandLog, ['group:create', 'payload.sign']);

    final signMessage = bridge.sentMessages.firstWhere(
      (message) =>
          (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
          'payload.sign',
    );
    final signPayload =
        (jsonDecode(signMessage) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    expect(signPayload['privateKey'], creatorPrivateKey);

    final signedData = signPayload['data'] as String;
    final signedPayload = jsonDecode(signedData) as Map<String, dynamic>;
    expect(signedPayload['schemaVersion'], 1);
    expect(signedPayload['eventType'], 'group_created');
    expect(signedPayload['groupId'], groupId);
    expect(signedPayload['topicName'], topicName);
    expect(signedPayload['groupName'], 'Signed Initial State Group');
    expect(signedPayload['groupType'], 'chat');
    expect(signedPayload['createdBy'], creatorPeerId);
    expect(signedPayload['initialKeyEpoch'], initialKeyEpoch);
    expect(
      signedData.indexOf('"createdAt"'),
      lessThan(signedData.indexOf('"createdBy"')),
    );

    final creator = signedPayload['creator'] as Map<String, dynamic>;
    expect(creator['peerId'], creatorPeerId);
    expect(creator['username'], creatorUsername);
    expect(creator['role'], 'admin');
    expect(creator['publicKey'], creatorPublicKey);
    expect(creator['mlKemPublicKey'], creatorMlKemPublicKey);
    expect(creator, contains('joinedAt'));

    expect(appendedEntries, hasLength(1));
    final entry = appendedEntries.single;
    expect(entry['groupId'], groupId);
    expect(entry['eventType'], 'group_created');
    expect(entry['sourcePeerId'], creatorPeerId);
    expect(entry['sourceEventId'], 'group_created:$groupId');
    expect(entry['sourceTimestamp'], result.createdAt.toIso8601String());
    expect(entry['createdAt'], result.createdAt);

    final eventPayload = entry['payload'] as Map<String, Object?>;
    expect(eventPayload['signature'], signature);
    expect(eventPayload['signatureAlgorithm'], 'ed25519');
    expect(eventPayload['signedPayload'], signedPayload);
    expect(jsonEncode(eventPayload), isNot(contains(creatorPrivateKey)));

    final savedGroup = await groupRepo.getGroup(groupId);
    final creatorMember = await groupRepo.getMember(groupId, creatorPeerId);
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(savedGroup, isNotNull);
    expect(creatorMember, isNotNull);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, initialKeyEpoch);
  });

  test('rolls back when initial membership event signing fails', () async {
    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': 'unsigned-create-group-id',
      'topicName': '/mknoon/group/unsigned-create-group-id',
      'groupKey': 'group-key',
      'keyEpoch': 3,
    };
    bridge.responses['payload.sign'] = {
      'ok': false,
      'errorMessage': 'signing failed',
    };

    await expectLater(
      createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Unsigned Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-creator',
        creatorPublicKey: 'pk-creator',
        creatorMlKemPublicKey: 'mlkem-pk-creator',
        creatorPrivateKey: 'sk-creator',
        appendGroupEventLogEntry:
            ({
              required groupId,
              required eventType,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required payload,
              createdAt,
            }) async => <String, Object?>{},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('initial membership event'),
        ),
      ),
    );

    expect(await groupRepo.getGroup('unsigned-create-group-id'), isNull);
    expect(await groupRepo.getMembers('unsigned-create-group-id'), isEmpty);
    expect(await groupRepo.getLatestKey('unsigned-create-group-id'), isNull);
  });

  test('rolls back when initial membership event append fails', () async {
    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': 'unlogged-create-group-id',
      'topicName': '/mknoon/group/unlogged-create-group-id',
      'groupKey': 'group-key',
      'keyEpoch': 3,
    };
    bridge.responses['payload.sign'] = {
      'ok': true,
      'signature': 'signed-create-event',
    };

    await expectLater(
      createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Unlogged Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-creator',
        creatorPublicKey: 'pk-creator',
        creatorMlKemPublicKey: 'mlkem-pk-creator',
        creatorPrivateKey: 'sk-creator',
        appendGroupEventLogEntry:
            ({
              required groupId,
              required eventType,
              required sourcePeerId,
              required sourceEventId,
              required sourceTimestamp,
              required payload,
              createdAt,
            }) async {
              throw StateError('append failed');
            },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('initial membership event'),
        ),
      ),
    );

    expect(await groupRepo.getGroup('unlogged-create-group-id'), isNull);
    expect(await groupRepo.getMembers('unlogged-create-group-id'), isEmpty);
    expect(await groupRepo.getLatestKey('unlogged-create-group-id'), isNull);
  });

  test(
    'duplicate bridge group id converges to one canonical local create state',
    () async {
      await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Test Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      );

      await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Test Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      );

      expect(
        bridge.commandLog.where((command) => command == 'group:create'),
        hasLength(2),
      );

      final groups = await groupRepo.getAllGroups();
      expect(groups, hasLength(1));
      expect(groups.single.id, 'test-group-id');
      expect(groups.single.topicName, '/mknoon/group/test-group-id');
      expect(groupRepo.groupCount, 1);

      final members = await groupRepo.getMembers('test-group-id');
      expect(members, hasLength(1));
      expect(members.single.peerId, 'peer-123');
      expect(members.single.role, MemberRole.admin);

      final latestKey = await groupRepo.getLatestKey('test-group-id');
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
      expect(latestKey.encryptedKey, 'test-group-key-base64');

      final epochKey = await groupRepo.getKeyByGeneration('test-group-id', 1);
      expect(epochKey, isNotNull);
      expect(epochKey!.encryptedKey, 'test-group-key-base64');
    },
  );

  test('persists the creator username on the admin membership row', () async {
    await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'Test Group',
      type: GroupType.chat,
      creatorPeerId: 'peer-123',
      creatorPublicKey: 'pk-123',
      creatorMlKemPublicKey: 'mlkem-pk-123',
      creatorUsername: 'Admin',
    );

    final members = await groupRepo.getMembers('test-group-id');
    expect(members, hasLength(1));
    expect(members.single.peerId, 'peer-123');
    expect(members.single.username, 'Admin');
    expect(members.single.role, MemberRole.admin);
  });

  test(
    'fails honestly and rolls back when no usable group key is available',
    () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'test-group-id',
        'topicName': '/mknoon/group/test-group-id',
      };
      bridge.responses['group.keygen'] = {
        'ok': false,
        'errorCode': 'KEYGEN_FAILED',
        'errorMessage': 'missing key material',
      };

      await expectLater(
        createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Keyless Group',
          type: GroupType.chat,
          creatorPeerId: 'peer-123',
          creatorPublicKey: 'pk-123',
          creatorMlKemPublicKey: 'mlkem-pk-123',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no usable group key'),
          ),
        ),
      );

      expect(await groupRepo.getGroup('test-group-id'), isNull);
      expect(await groupRepo.getMembers('test-group-id'), isEmpty);
      expect(await groupRepo.getLatestKey('test-group-id'), isNull);
    },
  );

  test(
    'uses the canonical /mknoon/group fallback when the bridge omits topicName',
    () async {
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'test-group-id',
        'groupKey': 'test-group-key-base64',
        'keyEpoch': 1,
      };

      final result = await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Fallback Topic Group',
        type: GroupType.chat,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      );

      expect(result.topicName, '/mknoon/group/test-group-id');

      final savedGroup = await groupRepo.getGroup('test-group-id');
      expect(savedGroup, isNotNull);
      expect(savedGroup!.topicName, '/mknoon/group/test-group-id');
    },
  );

  test(
    'creates announcement group with announcement bridge payload and admin metadata',
    () async {
      final result = await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'Announcements',
        type: GroupType.announcement,
        creatorPeerId: 'peer-123',
        creatorPublicKey: 'pk-123',
        creatorMlKemPublicKey: 'mlkem-pk-123',
      );

      final createMessage = bridge.sentMessages.firstWhere(
        (message) =>
            (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
            'group:create',
      );
      final createPayload =
          (jsonDecode(createMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;

      expect(createPayload['groupType'], 'announcement');
      expect(result.type, GroupType.announcement);
      expect(result.createdBy, 'peer-123');
      expect(result.myRole, GroupRole.admin);

      final savedGroup = await groupRepo.getGroup('test-group-id');
      expect(savedGroup, isNotNull);
      expect(savedGroup!.type, GroupType.announcement);
      expect(savedGroup.createdBy, 'peer-123');
      expect(savedGroup.myRole, GroupRole.admin);

      final members = await groupRepo.getMembers('test-group-id');
      expect(members.length, 1);
      expect(members.first.peerId, 'peer-123');
      expect(members.first.role, MemberRole.admin);
    },
  );
}
