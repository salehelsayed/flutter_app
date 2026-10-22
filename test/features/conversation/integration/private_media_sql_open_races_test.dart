import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

class _Documents extends PathProviderPlatform {
  _Documents(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final race in ['none', 'consumed', 'deleted', 'owner-changed']) {
    test(
      'MEDIA-034 real SQL $race while native protection admission is pending never publishes stale private bytes',
      () async {
        final root = Directory.systemTemp.createTempSync('private-sql-open-');
        final previousPaths = PathProviderPlatform.instance;
        final previousCache = MediaFileManager.cachedDocumentsDir;
        PathProviderPlatform.instance = _Documents(root.path);
        MediaFileManager.cacheDocumentsDir(root.path);
        final fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${root.path}/identity.db',
          databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        );
        final events = StreamController<Object?>.broadcast();
        final entered = Completer<void>();
        final release = Completer<void>();
        final calls = <String>[];
        final protection = PrivateMediaProtectionCoordinator(
          nativeEvents: events.stream,
          invokeMethod: (method, arguments) async {
            calls.add(method);
            if (method == 'enter') {
              if (!entered.isCompleted) entered.complete();
              await release.future;
            }
            return {'ok': true, 'protectionActive': method == 'enter'};
          },
        );
        final controller = DirectPrivateMediaViewerController(
          loadCurrentRows: (identity) async {
            final rows = await fixture.repo.getAttachmentsForMessage(
              identity.messageId,
              owner: MediaOwnerLane.direct,
            );
            return DirectPrivateMediaCurrentRows(
              parent: await fixture.messageRepo.getMessage(identity.messageId),
              attachment: rows
                  .where((r) => r.id == identity.attachmentId)
                  .firstOrNull,
            );
          },
          lifecycleEngine: PrivateMediaLifecycleEngine(
            adapter: DirectPrivateMediaLifecycle(
              messageRepository: fixture.messageRepo,
              mediaAttachmentRepository: fixture.repo,
              mediaFileManager: MediaFileManager(),
            ),
            lifecycleLock: fixture.repo.lifecycleLock,
            nowMs: () => 2000,
          ),
          protectionCoordinator: protection,
        );
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await controller.dispose();
          await events.close();
          await fixture.dispose();
          PathProviderPlatform.instance = previousPaths;
          MediaFileManager.debugResetDocumentsDirCache();
          if (previousCache != null)
            MediaFileManager.cacheDocumentsDir(previousCache);
          root.deleteSync(recursive: true);
        });
        const messageId = 'private-parent';
        const attachmentId = 'private-image';
        const relativePath = 'media/contact-1/private-image.png';
        final file = File('${root.path}/$relativePath');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATklEQVR4nO3PUQkAIBTAwNfAfmY3jCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjx2AV3NKJdv7voVAAAAAElFTkSuQmCC',
          ),
        );
        await fixture.seedDirectParent(messageId);
        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: [messageId],
        );
        await fixture.repo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/png',
            size: file.lengthSync(),
            mediaType: 'image',
            localPath: relativePath,
            downloadStatus: 'done',
            ownerLane: MediaOwnerLane.direct,
            createdAt: '2026-07-01T00:00:00Z',
          ),
          owner: MediaOwnerLane.direct,
        );
        const identity = DirectPrivateMediaViewerIdentity(
          messageId: messageId,
          attachmentId: attachmentId,
        );
        var published = false;
        final pending = controller
            .prepareResult(
              identity,
              const DirectPrivateMediaAlwaysValidContinuityGuard(),
            )
            .then((result) {
              published = result.isGranted;
              return result;
            });
        await entered.future.timeout(const Duration(seconds: 5));
        expect(published, isFalse);
        expect(
          (await fixture.messageRepo.getMessage(
            messageId,
          ))!.privateMediaState.name,
          'opening',
        );
        if (race == 'consumed' || race == 'deleted') {
          await fixture.db.update(
            'messages',
            {
              'private_media_state': 'consumed',
              'private_media_terminal_at_ms': 2100,
              if (race == 'deleted') 'deleted_at': '2026-07-02T00:00:00Z',
            },
            where: 'id = ?',
            whereArgs: [messageId],
          );
        } else if (race == 'owner-changed') {
          await fixture.seedGroupParent(messageId);
          await fixture.db.update(
            'media_attachments',
            {'owner_lane': 'group'},
            where: 'id = ? AND owner_lane = ?',
            whereArgs: [attachmentId, 'direct'],
          );
        }
        release.complete();
        final result = await pending.timeout(const Duration(seconds: 5));
        if (race == 'none') {
          expect(result.isGranted, isTrue);
          expect(result.grant!.localPath, file.path);
          expect(await controller.markFirstFrame(result.grant!), isTrue);
          final closed = await controller.settle(
            result.grant!,
            DirectPrivateMediaExitReason.close,
          );
          expect(closed.firstFrameRecorded, isTrue);
          await controller.releaseProtectionOwner(result.grant!);
        } else {
          expect(result.grant, isNull);
          expect(
            result.failureReason,
            DirectPrivateMediaPrepareFailureReason.revalidationFailed,
          );
          expect(published, isFalse);
        }
        expect(calls, ['enter', 'exit']);
        expect(
          (await controller.prepareResult(
            identity,
            const DirectPrivateMediaAlwaysValidContinuityGuard(),
          )).grant,
          isNull,
        );
        expect(calls, [
          'enter',
          'exit',
        ], reason: 'a stale tap cannot re-enter native protection');
        if (race == 'owner-changed') {
          expect(
            file.existsSync(),
            isTrue,
            reason: 'cleanup cannot delete a sibling owner file',
          );
          expect(
            await fixture.repo.getAttachmentsForMessage(
              messageId,
              owner: MediaOwnerLane.group,
            ),
            hasLength(1),
          );
        } else {
          expect(
            (await fixture.messageRepo.getMessage(
              messageId,
            ))!.privateMediaState.name,
            'consumed',
          );
        }
      },
    );
  }
}
