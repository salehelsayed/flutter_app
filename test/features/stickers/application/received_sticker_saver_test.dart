import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/stickers/application/account_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/received_sticker_saver.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

Matcher _error(CustomStickerErrorCode code) =>
    isA<CustomStickerException>().having((e) => e.code, 'code', code);

img.Image _pixels(int red) {
  final image = img.Image(width: 16, height: 16, numChannels: 4);
  for (final pixel in image) {
    pixel.setRgba(red, pixel.x * 8, pixel.y * 8, 255);
  }
  return image;
}

Uint8List _animation() {
  final image = _pixels(20)..frameDuration = 83;
  image.addFrame(_pixels(220)..frameDuration = 84);
  return img.encodeWebP(image, lossless: true);
}

class _Files extends MediaFileManager {
  _Files(this.documents, this.snapshots);
  final Directory documents;
  final Directory snapshots;
  int leases = 0;

  @override
  Future<String> resolveStoredPath(String path) async =>
      p.isAbsolute(path) ? path : p.join(documents.path, path);

  @override
  Future<String> groupForwardSnapshotRootPath() async => snapshots.path;

  @override
  Future<MediaForwardSnapshotLease> createMediaForwardSnapshotLease() {
    leases++;
    return super.createMediaForwardSnapshotLease();
  }
}

class _Gate {
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> hold() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }

  void open() {
    if (!release.isCompleted) release.complete();
  }
}

// Same real current rows, but deliberately no authoritative deletion capability.
// The legacy nullable lookup inherits the repository's unknown/default null.
class _MissingDeletionAuthority extends GroupMessageRepository {
  _MissingDeletionAuthority(this.rows);
  final GroupMessageRepository rows;

  @override
  Future<GroupMessage?> getMessage(String id) => rows.getMessage(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnknownDeletionAuthority extends _MissingDeletionAuthority
    implements GroupMessageLocalDeletionAuthority {
  _UnknownDeletionAuthority(super.rows);

  @override
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  ) async => GroupMessageLocalDeletionState.unknown;
}

class _Fixture {
  late Directory root, temporary, documents, otherDocuments, snapshots;
  late Database db, otherDb;
  late _Files files;
  late AccountCustomStickerLibrary library;
  final attachments = InMemoryMediaAttachmentRepository();
  final groups = InMemoryGroupMessageRepository();
  final groupRepository = InMemoryGroupRepository();
  final delegates = <SqliteCustomStickerLibrary>[];
  final gates = <_Gate>[];
  final pending = <Future<Object?>>[];
  late ConversationMessage parent;
  bool active = true;
  String account = 'A';
  int editorCalls = 0;
  int parentReads = 0;

  static Future<_Fixture> open() async {
    final f = _Fixture();
    f.root = await Directory.systemTemp.createTemp('received-sticker-action-');
    f.temporary = await Directory(p.join(f.root.path, 'temp')).create();
    f.documents = await Directory(p.join(f.root.path, 'documents-A')).create();
    f.otherDocuments = await Directory(
      p.join(f.root.path, 'documents-B'),
    ).create();
    f.snapshots = Directory(
      p.join(
        f.root.path,
        MediaFileManager.groupForwardSnapshotRootDirectoryName,
      ),
    );
    Future<Database> openDb(String name) =>
        databaseFactoryFfiNoIsolate.openDatabase(
          p.join(f.root.path, name),
          options: OpenDatabaseOptions(
            version: currentIdentityDatabaseVersion,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
          ),
        );
    f.db = await openDb('A.db');
    f.otherDb = await openDb('B.db');
    f.files = _Files(f.documents, f.snapshots);
    await f.groupRepository.saveGroup(
      GroupModel(
        id: 'group',
        name: 'Group',
        type: GroupType.chat,
        topicName: 'group-topic',
        createdAt: DateTime.utc(2026),
        createdBy: 'peer',
        myRole: GroupRole.member,
      ),
    );
    f.parent = ConversationMessage(
      id: 'direct-message',
      contactPeerId: 'peer',
      senderPeerId: 'peer',
      text: '',
      timestamp: '2026-11-11T00:00:00Z',
      createdAt: '2026-11-11T00:00:00Z',
      status: 'delivered',
      isIncoming: true,
    );
    f.library = AccountCustomStickerLibrary(
      enabled: true,
      createLibrary: (isCurrent) async {
        final expected = f.account;
        final delegate = SqliteCustomStickerLibrary(
          db: expected == 'A' ? f.db : f.otherDb,
          documentsDirectory: expected == 'A' ? f.documents : f.otherDocuments,
          temporaryDirectory: f.temporary,
          enabled: true,
          mayUseAccount: () async =>
              isCurrent() && f.active && f.account == expected,
        );
        f.delegates.add(delegate);
        return delegate;
      },
    );
    return f;
  }

