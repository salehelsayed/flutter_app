import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_fixture_controls.dart';
import 'production_journey_controller.dart';

/// Exact protocol prerequisites and read-only observations on production-owned
/// objects. Ordinary sends/deletion/navigation remain UI operations. Fixed
/// recording/upload/load/registration-gap fixtures preserve the original
/// controlled cases; they cannot submit arbitrary messages or build a graph.
void bindProductionRoutingJourneyControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required ActiveConversationTracker conversationTracker,
  required ActiveConversationTracker groupConversationTracker,
}) {
  if (controller.invocation.scenarioId != routingSmokeJourney) return;
  final events = <Map<String, Object?>>[];
  var overflow = false;
  final usedCases = <String>{};
  final lease = installScopedE2EFlowEventSink((event) {
    if (!{
      'CHAT_MSG_SEND_TIMING',
      'VOICE_SEND_TIMING',
      'GROUP_SEND_MSG_TIMING',
      'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
    }.contains(event['event'])) {
      return;
    }
    if (events.length >= 1024) {
      overflow = true;
      return;
    }
    events.add(Map<String, Object?>.from(event));
  });
  controller.bindDisposer(lease.release);
  String string(Map<String, Object?> values, String key) {
    final result = values[key];
    if (result is! String || result.isEmpty) {
      throw FormatException('missing $key');
    }
    return result;
  }

  Future<ContactModel> contact(String peer) async {
    final result = await contactRepository.getContact(peer);
    if (result == null ||
        result.rendezvous !=
            '/mknoon/production-journey/${controller.invocation.runId}') {
      throw StateError('routing peer is not prepared by this invocation');
    }
    return result;
  }

  Future<void> group(String id) async {
    final result = await groupRepository.getGroup(id);
    if (result == null ||
        result.name != productionFixtureGroupName(controller, result.type)) {
      throw StateError('routing group is not prepared by this invocation');
    }
  }

  controller.bindAction('routing_snapshot', (args) async {
    if (overflow) throw StateError('routing observation overflow');
    final peers = args['peerIds'];
    final groups = args['groupIds'];
    if (peers is! List ||
        groups is! List ||
        [...peers, ...groups].any((v) => v is! String || v.isEmpty)) {
      throw const FormatException('exact routing identities required');
    }
    final rows = <Map<String, Object?>>[];
    final tombstones = <Map<String, Object?>>[];
    final messageIds = args['messageIds'] ?? const <String>[];
    if (messageIds is! List || messageIds.any((v) => v is! String)) {
      throw const FormatException('exact message identities required');
    }
    for (final id in messageIds.cast<String>().toSet()) {
      final row = await messageRepository.getMessage(id);
      if (row == null || !peers.contains(row.contactPeerId)) {
        throw StateError('message observation is outside prepared peers');
      }
      await contact(row.contactPeerId);
      tombstones.add({
        'id': row.id,
        'contactPeerId': row.contactPeerId,
        'deletedAt': row.deletedAt,
        'status': row.status,
      });
    }
    for (final peer in peers.cast<String>().toSet()) {
      await contact(peer);
      for (final row in await messageRepository.getMessagesForContact(peer)) {
        rows.add({
          'id': row.id,
          'conversationId': peer,
          'lane': 'direct',
          'text': row.text,
          'incoming': row.isIncoming,
          'status': row.status,
          'transport': row.transport,
          'timestamp': row.timestamp,
          'createdAt': row.createdAt,
          'readAt': row.readAt,
          'deletedAt': row.deletedAt,
          'attachments':
              (await mediaAttachmentRepository.getAttachmentsForMessage(
                    row.id,
                    owner: MediaOwnerLane.direct,
                  ))
                  .map(
                    (a) => {
                      'id': a.id,
                      'mime': a.mime,
                      'size': a.size,
                      'mediaType': a.mediaType,
                      'contentHash': a.contentHash,
                      'encryptionScheme': a.encryptionScheme,
                    },
                  )
                  .toList(),
        });
      }
    }
    final keys = <String, int?>{};
    for (final id in groups.cast<String>().toSet()) {
      await group(id);
      keys[id] = (await groupRepository.getLatestKey(id))?.keyGeneration;
      for (final row in await groupMessageRepository.getMessagesPage(
        id,
        limit: 500,
      )) {
        rows.add({
          'id': row.id,
          'conversationId': id,
          'lane': 'group',
          'text': row.text,
          'incoming': row.isIncoming,
          'status': row.status,
          'keyGeneration': row.keyGeneration,
          'timestamp': row.timestamp.toUtc().toIso8601String(),
          'createdAt': row.createdAt.toUtc().toIso8601String(),
          'readAt': row.readAt?.toUtc().toIso8601String(),
        });
      }
    }
    return {
      'messages': rows,
      'tombstones': tombstones,
      'localPeers': {
        for (final peer in peers.cast<String>())
          peer: p2pService.isLocalPeer(peer),
      },
      'events': List.of(events),
      'groupKeys': keys,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'activePeerId': conversationTracker.activePeerId,
      'activeGroupId': groupConversationTracker.activePeerId,
      'node': p2pService.currentState.toJson(),
    };
  });

  controller.bindAction('routing_prepare_unreachable_contact', (_) async {
    if (controller.invocation.role != 'alice' || !usedCases.add('S7-contact')) {
      throw StateError('unreachable fixture claim rejected');
    }
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
      rendezvous: '/mknoon/production-journey/${controller.invocation.runId}',
      username: 'AllPathsFailSmoke',
      signature: 'fixture-${controller.invocation.runId}',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: mlkem['publicKey'] as String,
    );
    await contactRepository.addContact(fixture);
    return {'peerId': fixture.peerId};
  });

  controller.bindAction('routing_node_control', (args) async {
    final operation = string(args, 'operation');
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final elapsed = Stopwatch()..start();
    final before = p2pService.currentState.toJson();
    final bool result;
    switch (operation) {
      case 'stop':
        result = await p2pService.stopNode();
      case 'start':
        result = await p2pService.startNode(
          identity.privateKey,
          identity.peerId,
        );
      case 'start_core':
        result = await p2pService.startNodeCore(
          identity.privateKey,
          identity.peerId,
        );
      case 'health_check':
        await p2pService.performImmediateHealthCheck();
        result = true;
      case 'warm_background':
        await p2pService.warmBackground();
        result = true;
      default:
        throw StateError('unsupported routing node prerequisite');
    }
    return {
      'operation': operation,
      'result': result,
      'elapsedMs': elapsed.elapsedMilliseconds,
      'before': before,
      'after': p2pService.currentState.toJson(),
    };
  });

  controller.bindAction('routing_protocol_case', (args) async {
    final id = string(args, 'caseId');
    if (controller.invocation.role != 'alice' ||
        !{'S11', 'S12', 'S13', 'S15', 'G7'}.contains(id) ||
        !usedCases.add(id)) {
      throw StateError('routing protocol case claim rejected');
    }
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final beforeEvents = events.length;
    final elapsed = Stopwatch()..start();
    if (id == 'G7') {
      final groupId = string(args, 'groupId');
      await group(groupId);
      final before = await groupRepository.getLatestKey(groupId);
      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepository,
        groupId: groupId,
        selfPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        sendP2PMessage: p2pService.sendMessage,
      );
      return {
        'rotationMs': elapsed.elapsedMilliseconds,
        'rotated': result.rotated,
        'beforeGeneration': before?.keyGeneration,
        'afterGeneration': result.key?.keyGeneration,
      };
    }
    final peer = await contact(string(args, 'peerId'));
    if (peer.mlKemPublicKey?.isNotEmpty != true) {
      throw StateError('prepared peer lacks encryption key');
    }
    final messageIds = <String>[];
    final outcomes = <String>[];
    if (id == 'S13' || id == 'S15') {
      for (var i = 1; i <= (id == 'S13' ? 10 : 1); i++) {
        final messageId = 'routing-${controller.invocation.runId}-$id-$i';
        if (await messageRepository.getMessage(messageId) != null) {
          throw StateError('routing case message already exists');
        }
        final result = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepository,
          targetPeerId: peer.peerId,
          text: id == 'S13'
              ? 'S13: rapid msg $i'
              : 'S15: rendezvous-gap relay msg',
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          bridge: bridge,
          recipientMlKemPublicKey: peer.mlKemPublicKey,
          messageId: messageId,
          preassignedMessageIdIsFresh: true,
        );
        outcomes.add(result.$1.name);
        messageIds.add(messageId);
      }
    } else {
      final files = await controller.directory.createTemp('routing-$id-');
      if (id == 'S11') {
        final messageId = 'routing-${controller.invocation.runId}-S11';
        if (await messageRepository.getMessage(messageId) != null) {
          throw StateError('routing voice message already exists');
        }
        final file = File('${files.path}/voice.mp4');
        await file.writeAsBytes(List.filled(10240, 0x42), flush: true);
        final result = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepository,
          targetPeerId: peer.peerId,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          recording: AudioRecording(
            filePath: file.path,
            durationMs: 2000,
            sizeBytes: 10240,
          ),
          bridge: bridge,
          recipientMlKemPublicKey: peer.mlKemPublicKey,
          mediaAttachmentRepo: mediaAttachmentRepository,
          waveform: [0.1, 0.5, 0.8, 0.3, 0.6],
          messageId: messageId,
          preassignedMessageIdIsFresh: true,
        );
        outcomes.add(result.$1.name);
        messageIds.add(messageId);
      } else {
        final uploads = <Map<String, Object?>>[];
        for (final sizeMb in [1, 5]) {
          final file = File('${files.path}/$sizeMb.bin');
          await file.writeAsBytes(
            List.filled(sizeMb * 1024 * 1024, sizeMb == 1 ? 0xAB : 0xCD),
            flush: true,
          );
          final uploadElapsed = Stopwatch()..start();
          Object? result;
          String? error;
          try {
            result = await callP2PMediaUpload(
              bridge,
              id: 'routing-${controller.invocation.runId}-S12-$sizeMb',
              toPeerId: peer.peerId,
              mime: 'application/octet-stream',
              filePath: file.path,
            );
          } catch (failure) {
            error = '$failure';
          }
          uploads.add({
            'sizeBytes': sizeMb * 1024 * 1024,
            'uploadMs': uploadElapsed.elapsedMilliseconds,
            'result': result,
            'error': ?error,
          });
        }
        return {
          'uploads': uploads,
          'events': events.skip(beforeEvents).toList(),
        };
      }
    }
    return {
      'caseId': id,
      'messageIds': messageIds,
      'outcomes': outcomes,
      'elapsedMs': elapsed.elapsedMilliseconds,
      'events': events.skip(beforeEvents).toList(),
    };
  });
}
