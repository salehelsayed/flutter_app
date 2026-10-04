import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_catalog_controls.dart';
import 'production_group_reaction_capture.dart';
import 'production_journey_controller.dart';

typedef ProductionReactionToggle =
    Future<Map<String, Object?>> Function({
      required String groupId,
      required String messageId,
      required String reactorPeerId,
    });

/// Arms observations only after the exact UI-authored target exists. PL-009
/// sends through UI. RT-001 alone admits its fixed, once-only protocol sequence.
void bindProductionGroupReactionControls({
  required ProductionJourneyController controller,
  required GroupRepository groupRepository,
  required GroupMessageRepository messageRepository,
  required ReactionRepository reactionRepository,
  required IdentityRepository identityRepository,
  required GroupMessageListener groupMessageListener,
  ProductionReactionToggle? executeToggle,
}) {
  final scenario = controller.invocation.scenarioId;
  final isToggle = scenario == groupCatalogReactionToggleJourney;
  if (scenario != groupCatalogReactionJourney &&
      scenario != groupCatalogMediaReactionJourney &&
      !isToggle) {
    return;
  }
  ProductionGroupReactionCapture? capture;
  String? boundGroup, boundMessage, boundReactor;
  var toggleAttempted = false;
  controller.bindDisposer(() => capture?.dispose());
  controller.bindAction('catalog_arm_reaction', (args) async {
    if (capture != null) throw StateError('reaction observation already armed');
    final messageId = args['messageId'];
    final reactorPeerId = args['reactorPeerId'];
    if (messageId is! String || reactorPeerId is! String) {
      throw StateError('reaction target identity missing');
    }
    final groups = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (groups.length != 1) throw StateError('exact run group missing');
    final group = groups.single;
    final target = await messageRepository.getMessage(messageId);
    final reactor = await groupRepository.getMember(group.id, reactorPeerId);
    final identity = await identityRepository.loadIdentity();
    if (target == null ||
        target.groupId != group.id ||
        target.senderPeerId != group.createdBy ||
        target.text !=
            (isToggle
                ? 'RT-001 Alice reaction toggle target ${controller.invocation.runId}'
                : 'PL-009 Alice reaction target ${controller.invocation.runId}') ||
        reactor?.username != 'Journeybob' ||
        identity == null ||
        (controller.invocation.role == 'bob') !=
            (identity.peerId == reactorPeerId) ||
        await groupRepository.getMember(group.id, identity.peerId) == null) {
      throw StateError('reaction observation target or actor rejected');
    }
    if ((await reactionRepository.getReactionsForMessage(
      messageId,
    )).isNotEmpty) {
      throw StateError('reaction target is not initially empty');
    }
    boundGroup = group.id;
    boundMessage = messageId;
    boundReactor = reactorPeerId;
    capture = ProductionGroupReactionCapture(
      groupId: group.id,
      messageId: messageId,
      senderPeerId: reactorPeerId,
      changes: groupMessageListener.groupReactionChangeStream,
    );
    return {
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'groupId': boundGroup,
      'messageId': boundMessage,
      'reactorPeerId': boundReactor,
      'armed': true,
      'initialReactionCount': 0,
    };
  });
  controller.bindAction('catalog_reaction_snapshot', (_) async {
    final observation = capture;
    if (observation == null) throw StateError('reaction observation not armed');
    return {
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'groupId': boundGroup,
      'messageId': boundMessage,
      'reactorPeerId': boundReactor,
      ...observation.snapshot(),
      'reactions': [
        for (final reaction in await reactionRepository.getReactionsForMessage(
          boundMessage!,
        ))
          reaction.toMap(),
      ],
    };
  });
  if (isToggle && controller.invocation.role == 'bob') {
    controller.bindAction('catalog_toggle_reaction', (args) async {
      if (args.isNotEmpty ||
          capture == null ||
          toggleAttempted ||
          executeToggle == null) {
        throw StateError('toggle operation refused');
      }
      capture!.snapshot(); // Expiry/overflow/error cannot authorize a mutation.
      final identity = await identityRepository.loadIdentity();
      if (identity?.peerId != boundReactor) {
        throw StateError('toggle actor changed');
      }
      toggleAttempted = true;
      return {
        'runId': controller.invocation.runId,
        'role': controller.invocation.role,
        'groupId': boundGroup,
        'messageId': boundMessage,
        'reactorPeerId': boundReactor,
        ...await executeToggle(
          groupId: boundGroup!,
          messageId: boundMessage!,
          reactorPeerId: boundReactor!,
        ),
      };
    });
  }
}
