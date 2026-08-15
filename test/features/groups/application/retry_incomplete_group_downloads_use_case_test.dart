import 'dart:async';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _validHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test(
    'P269 group download recovery pages past denied rows and converges eligible durable media exactly once',
    () async {
      final pageSnapshots = <RecoverableGroupDownloadCandidate>[
        _candidate(index: 1, id: '01-reparented'),
        _candidate(index: 2, id: '02-protected'),
        _candidate(index: 3, id: '03-removed'),
        _candidate(index: 4, id: '04-policy-denied', mediaType: 'video'),
        _candidate(index: 5, id: '05-terminal'),
        _candidate(index: 6, id: '06-malformed'),
        _candidate(
          index: 7,
          id: '07-downloading',
          status: kMediaDownloadStatusDownloading,
        ),
        _candidate(
          index: 8,
          id: '08-failed',
          status: kMediaDownloadStatusFailed,
          mediaType: 'audio',
          retryCount: 2,
        ),
        // The durable row was enriched by an offline-drain duplicate after
        // this page snapshot was selected. Recovery must transfer the exact
        // current row, not reject or transfer this stale descriptor.
        _candidate(
          index: 9,
          id: '09-direct-drain',
          staleDescriptorWithoutIntegrityMetadata: true,
        ),
      ];

      final attachments = <String, MediaAttachment>{
        for (final candidate in pageSnapshots)
          candidate.attachment.id: _currentAttachment(candidate),
      };
      attachments['01-reparented'] = attachments['01-reparented']!.copyWith(
        messageId: 'message-reused-by-another-parent',
      );
      attachments['05-terminal'] = attachments['05-terminal']!.copyWith(
        downloadStatus: kMediaDownloadStatusDownloadFailed,
        downloadRetryCount: 3,
      );
      attachments['06-malformed'] = attachments['06-malformed']!.copyWith(
        clearContentHash: true,
      );
      final sibling = _attachment(
        index: 99,
        id: 'unrelated-sibling',
        messageId: 'unrelated-message',
      );
      attachments[sibling.id] = sibling;

      final parents = <String, GroupMessage>{
        for (final candidate in pageSnapshots)
          candidate.attachment.messageId: _parent(candidate),
      };
      parents['message-02-protected'] = parents['message-02-protected']!
          .copyWith(
            privateMediaPolicy: const GroupPrivateMediaPolicy.protected(),
          );

      final groups = <String, GroupModel>{
        for (final candidate in pageSnapshots)
          candidate.groupId: _group(
            candidate.groupId,
            type: _groupTypeFor(candidate),
          ),
      };
      groups['group-03-removed'] = groups['group-03-removed']!.copyWith(
        selfRemovedAt: DateTime.utc(2026, 1, 3),
      );

      final deniedIds = <String>{
        '01-reparented',
        '02-protected',
        '03-removed',
        '04-policy-denied',
        '05-terminal',
        '06-malformed',
        sibling.id,
      };
      final deniedBefore = <String, Map<String, dynamic>>{
        for (final id in deniedIds) id: attachments[id]!.toMap(),
      };

      final pageLimits = <int>[];
      final pageCursors = <RecoverableGroupDownloadCursor?>[];
      final events = <String>[];
      final transfers = <String>[];
      final firstTransferEntered = Completer<void>();
      final releaseFirstTransfer = Completer<void>();
      final decider = _RecordingDecider(events);

      final recovery = RetryIncompleteGroupDownloadsUseCase(
        pageSize: 2,
        scanLimit: 9,
        transferLimit: 3,
        loadPage: ({required after, required limit}) async {
          pageLimits.add(limit);
          pageCursors.add(after);
          final start = after == null
              ? 0
              : pageSnapshots.indexWhere(
                      (candidate) =>
                          candidate.cursor.createdAt == after.createdAt &&
                          candidate.cursor.attachmentId == after.attachmentId,
                    ) +
                    1;
          return pageSnapshots.skip(start).take(limit).toList();
        },
        loadCurrentAttachment: (attachmentId) async =>
            attachments[attachmentId],
        loadCurrentParent: (messageId) async => parents[messageId],
        loadCurrentGroup: (groupId) async => groups[groupId],
        autoDownloadDecider: decider,
        transfer:
            ({required attachment, required parent, required group}) async {
              events.add('transfer:${attachment.id}');
              transfers.add(attachment.id);
              expect(parent.id, attachment.messageId);
              expect(parent.groupId, group.id);
              if (!firstTransferEntered.isCompleted) {
                firstTransferEntered.complete();
                await releaseFirstTransfer.future;
              }
              final downloaded = attachment.copyWith(
                localPath: 'group_media/${attachment.id}',
                downloadStatus: kMediaDownloadStatusDone,
                downloadRetryCount: 0,
              );
              attachments[attachment.id] = downloaded;
              return downloaded;
            },
      );

      final firstPass = recovery();
      await firstTransferEntered.future;
      final overlappingPass = recovery();
      expect(
        identical(firstPass, overlappingPass),
        isTrue,
        reason: 'overlapping automatic triggers must join one shared pass',
      );
      releaseFirstTransfer.complete();

      expect(await firstPass, 3);
      expect(await overlappingPass, 3);
      expect(transfers, <String>[
        '07-downloading',
        '08-failed',
        '09-direct-drain',
      ]);
      expect(pageLimits, <int>[2, 2, 2, 2, 1]);
      expect(
        pageCursors.map((cursor) => cursor?.attachmentId).toList(),
        <String?>[
          null,
          '02-protected',
          '04-policy-denied',
          '06-malformed',
          '08-failed',
        ],
      );
      expect(
        events,
        <String>[
          'policy:discussion:video:pending',
          'policy:discussion:image:downloading',
          'transfer:07-downloading',
          'policy:announcement:audio:failed',
          'transfer:08-failed',
          'policy:discussion:image:pending',
          'transfer:09-direct-drain',
        ],
        reason: 'the current policy decision must immediately precede transfer',
      );
      expect(decider.requests, hasLength(4));

      for (final entry in deniedBefore.entries) {
        expect(
          attachments[entry.key]!.toMap(),
          entry.value,
          reason: '${entry.key} must remain byte-for-byte unchanged',
        );
      }

      final callsAfterConvergence = transfers.length;
      expect(await recovery(), 0);
      expect(transfers, hasLength(callsAfterConvergence));
      expect(
        attachments['09-direct-drain']!.downloadStatus,
        kMediaDownloadStatusDone,
      );
    },
  );

  test(
    'shared coordinator merges targeted recovery and exposes completion before idle',
    () async {
      final global = _candidate(index: 1, id: 'global-row');
      final targeted = _candidate(index: 2, id: 'targeted-row');
      final attachments = <String, MediaAttachment>{
        global.attachment.id: global.attachment,
        targeted.attachment.id: targeted.attachment,
      };
      final parents = <String, GroupMessage>{
        global.attachment.messageId: _parent(global),
        targeted.attachment.messageId: _parent(targeted),
      };
      final groups = <String, GroupModel>{
        global.groupId: _group(global.groupId, type: GroupType.chat),
        targeted.groupId: _group(targeted.groupId, type: GroupType.chat),
      };
      final firstTransferEntered = Completer<void>();
      final releaseFirstTransfer = Completer<void>();
      final transferred = <String>[];

      final GroupMediaDownloadCoordinator coordinator =
          RetryIncompleteGroupDownloadsUseCase(
            pageSize: 1,
            scanLimit: 2,
            transferLimit: 2,
            loadPage: ({required after, required limit}) async => after == null
                ? <RecoverableGroupDownloadCandidate>[global]
                : const <RecoverableGroupDownloadCandidate>[],
            loadCurrentAttachment: (id) async => attachments[id],
            loadCurrentParent: (id) async => parents[id],
            loadCurrentGroup: (id) async => groups[id],
            autoDownloadDecider: _RecordingDecider(<String>[]),
            transfer:
                ({required attachment, required parent, required group}) async {
                  transferred.add(attachment.id);
                  if (!firstTransferEntered.isCompleted) {
                    firstTransferEntered.complete();
                    await releaseFirstTransfer.future;
                  }
                  final downloaded = attachment.copyWith(
                    downloadStatus: kMediaDownloadStatusDone,
                    localPath: 'group_media/${attachment.id}',
                  );
                  attachments[attachment.id] = downloaded;
                  return downloaded;
                },
          );

      final globalPass = coordinator.sweep();
      await firstTransferEntered.future;
      final targetedPass = coordinator.recoverAttachments(
        groupId: targeted.groupId,
        attachmentIds: <String>[targeted.attachment.id, targeted.attachment.id],
      );
      expect(identical(globalPass, targetedPass), isTrue);
      expect(coordinator.isIdle, isFalse);

      var idleObserved = false;
      final idle = coordinator.waitForIdle().then((_) => idleObserved = true);
      await Future<void>.delayed(Duration.zero);
      expect(idleObserved, isFalse);

      releaseFirstTransfer.complete();
      final result = await globalPass;
      await idle;

      expect(coordinator.isIdle, isTrue);
      expect(idleObserved, isTrue);
      expect(transferred, <String>['global-row', 'targeted-row']);
      expect(result.scannedCount, 2);
      expect(result.attemptedTransferCount, 2);
      expect(result.successfulTransferCount, 2);
      expect(result.downloadedAttachmentIds, <String>{
        'global-row',
        'targeted-row',
      });
      expect(result.affectedMessageIds, <String>{
        'message-global-row',
        'message-targeted-row',
      });
      expect(await targetedPass, same(result));
    },
  );

  test(
    'P269 targeted recovery retains every merged ID across bounded chunks',
    () async {
      final candidates = <RecoverableGroupDownloadCandidate>[
        for (var index = 1; index <= 5; index++)
          _candidate(index: index, id: 'target-$index'),
      ];
      final attachments = <String, MediaAttachment>{
        for (final candidate in candidates)
          candidate.attachment.id: candidate.attachment,
      };
      final parents = <String, GroupMessage>{
        for (final candidate in candidates)
          candidate.attachment.messageId: _parent(candidate),
      };
      final groups = <String, GroupModel>{
        for (final candidate in candidates)
          candidate.groupId: _group(candidate.groupId, type: GroupType.chat),
      };
      final firstTransferEntered = Completer<void>();
      final releaseFirstTransfer = Completer<void>();
      final transfers = <String>[];

      final recovery = RetryIncompleteGroupDownloadsUseCase(
        pageSize: 1,
        scanLimit: 2,
        transferLimit: 1,
        loadPage: ({required after, required limit}) async =>
            const <RecoverableGroupDownloadCandidate>[],
        loadCurrentAttachment: (id) async => attachments[id],
        loadCurrentParent: (id) async => parents[id],
        loadCurrentGroup: (id) async => groups[id],
        autoDownloadDecider: _RecordingDecider(<String>[]),
        transfer:
            ({required attachment, required parent, required group}) async {
              transfers.add(attachment.id);
              if (!firstTransferEntered.isCompleted) {
                firstTransferEntered.complete();
                await releaseFirstTransfer.future;
              }
              final downloaded = attachment.copyWith(
                downloadStatus: kMediaDownloadStatusDone,
                localPath: 'group_media/${attachment.id}',
              );
              attachments[attachment.id] = downloaded;
              return downloaded;
            },
      );

      final first = recovery.recoverAttachments(
        groupId: candidates.first.groupId,
        attachmentIds: const <String>['target-1'],
      );
      await firstTransferEntered.future;
      for (final candidate in candidates.skip(1)) {
        final merged = recovery.recoverAttachments(
          groupId: candidate.groupId,
          attachmentIds: <String>[
            candidate.attachment.id,
            candidate.attachment.id,
          ],
        );
        expect(identical(first, merged), isTrue);
      }
      releaseFirstTransfer.complete();

      final result = await first;
      expect(recovery.isIdle, isTrue);
      expect(transfers, <String>[
        'target-1',
        'target-2',
        'target-3',
        'target-4',
        'target-5',
      ]);
      expect(result.scannedCount, 5);
      expect(result.attemptedTransferCount, 5);
      expect(result.successfulTransferCount, 5);
      expect(result.downloadedAttachmentIds, {
        'target-1',
        'target-2',
        'target-3',
        'target-4',
        'target-5',
      });

      for (final candidate in candidates) {
        final second = await recovery.recoverAttachments(
          groupId: candidate.groupId,
          attachmentIds: <String>[candidate.attachment.id],
        );
        expect(second.successfulTransferCount, 0);
      }
      expect(transfers, hasLength(5));
    },
  );

  test(
    'P269 bounded recovery sweeps retain fair cursor progress across denied prefixes',
    () async {
      final candidates = <RecoverableGroupDownloadCandidate>[
        _candidate(index: 1, id: '01-policy-denied', mediaType: 'video'),
        _candidate(
          index: 2,
          id: '02-malformed',
          staleDescriptorWithoutIntegrityMetadata: true,
        ),
        _candidate(index: 3, id: '03-policy-denied', mediaType: 'video'),
        _candidate(index: 4, id: '04-eligible'),
      ];
      final attachments = <String, MediaAttachment>{
        for (final candidate in candidates)
          candidate.attachment.id: candidate.attachment,
      };
      final parents = <String, GroupMessage>{
        for (final candidate in candidates)
          candidate.attachment.messageId: _parent(candidate),
      };
      final groups = <String, GroupModel>{
        for (final candidate in candidates)
          candidate.groupId: _group(candidate.groupId, type: GroupType.chat),
      };
      final requestedAfter = <String?>[];
      final transferred = <String>[];

      final recovery = RetryIncompleteGroupDownloadsUseCase(
        pageSize: 1,
        scanLimit: 2,
        transferLimit: 1,
        loadPage: ({required after, required limit}) async {
          requestedAfter.add(after?.attachmentId);
          final start = after == null
              ? 0
              : candidates.indexWhere(
                      (candidate) => candidate.cursor == after,
                    ) +
                    1;
          return candidates.skip(start).take(limit).toList(growable: false);
        },
        loadCurrentAttachment: (id) async => attachments[id],
        loadCurrentParent: (id) async => parents[id],
        loadCurrentGroup: (id) async => groups[id],
        autoDownloadDecider: _RecordingDecider(<String>[]),
        transfer:
            ({required attachment, required parent, required group}) async {
              transferred.add(attachment.id);
              final downloaded = attachment.copyWith(
                downloadStatus: kMediaDownloadStatusDone,
                localPath: 'group_media/${attachment.id}',
              );
              attachments[attachment.id] = downloaded;
              return downloaded;
            },
      );

      expect(await recovery(), 0);
      expect(await recovery(), 1);
      expect(transferred, <String>['04-eligible']);
      expect(
        requestedAfter,
        <String?>[null, '01-policy-denied', '02-malformed', '03-policy-denied'],
        reason:
            'the second bounded sweep must resume after the first scan bound',
      );
    },
  );

  test(
    'P269 account authority precedes the final automatic download policy read',
    () async {
      final candidate = _candidate(index: 1, id: 'policy-race');
      var current = candidate.attachment;
      final parent = _parent(candidate);
      final group = _group(candidate.groupId, type: GroupType.chat);
      final events = <String>[];
      var policyAllowed = true;

      final recovery = RetryIncompleteGroupDownloadsUseCase(
        loadPage: ({required after, required limit}) async => after == null
            ? <RecoverableGroupDownloadCandidate>[candidate]
            : const <RecoverableGroupDownloadCandidate>[],
        loadCurrentAttachment: (id) async => current,
        loadCurrentParent: (id) async => parent,
        loadCurrentGroup: (id) async => group,
        allowsNetworkSideEffects: () async {
          events.add('account');
          policyAllowed = false;
          return true;
        },
        autoDownloadDecider: _CallbackDecider(() {
          events.add('policy');
          return policyAllowed;
        }),
        transfer:
            ({required attachment, required parent, required group}) async {
              events.add('transfer');
              current = attachment.copyWith(
                downloadStatus: kMediaDownloadStatusDone,
                localPath: 'group_media/${attachment.id}',
              );
              return current;
            },
      );

      expect(await recovery(), 0);
      expect(events, <String>['account', 'policy']);
      expect(current.toMap(), candidate.attachment.toMap());
    },
  );

  test(
    'P269 real repository recovery composes durable paging with automatic claim commit authority',
    () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);

      const groupId = 'group-real-recovery';
      final parents = <String, GroupMessage>{};
      for (final descriptor in const <(int, String, String, bool)>[
        (1, '01-policy-denied', 'video', true),
        (2, '02-malformed', 'image', false),
        (3, '03-policy-denied', 'video', true),
        (4, '04-eligible', 'image', true),
      ]) {
        final createdAt = DateTime.utc(
          2026,
          7,
          descriptor.$1,
        ).toIso8601String();
        final messageId = 'message-${descriptor.$2}';
        await fixture.seedGroupParent(
          messageId,
          groupId: groupId,
          timestamp: createdAt,
        );
        final candidate = RecoverableGroupDownloadCandidate(
          attachment: _attachment(
            index: descriptor.$1,
            id: descriptor.$2,
            messageId: messageId,
            mediaType: descriptor.$3,
          ).copyWith(createdAt: createdAt, clearContentHash: !descriptor.$4),
          groupId: groupId,
        );
        parents[messageId] = _parent(candidate);
        await fixture.repo.saveAttachment(
          candidate.attachment,
          owner: MediaOwnerLane.group,
        );
      }

      final group = _group(groupId, type: GroupType.chat);
      final automaticState =
          fixture.repo as OrdinaryGroupAutomaticMediaDownloadStateRepository;
      final transfers = <String>[];
      final recovery = RetryIncompleteGroupDownloadsUseCase(
        pageSize: 1,
        scanLimit: 2,
        transferLimit: 1,
        loadPage: ({required after, required limit}) async {
          final rows = await fixture.repo.loadRecoverableGroupDownloadPage(
            after: after == null
                ? null
                : DurableGroupMediaDownloadCursor(
                    createdAt: after.createdAt,
                    attachmentId: after.attachmentId,
                  ),
            limit: limit,
          );
          return rows
              .map(
                (row) => RecoverableGroupDownloadCandidate(
                  attachment: row.attachment,
                  groupId: row.groupId,
                ),
              )
              .toList(growable: false);
        },
        loadCurrentAttachment: fixture.repo.getAttachmentById,
        loadCurrentParent: (id) async => parents[id],
        loadCurrentGroup: (id) async => id == groupId ? group : null,
        autoDownloadDecider: _RecordingDecider(<String>[]),
        transfer:
            ({required attachment, required parent, required group}) async {
              transfers.add(attachment.id);
              final claimed = await automaticState
                  .beginOrdinaryGroupAutomaticMediaDownload(
                    attachment.id,
                    groupId: group.id,
                    messageId: parent.id,
                    expectedDownloadStatus: attachment.downloadStatus,
                    expectedLocalPath: attachment.localPath,
                  );
              if (!claimed) return null;
              final committed = await automaticState
                  .commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
                    attachment.id,
                    groupId: group.id,
                    messageId: parent.id,
                    expectedLocalPath: attachment.localPath,
                    localPath: 'group_media/${attachment.id}.bin',
                  );
              return committed
                  ? fixture.repo.getAttachmentById(attachment.id)
                  : null;
            },
      );

      expect(await recovery(), 0);
      expect(await recovery(), 1);
      expect(transfers, <String>['04-eligible']);
      final settled = await fixture.rawAttachmentRow('04-eligible');
      expect(settled!['download_status'], kMediaDownloadStatusDone);
      expect(settled['local_path'], 'group_media/04-eligible.bin');
      expect(
        (await fixture.rawAttachmentRow(
          '01-policy-denied',
        ))!['download_status'],
        kMediaDownloadStatusPending,
      );
      expect(
        (await fixture.rawAttachmentRow('02-malformed'))!['download_status'],
        kMediaDownloadStatusPending,
      );
      expect(
        (await fixture.rawAttachmentRow(
          '03-policy-denied',
        ))!['download_status'],
        kMediaDownloadStatusPending,
      );
    },
  );

  test('TC-365-03a strict group blob ACK recovery is source pinned', () async {
    final strictCandidate = _candidate(
      index: 1,
      id: 'tc365-strict-voice',
      mediaType: 'audio',
    );
    final ordinaryCandidate = _candidate(index: 2, id: 'tc365-ordinary-image');
    final attachments = <String, MediaAttachment>{
      strictCandidate.attachment.id: strictCandidate.attachment.copyWith(
        groupMediaBlobCustodyFingerprint: _validHash,
      ),
      ordinaryCandidate.attachment.id: ordinaryCandidate.attachment,
    };
    final parents = <String, GroupMessage>{
      strictCandidate.attachment.messageId: _parent(strictCandidate),
      ordinaryCandidate.attachment.messageId: _parent(ordinaryCandidate),
    };
    final groups = <String, GroupModel>{
      strictCandidate.groupId: _group(
        strictCandidate.groupId,
        type: GroupType.chat,
      ),
      ordinaryCandidate.groupId: _group(
        ordinaryCandidate.groupId,
        type: GroupType.chat,
      ),
    };
    final strictAckSources = <String>[];
    final legacyTransfers = <String>[];
    var strictAttempt = 0;
    var ackDrainCalls = 0;
    var ackDrainProgress = 0;
    final recovery = RetryIncompleteGroupDownloadsUseCase(
      pageSize: 2,
      scanLimit: 2,
      transferLimit: 2,
      loadPage: ({required after, required limit}) async {
        final candidates = <RecoverableGroupDownloadCandidate>[
          RecoverableGroupDownloadCandidate(
            attachment: attachments[strictCandidate.attachment.id]!,
            groupId: strictCandidate.groupId,
          ),
          RecoverableGroupDownloadCandidate(
            attachment: attachments[ordinaryCandidate.attachment.id]!,
            groupId: ordinaryCandidate.groupId,
          ),
        ];
        return candidates
            .where(
              (candidate) =>
                  after == null || candidate.cursor.compareTo(after) > 0,
            )
            .take(limit)
            .toList(growable: false);
      },
      loadCurrentAttachment: (id) async => attachments[id],
      loadCurrentParent: (id) async => parents[id],
      loadCurrentGroup: (id) async => groups[id],
      autoDownloadDecider: _RecordingDecider(<String>[]),
      retryPendingStrictAcknowledgements: () async {
        ackDrainCalls++;
        return ackDrainProgress;
      },
      transfer: ({required attachment, required parent, required group}) async {
        expect(
          attachment.groupMediaBlobCustodyFingerprint,
          isNull,
          reason: 'fingerprinted rows never enter the legacy transfer',
        );
        legacyTransfers.add(attachment.id);
        final done = attachment.copyWith(
          localPath: 'group_media/${attachment.id}',
          downloadStatus: kMediaDownloadStatusDone,
        );
        attachments[attachment.id] = done;
        return done;
      },
      strictTransfer:
          ({required attachment, required parent, required group}) async {
            expect(attachment.groupMediaBlobCustodyFingerprint, _validHash);
            // The strict owner reloads this durable relay source on restart;
            // no roster, proof-less delete or alternate relay is consulted.
            strictAckSources.add('relay-source-tc365');
            strictAttempt++;
            if (strictAttempt == 1) return null;
            final done = attachment.copyWith(
              localPath: 'group_media/${attachment.id}',
              downloadStatus: kMediaDownloadStatusDone,
            );
            attachments[attachment.id] = done;
            return done;
          },
    );

    expect(await recovery(), 1);
    expect(
      legacyTransfers,
      <String>[ordinaryCandidate.attachment.id],
      reason: 'an ACK failure must not starve the next bounded candidate',
    );
    expect(
      await recovery(),
      0,
      reason: 'the persisted cursor first proves the prior page is exhausted',
    );
    expect(await recovery(), 1);
    expect(strictAckSources, <String>[
      'relay-source-tc365',
      'relay-source-tc365',
    ]);
    expect(ackDrainCalls, 3);
    expect(
      legacyTransfers,
      <String>[ordinaryCandidate.attachment.id],
      reason: 'restart recovery retries strict ownership, never legacy',
    );

    attachments[strictCandidate.attachment.id] = strictCandidate.attachment
        .copyWith(groupMediaBlobCustodyFingerprint: _validHash);
    attachments[ordinaryCandidate.attachment.id] = ordinaryCandidate.attachment;
    ackDrainProgress = 1;
    expect(
      await recovery.callStrictGroupMediaCustodyOnly(),
      2,
      reason: 'one ACK_PENDING retirement plus one strict voice download',
    );
    expect(ackDrainCalls, 4);
    expect(strictAckSources, <String>[
      'relay-source-tc365',
      'relay-source-tc365',
      'relay-source-tc365',
    ]);
    expect(
      legacyTransfers,
      <String>[ordinaryCandidate.attachment.id],
      reason: 'the restricted drain never invokes the legacy transfer owner',
    );
  });
}