  GroupMessage groupParent({
    GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.ordinary(),
  }) => GroupMessage(
    id: 'group-message',
    groupId: 'group',
    senderPeerId: 'peer',
    text: '',
    timestamp: DateTime.utc(2026, 11, 11),
    isIncoming: true,
    createdAt: DateTime.utc(2026, 11, 11),
    privateMediaPolicy: policy,
    mediaExpiresAt: policy.lifecycle == GroupMediaLifecycle.disappearing
        ? DateTime.utc(2099).millisecondsSinceEpoch
        : null,
  );

  Future<File> seed({
    bool group = false,
    String mime = 'image/webp',
    Uint8List? bytes,
    String? marker = 'custom',
    MediaOwnerLane? owner,
  }) async {
    final id = group ? 'group-att' : 'direct-att';
    final data = bytes ?? _animation();
    final extension = mime == 'image/webp'
        ? 'webp'
        : mime == 'image/png'
        ? 'png'
        : 'jpg';
    final relative = 'media/${group ? 'group' : 'peer'}/$id.$extension';
    final file = File(p.join(documents.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
    if (group) await groups.saveMessage(groupParent());
    await attachments.saveAttachment(
      MediaAttachment(
        id: id,
        messageId: group ? 'group-message' : 'direct-message',
        mime: mime,
        size: data.length,
        mediaType: 'image',
        localPath: relative,
        downloadStatus: 'done',
        createdAt: '2026-11-11T00:00:00Z',
        width: 16,
        height: 16,
        durationMs: null,
        stickerId: marker,
        // This is intentionally NOT the plaintext digest. It authenticates a
        // different ciphertext domain and must not become the sticker hash.
        contentHash: List.filled(64, 'b').join(),
        encryptionKeyBase64: 'a2V5',
        encryptionNonce: 'bm9uY2U=',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      ),
      owner: owner ?? (group ? MediaOwnerLane.group : MediaOwnerLane.direct),
    );
    return file;
  }

  ReceivedStickerSaver saver({
    Future<void> Function(String, File, int)? copy,
  }) => ReceivedStickerSaver(
    mediaFileManager: files,
    pathAuthority: IoAppOwnedMediaPathAuthority(
      documentsDirectory: () async => documents,
    ),
    copySnapshot: copy,
  );

  Future<CustomSticker?> save({
    bool group = false,
    ReceivedStickerEditor? editor,
    ReceivedStickerSaver? service,
    AccountCustomStickerLibrary? accountLibrary,
    GroupMessageRepository? groupMessages,
  }) {
    final supplied = service ?? saver();
    if (group) {
      return GroupReceivedMediaActionsController(
        groupRepository: groupRepository,
        messageRepository: groupMessages ?? groups,
        mediaAttachmentRepository: attachments,
        egressService: ReceivedMediaEgressService(),
        mediaFileManager: files,
        receivedStickerSaver: supplied,
      ).saveReceivedSticker(
        groupId: 'group',
        messageId: 'group-message',
        attachmentId: 'group-att',
        library: accountLibrary ?? library,
        editPhoto: editor ?? edit,
      );
    }
    return ReceivedMediaActionController(
      loadParentMessage: (_) async {
        parentReads++;
        return parent;
      },
      mediaAttachmentRepo: attachments,
      egressService: ReceivedMediaEgressService(),
      resolveStoredPath: (path) => p.join(documents.path, path),
      receivedStickerSaver: supplied,
    ).saveReceivedSticker(
      identity: const DirectReceivedMediaActionIdentity(
        messageId: 'direct-message',
        attachmentId: 'direct-att',
      ),
      library: accountLibrary ?? library,
      editPhoto: editor ?? edit,
    );
  }

  Future<bool> canSave({
    bool group = false,
    AccountCustomStickerLibrary? accountLibrary,
    GroupMessageRepository? groupMessages,
  }) {
    if (group) {
      return GroupReceivedMediaActionsController(
        groupRepository: groupRepository,
        messageRepository: groupMessages ?? groups,
        mediaAttachmentRepository: attachments,
        egressService: ReceivedMediaEgressService(),
        mediaFileManager: files,
        receivedStickerSaver: saver(),
      ).canSaveReceivedSticker(
        groupId: 'group',
        messageId: 'group-message',
        attachmentId: 'group-att',
        library: accountLibrary ?? library,
      );
    }
    return ReceivedMediaActionController(
      loadParentMessage: (_) async {
        parentReads++;
        return parent;
      },
      mediaAttachmentRepo: attachments,
      egressService: ReceivedMediaEgressService(),
      resolveStoredPath: (path) => p.join(documents.path, path),
      receivedStickerSaver: saver(),
    ).canSaveReceivedSticker(
      identity: const DirectReceivedMediaActionIdentity(
        messageId: 'direct-message',
        attachmentId: 'direct-att',
      ),
      library: accountLibrary ?? library,
    );
  }

  Future<StickerEditorResult> edit({
    required String sourceImagePath,
    required Directory outputDirectory,
  }) async {
    editorCalls++;
    expect(File(sourceImagePath).existsSync(), isTrue);
    final bytes = img.encodePng(_pixels(100));
    final file = await File(
      p.join(outputDirectory.path, 'edited.png'),
    ).writeAsBytes(bytes);
    return StickerEditorResult.ready(
      NormalizedStickerAsset(
        filePath: file.path,
        sha256Hex: sha256.convert(bytes).toString(),
        mime: 'image/png',
        byteLength: bytes.length,
        width: 16,
        height: 16,
        frameCount: 1,
        durationMs: 0,
      ),
    );
  }

  Future<Object?> watch(Future<CustomSticker?> operation) {
    final result = operation.then<Object?>((v) => v, onError: (Object e) => e);
    pending.add(result);
    return result;
  }

  _Gate gate() {
    final gate = _Gate();
    gates.add(gate);
    return gate;
  }

  Future<void> emptyLibrary() async {
    expect(await db.query('custom_stickers'), isEmpty);
    expect(await otherDb.query('custom_stickers'), isEmpty);
    expect(Directory(p.join(documents.path, 'stickers')).existsSync(), isFalse);
    expect(
      Directory(p.join(otherDocuments.path, 'stickers')).existsSync(),
      isFalse,
    );
  }

  void noTemps() {
    expect(snapshots.existsSync() ? snapshots.listSync() : [], isEmpty);
    expect(temporary.listSync(), isEmpty);
  }

  Future<void> close() async {
    for (final gate in gates) {
      gate.open();
    }
    await Future.wait(pending).timeout(const Duration(seconds: 10));
    await library.retire();
    for (final delegate in delegates) {
      await delegate.retire();
    }
    await db.close();
    await otherDb.close();
    await root.delete(recursive: true);
  }
}

void main() {
  sqfliteFfiInit();
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.open();
  });
  tearDown(() async {
    await f.close();
  });

