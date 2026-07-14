import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_actions.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_controller.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/strict_direct_media_library_repository.dart';

const String kContactPeerId = '12D3KooWBatchContactPeer';

/// Raw recording list-capable egress service: captures every native-boundary
/// request verbatim and answers with a scripted per-item result. Throws when
/// a dispatch exceeds the shared egress ceiling — an over-cap batch must be
/// refused BEFORE this boundary.
class _RecordingEgressService extends ReceivedMediaEgressService {
  final calls =
      <
        ({
          String requestId,
          MediaEgressDestination destination,
          List<ReceivedMediaEgressCandidate> selection,
        })
      >[];

  /// Scripted per-item outcomes by attachment id (photos/files only).
  final Map<String, MediaEgressItemOutcome> scriptedOutcomes = {};

  /// When set, a share dispatch answers with this aggregate outcome.
  MediaEgressOutcome shareOutcome = MediaEgressOutcome.presented;

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    if (selection.length > kMaxMediaEgressItems) {
      throw StateError(
        'over-cap native dispatch: ${selection.length} candidates',
      );
    }
    calls.add((
      requestId: requestId,
      destination: destination,
      selection: selection,
    ));
    if (destination == MediaEgressDestination.share) {
      return MediaEgressResult(
        requestId: requestId,
        outcome: shareOutcome,
        items: const [],
      );
    }
    return MediaEgressResult(
      requestId: requestId,
      outcome: MediaEgressOutcome.partial,
      items: [
        for (final candidate in selection)
          MediaEgressItemResult(
            attachmentId: candidate.attachmentId,
            outcome:
                scriptedOutcomes[candidate.attachmentId] ??
                MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

void main() {
  late Directory tempDir;
  late _RecordingEgressService service;
  late FakeMediaAttachmentRepository repo;
  late Map<String, ConversationMessage> parents;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('direct_media_batch_');
    service = _RecordingEgressService();
    repo = FakeMediaAttachmentRepository();
    parents = {};
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String writeMediaFile(String name, [List<int> bytes = const [7, 8, 9]]) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  ConversationMessage makeParent({
    required String id,
    bool isIncoming = true,
    String? deletedAt,
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
    PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: kContactPeerId,
      senderPeerId: isIncoming ? kContactPeerId : 'peer-me',
      text: 'parent $id',
      timestamp: '2026-07-09T10:00:00.000Z',
      status: 'delivered',
      isIncoming: isIncoming,
      createdAt: '2026-07-09T10:00:01.000Z',
      deletedAt: deletedAt,
      privateMediaPolicy: policy,
      privateMediaState: state,
    );
  }

  MediaAttachment makeRow({
    required String id,
    required String messageId,
    String? localPath,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String downloadStatus = 'done',
    MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 3,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-09T10:00:02.000Z',
      ownerLane: ownerLane,
    );
  }

  DirectMediaLibraryBatchActionsCoordinator buildCoordinator({
    DirectMediaLaneQualifier? qualifier,
  }) {
    return DirectMediaLibraryBatchActionsCoordinator(
      loadParentMessage: (id) async => parents[id],
      mediaAttachmentRepo: repo,
      egressService: service,
      qualifier: qualifier ?? defaultDirectMediaLaneQualifier,
      resolveStoredPath: (storedPath) => storedPath,
    );
  }

  DirectReceivedMediaActionIdentity identity(String messageId, String id) =>
      DirectReceivedMediaActionIdentity(messageId: messageId, attachmentId: id);

  test(
    'batch save reloads current direct rows and returns per-item outcomes',
    () async {
      final stalePathA1 = writeMediaFile('a1-stale.jpg');
      final currentPathA1 = writeMediaFile('a1-current.jpg');
      final pathA2 = writeMediaFile('a2.jpg');
      final pathProtected = writeMediaFile('protected.jpg');
      final pathIntegrity = writeMediaFile('integrity.jpg');

      parents['msg-a'] = makeParent(id: 'msg-a');
      parents['msg-p'] = makeParent(id: 'msg-p');
      parents['msg-i'] = makeParent(id: 'msg-i');
      // msg-c is deliberately ABSENT: its attachment must fail preflight.

      repo.seed([
        makeRow(id: 'att-a1', messageId: 'msg-a', localPath: stalePathA1),
        makeRow(id: 'att-a2', messageId: 'msg-a', localPath: pathA2),
        makeRow(id: 'att-c1', messageId: 'msg-c', localPath: pathA2),
        makeRow(id: 'att-p', messageId: 'msg-p', localPath: pathProtected),
        makeRow(
          id: 'att-i',
          messageId: 'msg-i',
          localPath: pathIntegrity,
          downloadStatus: 'integrity_failed',
        ),
      ]);

      // The library/viewer snapshot of att-a1 is STALE: the current row moved
      // to a new path after the page rendered. Only the reloaded current row
      // may reach the native boundary.
      await repo.updateLocalPath('att-a1', currentPathA1);

      final qualified = <String>[];
      final coordinator = buildCoordinator(
        qualifier: (parent, current) async {
          qualified.add(current.id);
          return current.id == 'att-p'
              ? DirectMediaLaneQualification.protected
              : DirectMediaLaneQualification.eligible;
        },
      );

      service.scriptedOutcomes['att-a2'] =
          MediaEgressItemOutcome.permissionDenied;

      final result = await coordinator.performBatchEgress(
        identities: [
          identity('msg-a', 'att-a1'),
          identity('msg-a', 'att-a2'),
          identity('msg-c', 'att-c1'),
          identity('msg-p', 'att-p'),
          identity('msg-i', 'att-i'),
        ],
        destination: MediaEgressDestination.files,
      );

      // ONE exact ordered native request to the CHOSEN destination with only
      // the current qualified rows — the stale att-a1 path is ignored, and
      // preflight-failed rows never reach the boundary.
      expect(service.calls, hasLength(1));
      expect(service.calls.single.destination, MediaEgressDestination.files);
      expect(
        isValidMediaEgressRequestId(service.calls.single.requestId),
        isTrue,
      );
      final selection = service.calls.single.selection;
      expect(selection.map((c) => c.attachmentId).toList(), [
        'att-a1',
        'att-a2',
      ]);
      expect(selection.first.storedPath, currentPathA1);
      expect(selection.last.storedPath, pathA2);

      // The shared plan-231 qualifier ran against each structurally-qualified
      // reloaded row (missing parent and integrity-failed never reached it).
      expect(qualified, ['att-a1', 'att-a2', 'att-p']);

      // Merged preflight + native per-item outcomes, in dispatch order.
      expect(result.items.map((i) => i.attachmentId).toList(), [
        'att-a1',
        'att-a2',
        'att-c1',
        'att-p',
        'att-i',
      ]);
      expect(result.succeededIds, {'att-a1'});
      expect(result.failedIds, {'att-a2', 'att-c1', 'att-p', 'att-i'});
      final byId = {for (final item in result.items) item.attachmentId: item};
      expect(byId['att-a1']!.itemOutcome, MediaEgressItemOutcome.saved);
      expect(
        byId['att-a2']!.itemOutcome,
        MediaEgressItemOutcome.permissionDenied,
      );
      expect(byId['att-c1']!.denial, DirectMediaEgressDenial.parentNotFound);
      expect(byId['att-p']!.denial, DirectMediaEgressDenial.protected);
      expect(byId['att-i']!.denial, DirectMediaEgressDenial.integrityFailed);

      // Source state is never mutated by a batch egress — including for the
      // failed items: rows keep their status/path/bookmark, bytes intact.
      final rowsA = await repo.getAttachmentsForMessage(
        'msg-a',
        owner: MediaOwnerLane.direct,
      );
      expect(rowsA.map((r) => r.downloadStatus).toSet(), {'done'});
      expect(
        rowsA.firstWhere((r) => r.id == 'att-a1').localPath,
        currentPathA1,
      );
      expect(rowsA.map((r) => r.isBookmarked).toSet(), {false});
      expect(File(currentPathA1).readAsBytesSync(), [7, 8, 9]);
      expect(File(pathA2).readAsBytesSync(), [7, 8, 9]);
      final rowsI = await repo.getAttachmentsForMessage(
        'msg-i',
        owner: MediaOwnerLane.direct,
      );
      expect(rowsI.single.downloadStatus, 'integrity_failed');
    },
  );

  test(
    'batch external share is one qualified native request with failed-only retry state',
    () async {
      final pathS1 = writeMediaFile('s1.jpg');
      final pathS2 = writeMediaFile('s2.jpg');

      parents['msg-s'] = makeParent(id: 'msg-s');

      repo.seed([
        makeRow(id: 'att-s1', messageId: 'msg-s', localPath: pathS1),
        makeRow(id: 'att-s2', messageId: 'msg-s', localPath: pathS2),
        // Preflight failure: the bytes are gone underneath a done row.
        makeRow(
          id: 'att-s3',
          messageId: 'msg-s',
          localPath: '${tempDir.path}/gone.jpg',
        ),
      ]);

      final coordinator = buildCoordinator();

      final presented = await coordinator.performBatchEgress(
        identities: [
          identity('msg-s', 'att-s1'),
          identity('msg-s', 'att-s2'),
          identity('msg-s', 'att-s3'),
        ],
        destination: MediaEgressDestination.share,
      );

      // ONE list-capable OS request for the qualified candidates — never a
      // per-item chooser loop, never an internal picker (the coordinator has
      // no picker/delivery/P2P seam to call).
      expect(service.calls, hasLength(1));
      expect(service.calls.single.destination, MediaEgressDestination.share);
      expect(
        service.calls.single.selection.map((c) => c.attachmentId).toList(),
        ['att-s1', 'att-s2'],
      );

      // Presented: the dispatched candidates clear; the preflight-failed
      // item stays selected with its typed denial.
      expect(presented.succeededIds, {'att-s1', 'att-s2'});
      expect(presented.failedIds, {'att-s3'});
      expect(
        presented.items.firstWhere((i) => i.attachmentId == 'att-s3').denial,
        DirectMediaEgressDenial.fileMissing,
      );

      // A cancelled native share keeps EVERY dispatched item selected for
      // truthful retry — cancellation is not success.
      service.shareOutcome = MediaEgressOutcome.cancelled;
      final cancelled = await coordinator.performBatchEgress(
        identities: [identity('msg-s', 'att-s1'), identity('msg-s', 'att-s2')],
        destination: MediaEgressDestination.share,
      );
      expect(service.calls, hasLength(2));
      expect(cancelled.wasCancelled, isTrue);
      expect(cancelled.succeededIds, isEmpty);
      expect(cancelled.failedIds, {'att-s1', 'att-s2'});
    },
  );

  test(
    'mixed current private states stay item-scoped despite a permissive qualifier',
    () async {
      final ordinaryPath = writeMediaFile('ordinary.jpg');
      final protectedPath = writeMediaFile('private.jpg');
      final unsupportedPath = writeMediaFile('unsupported.jpg');
      final terminalPath = writeMediaFile('terminal.jpg');
      parents['msg-ordinary'] = makeParent(id: 'msg-ordinary');
      parents['msg-private'] = makeParent(
        id: 'msg-private',
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      );
      parents['msg-unsupported'] = makeParent(
        id: 'msg-unsupported',
        policy: const PrivateMediaPolicy.unsupported(sourceVersion: 77),
        state: PrivateMediaLifecycleState.unsupported,
      );
      parents['msg-terminal'] = makeParent(
        id: 'msg-terminal',
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.expired,
      );
      repo.seed([
        makeRow(
          id: 'att-ordinary',
          messageId: 'msg-ordinary',
          localPath: ordinaryPath,
        ),
        makeRow(
          id: 'att-private',
          messageId: 'msg-private',
          localPath: protectedPath,
        ),
        makeRow(
          id: 'att-unsupported',
          messageId: 'msg-unsupported',
          localPath: unsupportedPath,
        ),
        makeRow(
          id: 'att-terminal',
          messageId: 'msg-terminal',
          localPath: terminalPath,
        ),
      ]);
      final coordinator = buildCoordinator(
        qualifier: (_, _) async => DirectMediaLaneQualification.eligible,
      );
      final identities = [
        identity('msg-ordinary', 'att-ordinary'),
        identity('msg-private', 'att-private'),
        identity('msg-unsupported', 'att-unsupported'),
        identity('msg-terminal', 'att-terminal'),
      ];

      for (final destination in const [
        MediaEgressDestination.files,
        MediaEgressDestination.share,
      ]) {
        final result = await coordinator.performBatchEgress(
          identities: identities,
          destination: destination,
        );
        expect(service.calls.last.selection.map((item) => item.attachmentId), [
          'att-ordinary',
        ]);
        final byId = {for (final item in result.items) item.attachmentId: item};
        expect(byId['att-private']!.denial, DirectMediaEgressDenial.protected);
        expect(
          byId['att-unsupported']!.denial,
          DirectMediaEgressDenial.protected,
        );
        expect(byId['att-terminal']!.denial, DirectMediaEgressDenial.expired);
        expect(result.succeededIds, {'att-ordinary'});
      }
      expect(service.calls, hasLength(2));
    },
  );

  test(
    'batch deduplication binds the complete message attachment identity',
    () async {
      final path = writeMediaFile('identity.jpg');
      parents['msg-valid'] = makeParent(id: 'msg-valid');
      parents['msg-other'] = makeParent(id: 'msg-other');
      repo.seed([
        makeRow(id: 'same-attachment', messageId: 'msg-valid', localPath: path),
      ]);

      final result = await buildCoordinator().performBatchEgress(
        identities: [
          identity('msg-valid', 'same-attachment'),
          identity('msg-other', 'same-attachment'),
        ],
        destination: MediaEgressDestination.files,
      );

      expect(service.calls, hasLength(1));
      expect(service.calls.single.selection, hasLength(1));
      expect(result.items, hasLength(2));
      expect(result.items.first.succeeded, isTrue);
      expect(
        result.items.last.denial,
        DirectMediaEgressDenial.attachmentNotCurrent,
      );
    },
  );

  testWidgets('selection is capped at ten and never over-caps egress', (
    tester,
  ) async {
    // The UI ceiling is an alias of the native egress ceiling — the two
    // cannot drift apart silently.
    expect(kMaxDirectMediaSelection, kMaxMediaEgressItems);
    expect(kMaxDirectMediaSelection, 10);

    // ── Coordinator boundary: an over-cap batch is refused BEFORE the
    // native boundary (the recording service throws on >10 by construction).
    parents['msg-cap'] = makeParent(id: 'msg-cap');
    final capPaths = <String, String>{};
    repo.seed([
      for (var i = 1; i <= 11; i++)
        makeRow(
          id: 'cap-$i',
          messageId: 'msg-cap',
          localPath: capPaths['cap-$i'] = writeMediaFile('cap-$i.jpg'),
        ),
    ]);
    final coordinator = buildCoordinator();
    await expectLater(
      coordinator.performBatchEgress(
        identities: [
          for (var i = 1; i <= 11; i++) identity('msg-cap', 'cap-$i'),
        ],
        destination: MediaEgressDestination.photos,
      ),
      throwsArgumentError,
    );
    expect(service.calls, isEmpty);

    // A full ten-item batch IS dispatched once with per-item-capable
    // handling — never the service's blanket over-cap rejection.
    final result = await coordinator.performBatchEgress(
      identities: [for (var i = 1; i <= 10; i++) identity('msg-cap', 'cap-$i')],
      destination: MediaEgressDestination.photos,
    );
    expect(service.calls, hasLength(1));
    expect(service.calls.single.selection, hasLength(10));
    expect(result.succeededIds, hasLength(10));

    // ── Selection controller: the ELEVENTH unique id is refused with
    // truthful semantics and no action can dispatch above the ceiling.
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final libraryRepo = StrictDirectMediaLibraryRepository(
      expectedContactPeerId: kContactPeerId,
    );
    libraryRepo.seedPage(
      entries: [
        for (var i = 1; i <= 11; i++)
          makeDirectLibraryEntry(
            'sel-$i',
            contactPeerId: kContactPeerId,
            messageId: 'msg-sel-$i',
            localPath: 'media/sel-$i.jpg',
          ),
      ],
      nextCursor: null,
    );

    final dispatched = <List<DirectReceivedMediaActionIdentity>>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DirectSharedMediaLibraryScreen(
          contactPeerId: kContactPeerId,
          contactUsername: 'Alice',
          libraryRepository: libraryRepo,
          stateRepository: libraryRepo,
          fileExists: (_) => true,
          resolveStoredPath: (storedPath) => storedPath,
          dispatchEgress: (identities, destination) async {
            if (identities.length > kMaxMediaEgressItems) {
              throw StateError('over-cap dispatch: ${identities.length}');
            }
            dispatched.add(identities);
            // Partial result: only the first three succeed — the rest must
            // STAY selected (failed-only retry), never a clear-all.
            return DirectMediaLibraryBatchResult(
              items: [
                for (var i = 0; i < identities.length; i++)
                  DirectMediaLibraryBatchItemOutcome(
                    attachmentId: identities[i].attachmentId,
                    succeeded: i < 3,
                    itemOutcome: i < 3
                        ? MediaEgressItemOutcome.saved
                        : MediaEgressItemOutcome.platformFailure,
                  ),
              ],
              egressResult: MediaEgressResult(
                requestId: 'req-cap',
                outcome: MediaEgressOutcome.partial,
                items: const [],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    for (var i = 1; i <= 10; i++) {
      await tester.longPress(find.byKey(ValueKey('shared-media-tile-sel-$i')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('10 selected'), findsOneWidget);

    // The eleventh unique selection is refused: truthful limit notice, the
    // count stays at ten, and no selected marker appears on the tile.
    await tester.longPress(
      find.byKey(const ValueKey('shared-media-tile-sel-11')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('10 selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shared-media-selected-sel-11')),
      findsNothing,
    );
    expect(find.text('You can select up to 10 items'), findsOneWidget);

    // Let the limit notice expire so it cannot obscure the action bar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    // Batch share dispatches exactly the ten selected identities (the
    // throwing spy proves nothing above the ceiling is ever dispatched) and
    // clears ONLY the successful three.
    await tester.tap(find.byKey(const ValueKey('shared-media-action-share')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(dispatched, hasLength(1));
    expect(dispatched.single, hasLength(10));
    expect(find.text('7 selected'), findsOneWidget);
    for (var i = 4; i <= 10; i++) {
      expect(
        find.byKey(ValueKey('shared-media-selected-sel-$i')),
        findsOneWidget,
        reason: 'failed item sel-$i must stay selected for retry',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
