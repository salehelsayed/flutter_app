import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_group_reaction_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
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

/// The L-01 media journey arms on its own original caption.
const _targetText = 'L-01 Alice media reaction target run';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime.utc(2026, 9, 28);
  const invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.e2e.main',
    scenarioId: groupCatalogMediaReactionJourney,
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
        name: 'Catalog private_media_reaction_roundtrip run',
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
        text: _targetText,
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

  test('the L-01 media target arms its reaction observation', () async {
    final ready = await arm();
    expect(ready['armed'], true);
    expect(ready['initialReactionCount'], 0);
  });
}
