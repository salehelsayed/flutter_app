import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_group_reaction_controls.dart';
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
    scenarioId: groupCatalogReactionJourney,
    role: 'alice',
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
    String reactor = 'bob',
  }) => command('catalog_arm_reaction', {
    'messageId': message,
    'reactorPeerId': reactor,
  });
  const reaction = MessageReaction(
    id: 'reaction',
    messageId: 'target',
    emoji: '🔥',
    senderPeerId: 'bob',
    timestamp: '2026-09-28T00:00:00Z',
    createdAt: '2026-09-28T00:00:01Z',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reaction-controls-');
    sequence = 0;
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
        name: 'Catalog private_reaction_roundtrip run',
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
        text: 'PL-009 Alice reaction target run',
        timestamp: at,
        keyGeneration: 1,
        status: 'sent',
        isIncoming: false,
        createdAt: at,
      ),
    );
    final identities = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: 'alice'));
    bindProductionGroupReactionControls(
      controller: controller,
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
      final before = await command('catalog_reaction_snapshot');
      expect(before['reactions'], hasLength(1));
      expect(before['changes'], isEmpty);
      expect(before['outcomes'], isEmpty);
      changes.add(ReactionChange.upsert(reaction));
      final after = await command('catalog_reaction_snapshot');
      expect(after['changes'], hasLength(1));
      expect(after['outcomes'], isEmpty);
      expect((after['reactions'] as List).single['id'], 'reaction');
      await expectLater(arm(), throwsStateError);
    },
  );
  test('snapshot cannot precede arm', () async {
    await expectLater(command('catalog_reaction_snapshot'), throwsStateError);
  });
  test('foreign message cannot arm', () async {
    await expectLater(arm(message: 'foreign'), throwsStateError);
  });
  test(
    'another group member cannot substitute for the expected reactor',
    () async {
      await expectLater(arm(reactor: 'charlie'), throwsStateError);
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
      ))!.copyWith(name: 'Catalog private_reaction_roundtrip other-run'),
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
}
