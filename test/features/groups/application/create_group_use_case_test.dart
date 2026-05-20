import 'dart:async';
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

class _TimeoutCommandBridge extends FakeBridge {
  final String command;

  _TimeoutCommandBridge(this.command);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == command) {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated $command timeout');
    }
    return super.send(message);
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

  test('KE-001 create persists initial private group key at epoch 1', () async {
    const groupId = 'ke001-initial-epoch-group';
    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': groupId,
      'topicName': '/mknoon/group/$groupId',
      'groupKey': 'ke001-initial-group-key',
      'keyEpoch': 1,
    };

    final result = await createGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      name: 'KE-001 Initial Epoch',
      type: GroupType.chat,
      creatorPeerId: 'ke001-alice-peer',
      creatorPublicKey: 'ke001-alice-public-key',
      creatorMlKemPublicKey: 'ke001-alice-mlkem-key',
    );

    expect(result.id, groupId);

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
    expect(latestKey.encryptedKey, 'ke001-initial-group-key');
    expect(await groupRepo.getKeyByGeneration(groupId, 1), isNotNull);
    expect(await groupRepo.getKeyByGeneration(groupId, 0), isNull);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);
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

  test('BB-003 creator identity contract', () async {
    Future<void> expectRejected({
      required String creatorPeerId,
      required String creatorPublicKey,
      required String creatorMlKemPublicKey,
      String? creatorPrivateKey,
      bool appendCreateEvent = false,
    }) async {
      bridge = FakeBridge();
      groupRepo = InMemoryGroupRepository();
      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': 'bb003-group-id',
        'topicName': '/mknoon/group/bb003-group-id',
        'groupKey': 'bb003-group-key',
        'keyEpoch': 1,
      };
      final appendedEntries = <Map<String, Object?>>[];

      await expectLater(
        createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'BB-003 Group',
          type: GroupType.chat,
          creatorPeerId: creatorPeerId,
          creatorPublicKey: creatorPublicKey,
          creatorMlKemPublicKey: creatorMlKemPublicKey,
          creatorPrivateKey: creatorPrivateKey,
          appendGroupEventLogEntry: appendCreateEvent
              ? ({
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
                }
              : null,
        ),
        throwsA(
          predicate(
            (Object error) => error is ArgumentError || error is StateError,
            'ArgumentError or StateError',
          ),
        ),
      );

      expect(bridge.commandLog, isNot(contains('group:create')));
      expect(bridge.commandLog, isNot(contains('payload.sign')));
      expect(await groupRepo.getAllGroups(), isEmpty);
      expect(await groupRepo.getMembers('bb003-group-id'), isEmpty);
      expect(await groupRepo.getLatestKey('bb003-group-id'), isNull);
      expect(appendedEntries, isEmpty);
    }

    await expectRejected(
      creatorPeerId: '  ',
      creatorPublicKey: 'pk-creator',
      creatorMlKemPublicKey: 'mlkem-pk-creator',
    );
    await expectRejected(
      creatorPeerId: 'peer-creator',
      creatorPublicKey: '  ',
      creatorMlKemPublicKey: 'mlkem-pk-creator',
    );
    await expectRejected(
      creatorPeerId: 'peer-creator',
      creatorPublicKey: 'pk-creator',
      creatorMlKemPublicKey: '  ',
    );
    await expectRejected(
      creatorPeerId: 'peer-creator',
      creatorPublicKey: 'pk-creator',
      creatorMlKemPublicKey: 'mlkem-pk-creator',
      creatorPrivateKey: '  ',
      appendCreateEvent: true,
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

  test(
    'BB-002 group:create NOT_INITIALIZED does not persist group member or key',
    () async {
      bridge.responses['group:create'] = {
        'ok': false,
        'errorCode': 'NOT_INITIALIZED',
        'errorMessage': 'native node not initialized',
      };

      await expectLater(
        createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Pre-init Group',
          type: GroupType.chat,
          creatorPeerId: 'peer-123',
          creatorPublicKey: 'pk-123',
          creatorMlKemPublicKey: 'mlkem-pk-123',
        ),
        throwsA(isA<Exception>()),
      );

      expect(await groupRepo.getAllGroups(), isEmpty);
      expect(await groupRepo.getMembers('test-group-id'), isEmpty);
      expect(await groupRepo.getLatestKey('test-group-id'), isNull);
      expect(bridge.commandLog, contains('group:create'));
      expect(bridge.commandLog, isNot(contains('group.keygen')));
    },
  );

  test(
    'BB-005 unsupported group type rejection leaves no local group member key or event state',
    () async {
      bridge.responses['group:create'] = {
        'ok': false,
        'errorCode': 'INVALID_INPUT',
        'errorMessage': 'unsupported groupType: public',
      };
      final appendedEntries = <Map<String, Object?>>[];

      await expectLater(
        createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'BB-005 Unsupported Group',
          type: GroupType.chat,
          creatorPeerId: 'peer-bb005-creator',
          creatorPublicKey: 'pk-bb005-creator',
          creatorMlKemPublicKey: 'mlkem-pk-bb005-creator',
          creatorPrivateKey: 'sk-bb005-creator',
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
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('unsupported groupType: public'),
          ),
        ),
      );

      expect(await groupRepo.getAllGroups(), isEmpty);
      expect(await groupRepo.getMembers('bb005-unsupported-group'), isEmpty);
      expect(await groupRepo.getLatestKey('bb005-unsupported-group'), isNull);
      expect(appendedEntries, isEmpty);
      expect(bridge.commandLog, ['group:create']);
      expect(bridge.commandLog, isNot(contains('group.keygen')));
      expect(bridge.commandLog, isNot(contains('payload.sign')));
    },
  );

  test(
    'BB-013 group:create timeout does not persist group member or key',
    () async {
      final timeoutBridge = _TimeoutCommandBridge('group:create');

      await expectLater(
        createGroup(
          bridge: timeoutBridge,
          groupRepo: groupRepo,
          name: 'Timeout Group',
          type: GroupType.chat,
          creatorPeerId: 'peer-123',
          creatorPublicKey: 'pk-123',
          creatorMlKemPublicKey: 'mlkem-pk-123',
        ),
        throwsA(isA<Exception>()),
      );

      expect(await groupRepo.getAllGroups(), isEmpty);
      expect(await groupRepo.getMembers('test-group-id'), isEmpty);
      expect(await groupRepo.getLatestKey('test-group-id'), isNull);
      expect(timeoutBridge.commandLog, ['group:create']);
      expect(timeoutBridge.commandLog, isNot(contains('group.keygen')));
    },
  );

  test(
    'BB-015 native group:create failures leave no group member key or event state',
    () async {
      final failures = <String, Map<String, String>>{
        'NULL_RESPONSE': {
          'errorCode': 'NULL_RESPONSE',
          'errorMessage': 'Native bridge returned null',
        },
        'MISSING_PLUGIN': {
          'errorCode': 'MISSING_PLUGIN',
          'errorMessage': 'Rebuild the app with the updated native bridge.',
        },
        'PLATFORM_ERROR': {
          'errorCode': 'PLATFORM_ERROR',
          'errorMessage': 'Platform channel error',
        },
        'MALFORMED_RESPONSE': {
          'errorCode': 'MALFORMED_RESPONSE',
          'errorMessage': 'Native bridge returned malformed JSON',
        },
      };

      for (final failure in failures.entries) {
        final failureBridge = FakeBridge();
        final failureRepo = InMemoryGroupRepository();
        final appendedEntries = <Map<String, Object?>>[];
        failureBridge.responses['group:create'] = {
          'ok': false,
          ...failure.value,
        };

        await expectLater(
          createGroup(
            bridge: failureBridge,
            groupRepo: failureRepo,
            name: 'BB-015 ${failure.key}',
            type: GroupType.chat,
            creatorPeerId: 'peer-bb015',
            creatorPublicKey: 'pk-bb015',
            creatorMlKemPublicKey: 'mlkem-pk-bb015',
            creatorPrivateKey: 'sk-bb015',
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
          ),
          throwsA(isA<Exception>()),
        );

        expect(await failureRepo.getAllGroups(), isEmpty);
        expect(await failureRepo.getMembers('test-group-id'), isEmpty);
        expect(await failureRepo.getLatestKey('test-group-id'), isNull);
        expect(appendedEntries, isEmpty);
        expect(failureBridge.commandLog, ['group:create']);
        expect(failureBridge.commandLog, isNot(contains('group.keygen')));
        expect(failureBridge.commandLog, isNot(contains('payload.sign')));
      }
    },
  );

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
    'BB-004 stores coherent create state with canonical topic key and creator config',
    () async {
      const groupId = 'bb004-created-group-id';
      const creatorPeerId = 'peer-bb004-creator';
      const creatorUsername = 'BB-004 Creator';
      const creatorPublicKey = 'pk-bb004-creator';
      const creatorMlKemPublicKey = 'mlkem-pk-bb004-creator';
      const groupKey = 'bb004-created-group-key-base64';
      final bridgeGroupConfig = <String, dynamic>{
        'name': 'BB-004 Local Group',
        'groupType': 'chat',
        'createdBy': creatorPeerId,
        'createdAt': '2026-05-10T20:00:00Z',
        'members': [
          {
            'peerId': creatorPeerId,
            'role': 'admin',
            'publicKey': creatorPublicKey,
            'mlKemPublicKey': creatorMlKemPublicKey,
          },
        ],
      };

      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': groupId,
        'groupConfig': bridgeGroupConfig,
        'groupKey': groupKey,
        'keyEpoch': 1,
      };

      final result = await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'BB-004 Local Group',
        type: GroupType.chat,
        creatorPeerId: creatorPeerId,
        creatorPublicKey: creatorPublicKey,
        creatorMlKemPublicKey: creatorMlKemPublicKey,
        creatorUsername: creatorUsername,
      );

      expect(bridge.commandLog, ['group:create']);
      expect(result.id, groupId);
      expect(result.topicName, '/mknoon/group/$groupId');
      expect(result.createdBy, creatorPeerId);
      expect(result.myRole, GroupRole.admin);

      final savedGroup = await groupRepo.getGroup(groupId);
      expect(savedGroup, isNotNull);
      expect(savedGroup!.id, groupId);
      expect(savedGroup.name, 'BB-004 Local Group');
      expect(savedGroup.type, GroupType.chat);
      expect(savedGroup.topicName, '/mknoon/group/$groupId');
      expect(savedGroup.createdBy, creatorPeerId);
      expect(savedGroup.myRole, GroupRole.admin);

      final members = await groupRepo.getMembers(groupId);
      expect(members, hasLength(1));
      final creatorMember = members.single;
      expect(creatorMember.peerId, creatorPeerId);
      expect(creatorMember.username, creatorUsername);
      expect(creatorMember.role, MemberRole.admin);
      expect(creatorMember.publicKey, creatorPublicKey);
      expect(creatorMember.mlKemPublicKey, creatorMlKemPublicKey);

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
      expect(latestKey.encryptedKey, groupKey);
      final epochKey = await groupRepo.getKeyByGeneration(groupId, 1);
      expect(epochKey, isNotNull);
      expect(epochKey!.encryptedKey, groupKey);

      final createMessage =
          jsonDecode(bridge.sentMessages.single) as Map<String, dynamic>;
      expect(createMessage['cmd'], 'group:create');
      final createPayload = createMessage['payload'] as Map<String, dynamic>;
      expect(createPayload['name'], 'BB-004 Local Group');
      expect(createPayload['groupType'], 'chat');
      expect(createPayload['creatorPeerId'], creatorPeerId);
      expect(createPayload['creatorPublicKey'], creatorPublicKey);
      expect(createPayload['creatorMlKemPublicKey'], creatorMlKemPublicKey);

      final localConfig = <String, dynamic>{
        'name': savedGroup.name,
        'groupType': savedGroup.type.toValue(),
        'createdBy': savedGroup.createdBy,
        'members': [
          {
            'peerId': creatorMember.peerId,
            'role': creatorMember.role.toValue(),
            'publicKey': creatorMember.publicKey,
            'mlKemPublicKey': creatorMember.mlKemPublicKey,
          },
        ],
      };
      expect(localConfig['name'], bridgeGroupConfig['name']);
      expect(localConfig['groupType'], bridgeGroupConfig['groupType']);
      expect(localConfig['createdBy'], bridgeGroupConfig['createdBy']);

      final localMembers = localConfig['members'] as List<Map<String, Object?>>;
      final bridgeMembers = bridgeGroupConfig['members'] as List<Object?>;
      expect(localMembers, hasLength(bridgeMembers.length));
      final bridgeCreator = bridgeMembers.single as Map<String, Object?>;
      final localCreator = localMembers.single;
      expect(localCreator['peerId'], bridgeCreator['peerId']);
      expect(localCreator['role'], bridgeCreator['role']);
      expect(localCreator['publicKey'], bridgeCreator['publicKey']);
      expect(localCreator['mlKemPublicKey'], bridgeCreator['mlKemPublicKey']);
    },
  );

  test(
    'BB-016 create with description persists and matches bridge config',
    () async {
      const groupId = 'bb016-created-group-id';
      const creatorPeerId = 'peer-bb016-creator';
      const creatorPublicKey = 'pk-bb016-creator';
      const creatorMlKemPublicKey = 'mlkem-pk-bb016-creator';
      const description = 'BB-016 private planning description';
      final bridgeGroupConfig = <String, dynamic>{
        'name': 'BB-016 Local Group',
        'groupType': 'chat',
        'description': description,
        'createdBy': creatorPeerId,
        'createdAt': '2026-05-15T09:42:00Z',
        'members': [
          {
            'peerId': creatorPeerId,
            'role': 'admin',
            'publicKey': creatorPublicKey,
            'mlKemPublicKey': creatorMlKemPublicKey,
          },
        ],
      };

      bridge.responses['group:create'] = {
        'ok': true,
        'groupId': groupId,
        'topicName': '/mknoon/group/$groupId',
        'groupConfig': bridgeGroupConfig,
        'groupKey': 'bb016-created-group-key-base64',
        'keyEpoch': 1,
      };

      final result = await createGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        name: 'BB-016 Local Group',
        type: GroupType.chat,
        creatorPeerId: creatorPeerId,
        creatorPublicKey: creatorPublicKey,
        creatorMlKemPublicKey: creatorMlKemPublicKey,
        description: description,
      );

      expect(result.id, groupId);
      expect(result.description, description);

      final createMessage =
          jsonDecode(bridge.sentMessages.single) as Map<String, dynamic>;
      final createPayload = createMessage['payload'] as Map<String, dynamic>;
      expect(createPayload['description'], description);
      expect(
        bridgeGroupConfig['description'],
        createPayload['description'],
        reason: 'Dart create payload and returned Go config must not drift.',
      );

      final savedGroup = await groupRepo.getGroup(groupId);
      expect(savedGroup, isNotNull);
      expect(savedGroup!.description, description);
    },
  );

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
      expect(savedGroup.createdBy, creatorPeerId);
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
