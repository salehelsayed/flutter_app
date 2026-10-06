import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_group_removed_reaction_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fakes/in_memory_group_message_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';
import '../core/bridge/fake_bridge.dart';
import '../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';

class _Listener extends Fake implements GroupMessageListener {
  _Listener(this.changes);
  final Stream<ReactionChange> changes;
  @override
  Stream<ReactionChange> get groupReactionChangeStream => changes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime.utc(2026, 9, 28);
  const invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.e2e.production',
    scenarioId: groupCatalogRemovedReactionJourney,
    role: 'charlie',
    runId: 'run',
    nonce: 'nonce',
    values: {},
  );
  late Directory directory;
  late ProductionJourneyController controller;
  late InMemoryGroupRepository groups;
  late InMemoryGroupMessageRepository messages;
  late FakeReactionRepository reactions;
  late StreamController<ReactionChange> changes;
  var sequence = 0;
  late FakeBridge bridge;
  late FakeGroupReactionReplayOutboxRepository outbox;
  late FakeIdentityRepository identities;
  Future<Map<String, Object?>> command(
    String operation, [
    Map<String, Object?> args = const {},
  ]) => controller.execute({
    'invocation': invocation.toJson(),
    'sequence': ++sequence,
    'operation': operation,
    'arguments': args,
  });
  Future<Map<String, Object?>> arm({
    String message = 'target',
    String reactor = 'charlie',
  }) => command('catalog_arm_removed_reaction', {
    'messageId': message,
    'reactorPeerId': reactor,
  });
  const reaction = MessageReaction(
    id: 'reaction',
    messageId: 'target',
    emoji: '🔥',
    senderPeerId: 'charlie',
    timestamp: '2026-09-28T00:00:00Z',
    createdAt: '2026-09-28T00:00:01Z',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reaction-controls-');
    sequence = 0;
    bridge = FakeBridge();
    outbox = FakeGroupReactionReplayOutboxRepository();
    controller = ProductionJourneyController(
      directory: directory,
      profileId: invocation.profileId,
      invocation: invocation,
    );
    groups = InMemoryGroupRepository();
    messages = InMemoryGroupMessageRepository();
    reactions = FakeReactionRepository();
    changes = StreamController<ReactionChange>.broadcast(sync: true);
    await groups.saveGroup(
      GroupModel(
        id: 'group',
        name: 'Catalog private_removed_reaction_rejected run',
        type: GroupType.chat,
        topicName: 'topic',
        createdAt: at,
        createdBy: 'alice',
        myRole: GroupRole.admin,
      ),
    );
    for (final peer in ['alice', 'bob', 'charlie']) {
      await groups.saveMember(
        GroupMember(
          groupId: 'group',
          peerId: peer,
          username: 'Journey$peer',
          role: peer == 'alice' ? MemberRole.admin : MemberRole.writer,
          joinedAt: at,
        ),
      );
    }
    await messages.saveMessage(
      GroupMessage(
        id: 'target',
        groupId: 'group',
        senderPeerId: 'alice',
        senderUsername: 'Journeyalice',
        text: 'PL-010 Alice pre-removal reaction target run',
        timestamp: at,
        keyGeneration: 1,
        status: 'sent',
        isIncoming: false,
        createdAt: at,
      ),
    );
    identities = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: 'charlie'));
    bindProductionRemovedReactionControls(
      controller: controller,
      bridge: bridge,
      replayOutboxRepository: outbox,
      inviteDeliveryRepository: null,
      groupRepository: groups,
      messageRepository: messages,
      reactionRepository: reactions,
      identityRepository: identities,
      groupMessageListener: _Listener(changes.stream),
    );
    controller.foregroundPush.bind((_) async {});
    controller.markRuntimeReady();
    await controller.start();
  });
  tearDown(() async {
    controller.dispose();
    await changes.close();
    await directory.delete(recursive: true);
  });

  test(
    'exact arm observes independent real stream and repository rows',
    () async {
      final ready = await arm();
      expect(ready['initialReactionCount'], 0);
      expect(ready['armed'], true);
      await reactions.saveReaction(reaction);
      final before = await command('catalog_removed_reaction_snapshot');
      expect(before['reactions'], hasLength(1));
      expect(before['changes'], isEmpty);
      expect(before['outcomes'], isEmpty);
      changes.add(ReactionChange.upsert(reaction));
      final after = await command('catalog_removed_reaction_snapshot');
      expect(after['changes'], hasLength(1));
      expect(after['outcomes'], isEmpty);
      expect((after['reactions'] as List).single['id'], 'reaction');
      await expectLater(arm(), throwsStateError);
    },
  );
  test('snapshot cannot precede arm', () async {
    await expectLater(
      command('catalog_removed_reaction_snapshot'),
      throwsStateError,
    );
  });
  test('foreign message cannot arm', () async {
    await expectLater(arm(message: 'foreign'), throwsStateError);
  });
  test(
    'another group member cannot substitute for the expected reactor',
    () async {
      await expectLater(arm(reactor: 'bob'), throwsStateError);
    },
  );
  test('stale reaction cannot become a fresh operation observation', () async {
    await reactions.saveReaction(reaction);
    await expectLater(arm(), throwsStateError);
  });
  test('run-owned group and target text remain bound', () async {
    await groups.updateGroup(
      (await groups.getGroup(
        'group',
      ))!.copyWith(name: 'Catalog private_removed_reaction_rejected other-run'),
    );
    await expectLater(arm(), throwsStateError);
  });
  test('a same-group message with different target text cannot arm', () async {
    await messages.saveMessage(
      (await messages.getMessage(
        'target',
      ))!.copyWith(text: 'unrelated message'),
    );
    await expectLater(arm(), throwsStateError);
  });
  for (final role in ['alice', 'bob', 'charlie', 'sender']) {
    test('reaction runtime admission binds role $role', () async {
      final root = await Directory.systemTemp.createTemp('reaction-admission-');
      try {
        final file = File(
          '${root.path}/production-journey/runtime-config.json',
        );
        await file.parent.create();
        await file.writeAsString(
          jsonEncode({...invocation.toJson(), 'role': role}),
        );
        ProductionJourneyController? activate() =>
            ProductionJourneyController.forInstalledProfile(
              stateDirectory: root,
              isDebugMode: true,
              e2eTestMode: true,
              profileId: 'android.e2e.production',
            );
        if (role == 'sender') {
          expect(activate, throwsStateError);
        } else {
          final admitted = activate()!;
          expect(admitted.invocation.role, role);
          admitted.dispose();
        }
      } finally {
        await root.delete(recursive: true);
      }
    });
  }
  test(
    'actual production operation rejects removed Charlie and emits its real return',
    () async {
      await arm();
      await groups.removeMember('group', 'charlie');
      final result = await command('catalog_attempt_removed_reaction');
      expect(result['outcome'], 'notMember');
      expect(result['accepted'], false);
      expect(result['localReactionCountAfterAttempt'], 0);
      final snapshot = await command('catalog_removed_reaction_snapshot');
      expect(snapshot['memberPeerIds'], isNot(contains('charlie')));
      expect((snapshot['target'] as Map)['messageId'], 'target');
      expect(snapshot['reactions'], isEmpty);
      expect((snapshot['outcomes'] as List).single['outcome'], 'notMember');
      expect(bridge.sendCallCount, 0);
      expect(outbox.entries, isEmpty);
      await expectLater(
        command('catalog_attempt_removed_reaction'),
        throwsStateError,
      );
    },
  );
  test('attempt cannot precede observation arm', () async {
    await expectLater(
      command('catalog_attempt_removed_reaction'),
      throwsStateError,
    );
    expect(bridge.sendCallCount, 0);
  });
  test('a current member cannot use removed-member control to send', () async {
    await arm();
    await expectLater(
      command('catalog_attempt_removed_reaction'),
      throwsStateError,
    );
    expect(bridge.sendCallCount, 0);
    expect(
      (await command('catalog_removed_reaction_snapshot'))['outcomes'],
      isEmpty,
    );
  });
  test('caller cannot override the validated target', () async {
    await arm();
    await groups.removeMember('group', 'charlie');
    await expectLater(
      command('catalog_attempt_removed_reaction', {'messageId': 'other'}),
      throwsStateError,
    );
    expect(bridge.sendCallCount, 0);
  });
  test('identity change after arm refuses the attempt', () async {
    await arm();
    await groups.removeMember('group', 'charlie');
    identities.seed(FakeIdentityRepository.makeIdentity(peerId: 'bob'));
    await expectLater(
      command('catalog_attempt_removed_reaction'),
      throwsStateError,
    );
    expect(bridge.sendCallCount, 0);
  });
  test('changed old target refuses the attempt', () async {
    await arm();
    await groups.removeMember('group', 'charlie');
    await messages.saveMessage(
      (await messages.getMessage('target'))!.copyWith(text: 'foreign'),
    );
    await expectLater(
      command('catalog_attempt_removed_reaction'),
      throwsStateError,
    );
    expect(bridge.sendCallCount, 0);
  });
  test('broken receiver stream cannot authorize an attempt', () async {
    await arm();
    await groups.removeMember('group', 'charlie');
    changes.addError(StateError('listener failure'));
    await expectLater(
      command('catalog_attempt_removed_reaction'),
      throwsStateError,
    );
    expect(bridge.sendCallCount, 0);
  });
}