  for (final group in [false, true]) {
    test(
      '${group ? 'unmarked strict-compatible group' : 'direct'} canonical animation saves every original byte without editor or creator',
      () async {
        final source = await f.seed(
          group: group,
          marker: group ? null : 'unknown-creator',
        );
        final bytes = await source.readAsBytes();
        final saved = (await f.save(group: group))!;
        expect(saved.asset.frameCount, 2);
        expect(saved.asset.durationMs, 167);
        expect(saved.asset.sha256Hex, sha256.convert(bytes).toString());
        expect(await File(saved.asset.filePath).readAsBytes(), bytes);
        expect(await source.readAsBytes(), bytes);
        expect(saved.asset.filePath, isNot(source.path));
        expect(f.editorCalls, 0);
        f.noTemps();
      },
    );
  }

  test(
    'ordinary unmarked photo requires editor and owns only its independent output',
    () async {
      final source = await f.seed(
        group: true,
        mime: 'image/jpeg',
        bytes: img.encodeJpg(_pixels(90)),
        marker: null,
      );
      final before = await source.readAsBytes();
      String? snapshot;
      final saved = await f.save(
        group: true,
        editor: ({required sourceImagePath, required outputDirectory}) async {
          snapshot = sourceImagePath;
          expect(sourceImagePath, isNot(source.path));
          expect(await File(sourceImagePath).readAsBytes(), before);
          return f.edit(
            sourceImagePath: sourceImagePath,
            outputDirectory: outputDirectory,
          );
        },
      );
      expect(saved, isNotNull);
      expect(f.editorCalls, 1);
      expect(saved!.asset.mime, 'image/webp');
      expect(File(snapshot!).existsSync(), isFalse);
      expect(await source.readAsBytes(), before);
      f.noTemps();
    },
  );