class _RecordingDecider implements MediaAutoDownloadDecider {
  _RecordingDecider(this.events);

  final List<String> events;
  final List<_PolicyRequest> requests = <_PolicyRequest>[];

  @override
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  }) async {
    requests.add(
      _PolicyRequest(
        conversationKind: conversationKind,
        storageOwner: storageOwner,
        mediaType: mediaType,
        downloadStatus: downloadStatus,
        userInitiated: userInitiated,
        isProtected: isProtected,
      ),
    );
    events.add('policy:${conversationKind.name}:$mediaType:$downloadStatus');
    expect(storageOwner, MediaOwnerLane.group);
    expect(userInitiated, isFalse);
    expect(isProtected, isFalse);
    return mediaType != 'video';
  }
}

class _PolicyRequest {
  const _PolicyRequest({
    required this.conversationKind,
    required this.storageOwner,
    required this.mediaType,
    required this.downloadStatus,
    required this.userInitiated,
    required this.isProtected,
  });

  final MediaConversationKind conversationKind;
  final MediaOwnerLane? storageOwner;
  final String mediaType;
  final String downloadStatus;
  final bool userInitiated;
  final bool isProtected;
}

class _CallbackDecider implements MediaAutoDownloadDecider {
  const _CallbackDecider(this.decide);

