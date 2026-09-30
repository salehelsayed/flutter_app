import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'production_journey_controller.dart';

const _fixturePng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=';

/// Seeds only fixed local fixtures from the retained private-media harness.
/// Production owns the SQL connection, repositories, file manager, lifecycle
/// and viewer. UI actions are external; these controls never open a route or
/// invoke a viewer/controller. Mutation receipts are committed row snapshots
/// published by the existing production repository.
void bindProductionPrivateMediaControls({
  required ProductionJourneyController controller,
  required sqlcipher.Database database,
  required MessageRepository messageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  if (controller.invocation.scenarioId != privateMediaJourney) return;
  final manifest = File(
    '${controller.directory.path}/private-local-fixtures.json',
  );
  final owned = <String, Map<String, Object?>>{};
  final committed = <Map<String, Object?>>[];
  var overflow = false;
  String? contactId;
  if (manifest.existsSync()) {
    final value = Map<String, Object?>.from(
      jsonDecode(manifest.readAsStringSync()) as Map,
    );
    if (value['runId'] != controller.invocation.runId ||
        value['role'] != controller.invocation.role) {
      throw StateError(
        'private fixture manifest belongs to another invocation',
      );
    }
    contactId = value['peerId']! as String;
    for (final item in value['fixtures']! as List) {
      final row = Map<String, Object?>.from(item as Map);
      final id = row['id']! as String;
      if (!id.startsWith('private-${controller.invocation.runId}-')) {
        throw StateError('foreign private fixture identity');
      }
      owned[id] = row;
    }
  }
  if (messageRepository is! MessageRepositoryChangeSource) {
    throw StateError('production committed-mutation stream missing');
  }
  final changes = (messageRepository as MessageRepositoryChangeSource)
      .messageChanges
      .listen((row) {
        if (!owned.containsKey(row.id)) return;
        if (committed.length >= 256) {
          overflow = true;
          return;
        }
        committed.add({
          'messageId': row.id,
          'state': row.privateMediaState.wireValue,
          'hiddenAt': row.hiddenAt,
          'deletedAt': row.deletedAt,
          'observedAtMicros': DateTime.now().toUtc().microsecondsSinceEpoch,
          'source': 'production-repository-committed-change',
        });
      });
  controller.bindDisposer(() => unawaited(changes.cancel()));

  controller.bindAction('prepare_private_local_fixtures', (args) async {
    if (owned.isNotEmpty || manifest.existsSync()) {
      throw StateError('private fixtures already prepared');
    }
    final peer = args['peerId'];
    final set = args['set'];
    if (set !=
        (controller.invocation.role == 'alice'
            ? 'sender_pending'
            : 'projection')) {
      throw StateError('private fixture set is not assigned to this role');
    }
    if (peer is! String || !{'projection', 'sender_pending'}.contains(set)) {
      throw const FormatException('exact private fixture set required');
    }
    final contact = await contactRepository.getContact(peer);
    final identity = await identityRepository.loadIdentity();
    if (identity == null ||
        contact?.rendezvous !=
            '/mknoon/production-journey/${controller.invocation.runId}') {
      throw StateError('private fixture peer not owned by this invocation');
    }
    contactId = peer;
    final names = set == 'projection'
        ? ['outgoing', 'protected_thumbnail', 'incoming', 'terminal']
        : ['sender_pending'];
    final bytes = base64Decode(_fixturePng);
    final fixtureFile = File(
      '${controller.directory.path}/private-fixture.png',
    );
    await fixtureFile.writeAsBytes(bytes, flush: true);
    final now = DateTime.now().toUtc();
    for (final name in names) {
      final id = 'private-${controller.invocation.runId}-$name';
      if (await messageRepository.getMessage(id) != null) {
        throw StateError('fixture row already exists');
      }
      final incoming = name == 'incoming' || name == 'terminal';
      final terminal = name == 'terminal';
      final parent = ConversationMessage(
        id: id,
        contactPeerId: peer,
        senderPeerId: incoming ? peer : identity.peerId,
        text: '',
        timestamp: now.toIso8601String(),
        createdAt: now.toIso8601String(),
        status: 'sent',
        isIncoming: incoming,
        privateMediaPolicy: {'outgoing', 'protected_thumbnail'}.contains(name)
            ? const PrivateMediaPolicy.protected()
            : const PrivateMediaPolicy.viewOnce(),
        privateMediaState: terminal
            ? PrivateMediaLifecycleState.consumed
            : PrivateMediaLifecycleState.available,
        privateMediaReceivedAtMs: incoming ? now.millisecondsSinceEpoch : null,
        privateMediaRevealedAtMs: terminal ? now.millisecondsSinceEpoch : null,
        privateMediaTerminalAtMs: terminal ? now.millisecondsSinceEpoch : null,
        privateMediaClockHighWaterMs: incoming
            ? now.millisecondsSinceEpoch
            : null,
      );
      final attachmentId = '$id-attachment';
      final String stored;
      final String absolute;
      if (incoming) {
        stored = mediaFileManager.relativePathForAttachment(
          contactPeerId: peer,
          blobId: attachmentId,
          mime: 'image/png',
        );
        absolute = await mediaFileManager.localPathForAttachment(
          contactPeerId: peer,
          blobId: attachmentId,
          mime: 'image/png',
        );
        final root = await mediaFileManager.trustedMediaRootPath();
        if (absolute !=
            '$root${Platform.pathSeparator}$peer${Platform.pathSeparator}$attachmentId.png') {
          throw StateError(
            'incoming fixture outside canonical media owner root',
          );
        }
        await File(absolute).writeAsBytes(bytes, flush: true);
      } else {
        stored = await mediaFileManager.copyToDurableStorage(
          sourceFilePath: fixtureFile.path,
          messageId: id,
          attachmentId: attachmentId,
          mime: 'image/png',
        );
        absolute = await mediaFileManager.resolveStoredPath(stored);
        final root = await mediaFileManager.trustedPendingUploadRootPath();
        if (absolute !=
            '$root${Platform.pathSeparator}$id${Platform.pathSeparator}$attachmentId.png') {
          throw StateError(
            'fixture bytes outside production pending owner root',
          );
        }
      }
      // Retain the production no-byte fallback alongside plan 301 pixels.
      if (name == 'outgoing') await File(absolute).delete();
      owned[id] = {
        'id': id,
        'name': name,
        'attachmentId': attachmentId,
        'storedPath': stored,
        'storageOwner': incoming ? 'canonical_incoming' : 'pending_upload',
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
      await messageRepository.saveMessage(parent);
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: id,
        mime: 'image/png',
        size: bytes.length,
        mediaType: 'image',
        localPath: stored,
        downloadStatus: name == 'sender_pending' ? 'upload_pending' : 'done',
        createdAt: now.toIso8601String(),
        contentHash: sha256.convert(bytes).toString(),
        ownerLane: MediaOwnerLane.direct,
      );
      // Fixture-only SQL seed, as in the original harness. The guarded media
      // insert helper is incoming-only and must not be weakened for a fixture.
      await dbInsertMediaAttachment(database, attachment.toMap());
    }
    await manifest.writeAsString(
      jsonEncode({
        'runId': controller.invocation.runId,
        'role': controller.invocation.role,
        'peerId': peer,
        'set': set,
        'fixtures': owned.values.toList(),
      }),
      flush: true,
    );
    return {
      'set': set,
      'messageIds': owned.keys.toList(),
      'fixtureSha256': sha256.convert(bytes).toString(),
    };
  });

  controller.bindAction('private_local_snapshot', (_) async {
    if (owned.isEmpty || contactId == null || overflow) {
      throw StateError('private observations unavailable');
    }
    final rows = <Map<String, Object?>>[];
    for (final fixture in owned.values) {
      final id = fixture['id']! as String;
      final parent = await messageRepository.getMessage(id);
      if (parent == null || parent.contactPeerId != contactId) {
        throw StateError('private fixture parent missing');
      }
      final sql = await database.query(
        'messages',
        columns: [
          'id',
          'is_incoming',
          'private_media_policy_version',
          'private_media_mode',
          'private_media_state',
          'hidden_at',
          'deleted_at',
        ],
        where: 'id = ?',
        whereArgs: [id],
      );
      final attachments = await database.query(
        'media_attachments',
        columns: [
          'id',
          'message_id',
          'owner_lane',
          'download_status',
          'size',
          'local_path',
        ],
        where: 'id = ? AND message_id = ? AND owner_lane = ?',
        whereArgs: [fixture['attachmentId'], id, MediaOwnerLane.direct.dbValue],
      );
      final file = File(
        await mediaFileManager.resolveStoredPath(
          fixture['storedPath']! as String,
        ),
      );
      final exists = await file.exists();
      rows.add({
        'id': id,
        'name': fixture['name'],
        'storageOwner': fixture['storageOwner'],
        'sql': sql,
        'attachments': [
          for (final a in attachments)
            {
              for (final entry in a.entries)
                if (entry.key != 'local_path') entry.key: entry.value,
              'exactOwnedPath': a['local_path'] == fixture['storedPath'],
            },
        ],
        'repositoryAttachmentCount':
            (await mediaAttachmentRepository.getAttachmentsForMessage(
              id,
              owner: MediaOwnerLane.direct,
            )).length,
        'fileExists': exists,
        if (exists)
          'fileSha256': sha256.convert(await file.readAsBytes()).toString(),
        'fixtureSha256': fixture['sha256'],
      });
    }
    final projection = _privateProjection(
      navigatorKey,
      contactId!,
      owned.keys.toSet(),
    );
    return {
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'peerId': contactId,
      'rows': rows,
      'committed': List.of(committed),
      'projection': projection,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
    };
  });
}

Map<String, Object?> _privateProjection(
  GlobalKey<NavigatorState> navigator,
  String peer,
  Set<String> ids,
) {
  final conversations = <Element>[];
  final viewers = <Element>[];
  void walk(Element element, void Function(Element) visit) {
    if (element.widget case Offstage(offstage: true)) return;
    visit(element);
    element.visitChildren((child) => walk(child, visit));
  }

  final context = navigator.currentContext;
  if (context is Element) {
    walk(context, (e) {
      if (e.widget case ConversationScreen(
        contactPeerId: final id,
      ) when id == peer) {
        conversations.add(e);
      }
      if (e.widget is DirectPrivateMediaViewer) viewers.add(e);
    });
  }
  final rows = <Map<String, Object?>>[];
  for (final id in ids) {
    final matching = <Element>[];
    for (final c in conversations) {
      walk(c, (e) {
        if (e.widget.key == ValueKey('msg-$id')) matching.add(e);
      });
    }
    final slots = <Element>[];
    var cards = 0, decorated = 0, inside = 0, images = 0, decorations = 0;
    final sizes = <Map<String, double>>[];
    final actions = <Map<String, Object?>>[];
    for (final row in matching) {
      walk(row, (e) {
        if (e.widget is LetterCard) cards++;
        if (e.widget.key == ValueKey('private-media-slot-$id')) slots.add(e);
        if (e.widget.key == ValueKey('private-media-decorated-body-$id')) {
          decorated++;
          walk(e, (child) {
            if (child.widget.key == ValueKey('private-media-slot-$id')) {
              inside++;
            }
          });
        }
      });
    }
    for (final slot in slots) {
      final render = slot.findRenderObject();
      if (render is RenderBox && render.hasSize) {
        sizes.add({'width': render.size.width, 'height': render.size.height});
      }
      walk(slot, (e) {
        const observedKeys = {
          'private-media-open',
          'private-media-thumbnail-tile',
          'private-media-card-visual',
          'private-terminal-view-once-consumed-summary',
          'private-action-deleteForMe',
        };
        final key = e.widget.key;
        if (key is ValueKey<String> && observedKeys.contains(key.value)) {
          final render = e.findRenderObject();
          actions.add({
            'key': key.value,
            if (render is RenderBox && render.hasSize) ...{
              'width': render.size.width,
              'height': render.size.height,
            },
          });
        }
        if (e.widget is Image ||
            e.widget is RawImage ||
            e.widget.runtimeType.toString() == 'MediaGrid') {
          images++;
        }
        if (e.widget case DecoratedBox(
          decoration: BoxDecoration(image: final image),
        ) when image != null) {
          decorations++;
        }
      });
    }
    rows.add({
      'id': id,
      'rows': matching.length,
      'letterCards': cards,
      'slots': slots.length,
      'decoratedBodies': decorated,
      'slotsInsideBodies': inside,
      'slotSizes': sizes,
      'imageWidgets': images,
      'decorationImages': decorations,
      'actions': actions,
    });
  }
  return {
    'conversations': conversations.length,
    'viewers': viewers.length,
    'rows': rows,
  };
}