  for (final policy in [
    'view-once',
    'protected-open',
    'unexpired disappearing',
    'unknown protection',
  ]) {
    test('$policy receive-save refuses before any file write', () async {
      for (final group in [false, true]) {
        final source = await f.seed(group: group);
        final before = await source.readAsBytes();
        if (group) {
          final value = switch (policy) {
            'view-once' => const GroupPrivateMediaPolicy.viewOnce(),
            'protected-open' => const GroupPrivateMediaPolicy.protected(),
            'unexpired disappearing' => GroupPrivateMediaPolicy.disappearing(
              3600,
            ),
            _ => const GroupPrivateMediaPolicy.unsupported(),
          };
          await f.groups.saveMessage(f.groupParent(policy: value));
        } else {
          final value = switch (policy) {
            'view-once' => const PrivateMediaPolicy.viewOnce(),
            'protected-open' => const PrivateMediaPolicy.protected(),
            'unexpired disappearing' => PrivateMediaPolicy.disappearing(3600),
            _ => const PrivateMediaPolicy.unsupported(),
          };
          f.parent = f.parent.copyWith(
            privateMediaPolicy: value,
            privateMediaState: value.isUnsupported
                ? PrivateMediaLifecycleState.unsupported
                : PrivateMediaLifecycleState.available,
            privateMediaExpiresAtMs: policy == 'unexpired disappearing'
                ? DateTime.utc(2099).millisecondsSinceEpoch
                : null,
          );
        }
        expect(await f.canSave(group: group), isFalse);
        await expectLater(
          f.save(group: group),
          throwsA(_error(CustomStickerErrorCode.notEligible)),
        );
        expect(await source.readAsBytes(), before);
      }
      expect(f.files.leases, 0);
      expect(f.editorCalls, 0);
      await f.emptyLibrary();
      f.noTemps();
    });
  }