  final bool Function() decide;

  @override
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  }) async => decide();
}

RecoverableGroupDownloadCandidate _candidate({
  required int index,
  required String id,
  String status = kMediaDownloadStatusPending,
  String mediaType = 'image',
  int? retryCount,
  bool staleDescriptorWithoutIntegrityMetadata = false,
}) {
  final messageId = 'message-$id';
  var attachment = _attachment(
    index: index,
    id: id,
    messageId: messageId,
    status: status,
    mediaType: mediaType,
    retryCount: retryCount,
  );
  if (staleDescriptorWithoutIntegrityMetadata) {
    attachment = attachment.copyWith(
      clearContentHash: true,
      clearEncryptionKeyBase64: true,
      clearEncryptionNonce: true,
    );
  }
  return RecoverableGroupDownloadCandidate(
    attachment: attachment,
    groupId: 'group-$id',
  );
}

MediaAttachment _currentAttachment(
  RecoverableGroupDownloadCandidate candidate,
) {
  if (candidate.attachment.id != '09-direct-drain') {
    return candidate.attachment;
  }
  return candidate.attachment.copyWith(
    contentHash: _validHash,
    encryptionKeyBase64: 'offline-drain-key',
    encryptionNonce: 'offline-drain-nonce',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

MediaAttachment _attachment({
  required int index,
  required String id,
  required String messageId,
  String status = kMediaDownloadStatusPending,
  String mediaType = 'image',
  int? retryCount,
}) {
  final mime = switch (mediaType) {
    'video' => 'video/mp4',
    'audio' => 'audio/mp4',
    'file' => 'application/pdf',
    _ => 'image/jpeg',
  };
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1024,
    mediaType: mediaType,
    downloadStatus: status,
    createdAt: DateTime.utc(2026, 1, index).toIso8601String(),
    downloadRetryCount: retryCount,
    contentHash: _validHash,
    encryptionKeyBase64: 'key-$id',
    encryptionNonce: 'nonce-$id',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ownerLane: MediaOwnerLane.group,
  );
}

GroupMessage _parent(RecoverableGroupDownloadCandidate candidate) {
  final timestamp = DateTime.parse(candidate.attachment.createdAt);
  return GroupMessage(
    id: candidate.attachment.messageId,
    groupId: candidate.groupId,
    senderPeerId: 'sender-peer',
    text: '',
    timestamp: timestamp,
    isIncoming: true,
    privateMediaPolicy: const GroupPrivateMediaPolicy.ordinary(),
    createdAt: timestamp,
  );
}

GroupModel _group(String id, {required GroupType type}) => GroupModel(
  id: id,
  name: id,
  type: type,
  topicName: 'topic-$id',
  createdAt: DateTime.utc(2025),
  createdBy: 'creator-peer',
  myRole: GroupRole.member,
);

GroupType _groupTypeFor(RecoverableGroupDownloadCandidate candidate) {
  if (candidate.attachment.id == '08-failed') return GroupType.announcement;
  if (candidate.attachment.id == '09-direct-drain') return GroupType.qa;
  return GroupType.chat;
}
