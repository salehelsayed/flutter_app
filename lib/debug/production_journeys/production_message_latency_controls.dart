import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_fixture_controls.dart';
import 'production_journey_controller.dart';

/// Production message latency (Wave 4 round B): the original 1:1 send (A),
/// routing paths (R) and group publish (GP) benchmarks' send sequences on
/// production-created services. Each send returns the production timing
/// event it emitted (CHAT_MSG_SEND_TIMING / GROUP_SEND_MSG_TIMING). Unlike the
/// originals at HEAD, direct sends carry the recipient's ML-KEM key, so they
/// reach the transport instead of stopping at `encryption_required`.
void bindProductionMessageLatencyControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryRepository,
}) {
  if (controller.invocation.scenarioId != messageLatencyJourney) return;
  final events = <Map<String, Object?>>[];
  var overflow = false;
  final lease = installScopedE2EFlowEventSink((event) {
    if (event['event'] != 'CHAT_MSG_SEND_TIMING' &&
        event['event'] != 'GROUP_SEND_MSG_TIMING') {
      return;
    }
    if (events.length >= 1024) {
      overflow = true;
      return;
    }
    events.add(Map<String, Object?>.from(event));
  });
  controller.bindDisposer(lease.release);
  final usedKeys = <String>{};
  final runId = controller.invocation.runId;

  String string(Map<String, Object?> values, String key) {
    final result = values[key];
    if (result is! String || result.isEmpty) {
      throw FormatException('missing $key');
    }
    return result;
  }

  void requireRole(String role) {
    if (controller.invocation.role != role) {
      throw StateError('latency action belongs to $role');
    }
  }

  Future<ContactModel> preparedContact(String peerId) async {
    final contact = await contactRepository.getContact(peerId);
    if (contact == null ||
        contact.rendezvous != '/mknoon/production-journey/$runId') {
      throw StateError('latency peer is not prepared by this invocation');
    }
    return contact;
  }

  /// The timing events one sequential send emitted.
  Future<(T, List<Map<String, Object?>>)> observe<T>(
    String event,
    Future<T> Function() send,
  ) async {
    if (overflow) throw StateError('latency observation overflow');
    final start = events.length;
    final result = await send();
    return (
      result,
      [
        for (final e in events.skip(start))
          if (e['event'] == event) e,
      ],
    );
  }

  controller.bindAction('latency_send', (args) async {
    requireRole('alice');
    final key = '${string(args, 'case')}-${args['index']}';
    final cold = args['cold'];
    if (args['index'] is! int || cold is! bool || !usedKeys.add(key)) {
      throw StateError('latency send prerequisite rejected');
    }
    final contact = await preparedContact(string(args, 'peerId'));
    if (cold) {
      // The census's cold lever: drop the connection, then wait 300 ms.
      try {
        await callP2PPeerDisconnect(bridge, peerId: contact.peerId);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final ((result, message), timings) = await observe(
      'CHAT_MSG_SEND_TIMING',
      () => sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepository,
        targetPeerId: contact.peerId,
        text: 'latency-$runId-$key',
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        bridge: bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
      ),
    );
    return {
      'key': key,
      'cold': cold,
      'result': result.name,
      'messageId': message?.id,
      'timings': timings,
    };
  });

  controller.bindAction('latency_unreachable_contact', (_) async {
    requireRole('alice');
    if (!usedKeys.add('unreachable-contact')) {
      throw StateError('unreachable fixture claim rejected');
    }
    // A real identity with real keys that never comes online (the routing
    // journey's S7 fixture), replacing the originals' nonexistent peer.
    final identity =
        jsonDecode(
              await bridge.send(
                jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
              ),
            )
            as Map;
    final mlkem =
        jsonDecode(
              await bridge.send(
                jsonEncode({'cmd': 'mlkem.keygen', 'payload': {}}),
              ),
            )
            as Map;
    if (identity['ok'] != true || mlkem['ok'] != true) {
      throw StateError('native fixture identity generation failed');
    }
    final public = identity['identity'] as Map;
    final fixture = ContactModel(
      peerId: public['peerId'] as String,
      publicKey: public['publicKey'] as String,
      rendezvous: '/mknoon/production-journey/$runId',
      username: 'LatencyUnreachable',
      signature: 'fixture-$runId',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: mlkem['publicKey'] as String,
    );
    await contactRepository.addContact(fixture);
    return {'peerId': fixture.peerId};
  });

  controller.bindAction('latency_group_send', (args) async {
    requireRole('alice');
    final groupId = string(args, 'groupId');
    final key = 'GP-${args['index']}';
    if (args['index'] is! int || !usedKeys.add(key)) {
      throw StateError('group latency send prerequisite rejected');
    }
    final group = await groupRepository.getGroup(groupId);
    if (group == null ||
        group.name != productionFixtureGroupName(controller, group.type)) {
      throw StateError('latency group is not prepared by this invocation');
    }
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final transport = p2pService.currentState.peerId?.trim();
    final ((result, message), timings) = await observe(
      'GROUP_SEND_MSG_TIMING',
      () => sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupId: groupId,
        text: 'latency-$runId-$key',
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        senderDeviceId: transport,
        senderTransportPeerId: transport,
        mediaAttachmentRepo: mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: inviteDeliveryRepository,
      ),
    );
    return {
      'key': key,
      'result': result.name,
      'messageId': message?.id,
      'timings': timings,
    };
  });

  controller.bindAction('latency_node', (args) async {
    requireRole('bob');
    final operation = string(args, 'operation');
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final bool result;
    switch (operation) {
      case 'stop':
        result = await p2pService.stopNode();
      case 'start':
        result = await p2pService.startNode(
          identity.privateKey,
          identity.peerId,
        );
      default:
        throw StateError('unsupported latency node operation');
    }
    return {'operation': operation, 'result': result};
  });

  controller.bindAction('latency_rendezvous', (args) async {
    requireRole('bob');
    final operation = string(args, 'operation');
    final response = switch (operation) {
      'unregister' => await callP2PRendezvousUnregister(bridge),
      'register' => await callP2PRendezvousRegister(bridge),
      _ => throw StateError('unsupported rendezvous operation'),
    };
    return {
      'operation': operation,
      'ok': response['ok'] == true,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
  });
}