  test(
    'cancel in the same active account returns null and cleans editor and snapshot files',
    () async {
      final source = await f.seed(
        mime: 'image/png',
        bytes: img.encodePng(_pixels(40)),
      );
      final before = await source.readAsBytes();
      expect(
        await f.save(
          editor: ({required sourceImagePath, required outputDirectory}) async {
            await File(
              p.join(outputDirectory.path, 'abandoned'),
            ).writeAsString('temporary');
            return const StickerEditorResult.cancelled();
          },
        ),
        isNull,
      );
      expect(await source.readAsBytes(), before);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'foreign editor result is refused without deleting the foreign file',
    () async {
      await f.seed(mime: 'image/png', bytes: img.encodePng(_pixels(30)));
      final outside = await Directory(p.join(f.root.path, 'foreign')).create();
      await expectLater(
        f.save(
          editor: ({required sourceImagePath, required outputDirectory}) => f
              .edit(sourceImagePath: sourceImagePath, outputDirectory: outside),
        ),
        throwsA(_error(CustomStickerErrorCode.invalidAsset)),
      );
      expect(File(p.join(outside.path, 'edited.png')).existsSync(), isTrue);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'source outside owned media roots refuses before snapshot allocation',
    () async {
      final source = await f.seed();
      final outside = await File(
        p.join(f.root.path, 'outside.webp'),
      ).writeAsBytes(await source.readAsBytes());
      final row = (await f.attachments.getAttachmentsForMessage(
        'direct-message',
        owner: MediaOwnerLane.direct,
      )).single;
      await f.attachments.saveAttachment(
        row.copyWith(localPath: outside.path),
        owner: MediaOwnerLane.direct,
      );
      await expectLater(
        f.save(),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      expect(outside.existsSync(), isTrue);
      expect(f.files.leases, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'wrong owner and stale parent cannot authorize received bytes',
    () async {
      await f.seed(owner: MediaOwnerLane.group);
      await expectLater(
        f.save(),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      await f.seed(group: true);
      f.groups.seedLocalDeletion(messageId: 'group-message', groupId: 'group');
      await expectLater(
        f.save(group: true),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      expect(f.files.leases, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'private transition during real snapshot copy refuses and cleans only the snapshot',
    () async {
      final source = await f.seed();
      final before = await source.readAsBytes();
      final service = f.saver(
        copy: (path, target, size) async {
          await File(path).copy(target.path);
          f.parent = f.parent.copyWith(
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.available,
          );
        },
      );
      await expectLater(
        f.save(service: service),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      expect(await source.readAsBytes(), before);
      expect(f.editorCalls, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'visibility probe writes nothing and never authorizes a later private save',
    () async {
      for (final group in [false, true]) {
        await f.seed(group: group, marker: null);
        expect(await f.canSave(group: group), isTrue);
        expect(f.files.leases, 0);
        expect(f.editorCalls, 0);
        await f.emptyLibrary();
        f.noTemps();
        if (group) {
          await f.groups.saveMessage(
            f.groupParent(policy: const GroupPrivateMediaPolicy.protected()),
          );
        } else {
          f.parent = f.parent.copyWith(
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.available,
          );
        }
        await expectLater(
          f.save(group: group),
          throwsA(_error(CustomStickerErrorCode.notEligible)),
        );
      }
      expect(f.files.leases, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'group probe and save preserve the existing local save policy for QA groups',
    () async {
      await f.seed(group: true);
      final group = (await f.groupRepository.getGroup('group'))!;
      await f.groupRepository.saveGroup(group.copyWith(type: GroupType.qa));
      expect(await f.canSave(group: true), isFalse);
      await expectLater(
        f.save(group: true),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      expect(f.files.leases, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  for (final missing in [true, false]) {
    for (final probe in [true, false]) {
      test(
        '${missing ? 'missing' : 'unknown'} deletion authority refuses group ${probe ? 'probe' : 'save'} before any file write',
        () async {
          final source = await f.seed(group: true);
          final before = await source.readAsBytes();
          final rows = missing
              ? _MissingDeletionAuthority(f.groups)
              : _UnknownDeletionAuthority(f.groups);
          if (probe) {
            expect(await f.canSave(group: true, groupMessages: rows), isFalse);
          } else {
            await expectLater(
              f.save(group: true, groupMessages: rows),
              throwsA(_error(CustomStickerErrorCode.notEligible)),
            );
          }
          expect(await source.readAsBytes(), before);
          expect(f.files.leases, 0);
          expect(f.editorCalls, 0);
          await f.emptyLibrary();
          f.noTemps();
        },
      );
    }
  }

  for (final sameAccount in [false, true]) {
    for (final cancel in [false, true]) {
      test(
        '${sameAccount ? 'same-account' : 'cross-account'} replacement rejects late editor ${cancel ? 'cancel' : 'ready'} without blocking activation',
        () async {
          final source = await f.seed(
            mime: 'image/png',
            bytes: img.encodePng(_pixels(70)),
          );
          final gate = f.gate();
          final result = f.watch(
            f.save(
              editor:
                  ({required sourceImagePath, required outputDirectory}) async {
                    final edited = await f.edit(
                      sourceImagePath: sourceImagePath,
                      outputDirectory: outputDirectory,
                    );
                    await gate.hold();
                    return cancel
                        ? const StickerEditorResult.cancelled()
                        : edited;
                  },
            ),
          );
          await gate.entered.future.timeout(const Duration(seconds: 10));
          await f.library.retire().timeout(const Duration(seconds: 2));
          if (!sameAccount) f.account = 'B';
          await f.library.activate().timeout(const Duration(seconds: 2));
          gate.open();
          expect(await result, _error(CustomStickerErrorCode.unavailable));
          expect(source.existsSync(), isTrue);
          await f.emptyLibrary();
          f.noTemps();
        },
      );
    }
  }

  test(
    'retire during a copied snapshot revokes the old action before inspection or admission',
    () async {
      final source = await f.seed();
      final before = await source.readAsBytes();
      final gate = f.gate();
      final result = f.watch(
        f.save(
          service: f.saver(
            copy: (path, target, size) async {
              await File(path).copy(target.path);
              await gate.hold();
            },
          ),
        ),
      );
      await gate.entered.future.timeout(const Duration(seconds: 10));
      await f.library.retire().timeout(const Duration(seconds: 2));
      await f.library.activate().timeout(const Duration(seconds: 2));
      gate.open();
      expect(await result, _error(CustomStickerErrorCode.unavailable));
      expect(await source.readAsBytes(), before);
      expect(f.editorCalls, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'export pause during editor denies admission through the captured passive authority',
    () async {
      await f.seed(mime: 'image/png', bytes: img.encodePng(_pixels(60)));
      await expectLater(
        f.save(
          editor: ({required sourceImagePath, required outputDirectory}) async {
            final result = await f.edit(
              sourceImagePath: sourceImagePath,
              outputDirectory: outputDirectory,
            );
            f.active = false;
            return result;
          },
        ),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'disabled account action performs no row read, editor or file work',
    () async {
      var factories = 0;
      final disabled = AccountCustomStickerLibrary(
        createLibrary: (_) async {
          factories++;
          return null;
        },
      );
      await expectLater(
        f.save(accountLibrary: disabled),
        throwsA(_error(CustomStickerErrorCode.disabled)),
      );
      expect(factories, 0);
      expect(f.parentReads, 0);
      expect(f.files.leases, 0);
      expect(f.editorCalls, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'unsupported animated input is never silently reduced through the photo editor',
    () async {
      final source = await f.seed(
        mime: 'image/gif',
        bytes: Uint8List.fromList([71, 73, 70, 56, 57, 97]),
      );
      await expectLater(
        f.save(),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      expect(source.existsSync(), isTrue);
      expect(f.editorCalls, 0);
      expect(f.files.leases, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'canonical static WebP keeps exact bytes while a larger still requires the editor',
    () async {
      final canonical = img.encodeWebP(_pixels(80), lossless: true);
      final source = await f.seed(bytes: canonical);
      final saved = (await f.save())!;
      expect(await File(saved.asset.filePath).readAsBytes(), canonical);
      expect(await source.readAsBytes(), canonical);
      expect(f.editorCalls, 0);
      final large = img.encodeWebP(
        img.Image(width: 513, height: 1, numChannels: 4),
        lossless: true,
      );
      await f.seed(group: true, bytes: large, marker: null);
      expect(await f.save(group: true), isNotNull);
      expect(f.editorCalls, 1);
      f.noTemps();
    },
  );

  test(
    'over-duration canonical animation is rejected without truncation or an editor fallback',
    () async {
      final image = _pixels(10)..frameDuration = 1500;
      image.addFrame(_pixels(200)..frameDuration = 1500);
      final source = await f.seed(bytes: img.encodeWebP(image, lossless: true));
      final before = await source.readAsBytes();
      await expectLater(
        f.save(),
        throwsA(_error(CustomStickerErrorCode.invalidAsset)),
      );
      expect(await source.readAsBytes(), before);
      expect(f.editorCalls, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'oversized source claim is refused before any snapshot allocation',
    () async {
      await f.seed();
      final row = (await f.attachments.getAttachmentsForMessage(
        'direct-message',
        owner: MediaOwnerLane.direct,
      )).single;
      await f.attachments.saveAttachment(
        row.copyWith(size: 25 * 1024 * 1024 + 1),
        owner: MediaOwnerLane.direct,
      );
      expect(await f.canSave(), isFalse);
      await expectLater(
        f.save(),
        throwsA(_error(CustomStickerErrorCode.notEligible)),
      );
      expect(f.files.leases, 0);
      await f.emptyLibrary();
      f.noTemps();
    },
  );

  test(
    'admission failure cleans owned editor output and leaves source bytes untouched',
    () async {
      final source = await f.seed(
        mime: 'image/png',
        bytes: img.encodePng(_pixels(30)),
      );
      final before = await source.readAsBytes();
      await expectLater(
        f.save(
          editor: ({required sourceImagePath, required outputDirectory}) async {
            final result =
                await f.edit(
                      sourceImagePath: sourceImagePath,
                      outputDirectory: outputDirectory,
                    )
                    as StickerEditorReady;
            final asset = result.asset;
            return StickerEditorResult.ready(
              NormalizedStickerAsset(
                filePath: asset.filePath,
                sha256Hex: List.filled(64, '0').join(),
                mime: asset.mime,
                byteLength: asset.byteLength,
                width: asset.width,
                height: asset.height,
                frameCount: 1,
                durationMs: 0,
              ),
            );
          },
        ),
        throwsA(_error(CustomStickerErrorCode.invalidAsset)),
      );
      expect(await source.readAsBytes(), before);
      await f.emptyLibrary();
      f.noTemps();
    },
  );
}
