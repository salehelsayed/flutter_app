import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _AllowAllDownloads implements MediaAutoDownloadDecider {
  @override
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  }) async => true;
}

class _MutableLifecycleState {
  _MutableLifecycleState(this.value);

  AppLifecycleState value;
}

class _ListenerHarness {
  _ListenerHarness._({
    required this.groupRepo,
    required this.messageRepo,
    required this.mediaRepo,
    required this.coordinator,
    required this.listener,
    required this.lifecycle,
    required this.operations,
    required this.transferStarted,
  });

  final InMemoryGroupRepository groupRepo;
  final InMemoryGroupMessageRepository messageRepo;
  final InMemoryMediaAttachmentRepository mediaRepo;
  final RetryIncompleteGroupDownloadsUseCase coordinator;
  final GroupMessageListener listener;
  final _MutableLifecycleState lifecycle;
  final List<String> operations;
  final Completer<void> transferStarted;

  static Future<_ListenerHarness> create({
    required AppLifecycleState lifecycleState,
    required String? grantedTaskId,
    Completer<void>? transferGate,
    bool throwDuringTransfer = false,
  }) async {
    final groupRepo = InMemoryGroupRepository();
    final messageRepo = InMemoryGroupMessageRepository();
    final mediaRepo = InMemoryMediaAttachmentRepository();
    final operations = <String>[];
    final transferStarted = Completer<void>();
    final lifecycle = _MutableLifecycleState(lifecycleState);
    final createdAt = DateTime.utc(2026, 7, 22, 16);

    await groupRepo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Group media reliability',
        type: GroupType.chat,
        topicName: 'group-topic-1',
        createdAt: createdAt,
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      ),
    );
    for (final member in <GroupMember>[
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: createdAt,
      ),
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-self',
        username: 'Self',
        role: MemberRole.writer,
        joinedAt: createdAt,
      ),
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-sender',
        username: 'Sender',
        role: MemberRole.writer,
        joinedAt: createdAt,
      ),
    ]) {
      await groupRepo.saveMember(member);
    }

    final coordinator = RetryIncompleteGroupDownloadsUseCase(
      loadPage: ({required after, required limit}) async => const [],
      loadCurrentAttachment: mediaRepo.getAttachmentById,
      loadCurrentParent: messageRepo.getMessage,
      loadCurrentGroup: groupRepo.getGroup,
      autoDownloadDecider: _AllowAllDownloads(),
      transfer: ({required attachment, required parent, required group}) async {
        operations.add('transfer:${attachment.id}');
        if (!transferStarted.isCompleted) transferStarted.complete();
        if (transferGate != null) await transferGate.future;
        if (throwDuringTransfer) {
          throw StateError('simulated receiver transfer interruption');
        }
        await mediaRepo.updateLocalPath(
          attachment.id,
          '/durable/${attachment.id}',
        );
        return mediaRepo.getAttachmentById(attachment.id);
      },
    );

    final listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: messageRepo,
      getSelfPeerId: () async => 'peer-self',
      mediaAttachmentRepo: mediaRepo,
      getAppLifecycleState: () => lifecycle.value,
      groupMediaDownloadCoordinator: coordinator,
      beginGroupMediaReceiveCriticalTask: () async {
        operations.add('begin');
        return grantedTaskId;
      },
      endGroupMediaReceiveCriticalTask: (taskId) async {
        operations.add('end:$taskId');
      },
    );

    return _ListenerHarness._(
      groupRepo: groupRepo,
      messageRepo: messageRepo,
      mediaRepo: mediaRepo,
      coordinator: coordinator,
      listener: listener,
      lifecycle: lifecycle,
      operations: operations,
      transferStarted: transferStarted,
    );
  }

  Future<void> receiveOrdinaryMedia(String suffix) {
    final timestamp = DateTime.utc(2026, 7, 22, 16, 1).toIso8601String();
    return listener.handleReplayEnvelope({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'messageId': 'message-$suffix',
      'text': 'Media $suffix',
      'timestamp': timestamp,
      'media': [
        {
          'id': 'attachment-$suffix',
          'mime': 'image/jpeg',
          'size': 4096,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-$suffix',
          'encryptionNonce': 'nonce-$suffix',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'createdAt': timestamp,
        },
      ],
    });
  }

  Future<void> receiveTextOnly(String suffix) {
    return listener.handleReplayEnvelope({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'messageId': 'message-$suffix',
      'text': 'Text only',
      'timestamp': DateTime.utc(2026, 7, 22, 16, 2).toIso8601String(),
    });
  }

  Future<void> receivePrivateMedia(String suffix) {
    final timestamp = DateTime.utc(2026, 7, 22, 16, 3).toIso8601String();
    return listener.handleReplayEnvelope({
      'groupId': 'group-1',
      'senderId': 'peer-sender',
      'senderUsername': 'Sender',
      'keyEpoch': 0,
      'messageId': 'message-$suffix',
      'text': '',
      'timestamp': timestamp,
      'mediaPolicyVersion': 1,
      'mediaLifecycle': 'viewOnce',
      'mediaProtected': true,
      'media': [
        {
          'id': 'attachment-$suffix',
          'mime': 'image/jpeg',
          'size': 4096,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-$suffix',
          'encryptionNonce': 'nonce-$suffix',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'createdAt': timestamp,
        },
      ],
    });
  }

  Future<void> close() async {
    await listener.stop();
    listener.dispose();
  }
}

void main() {
  test(
    'P269 foreground handoff reservation shares one task with background receive',
    () async {
      final transferGate = Completer<void>();
      final harness = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.resumed,
        grantedTaskId: 'task-handoff',
        transferGate: transferGate,
      );

      final reservation = await harness.listener
          .reserveGroupMediaReceiveCriticalTaskForForegroundHandoff();
      expect(harness.operations, <String>['begin']);

      // The native app may already be backgrounded while Flutter still reports
      // the last foreground lifecycle value. The explicit handoff reservation
      // is the stronger authority for joining the shared lease.
      await harness.receiveOrdinaryMedia('handoff');
      await harness.transferStarted.future.timeout(const Duration(seconds: 2));
      expect(harness.operations, <String>[
        'begin',
        'transfer:attachment-handoff',
      ]);

      await reservation.release();
      await reservation.release();
      expect(
        harness.operations,
        <String>['begin', 'transfer:attachment-handoff'],
        reason:
            'the shared native task must remain live for the transfer participant',
      );

      var stopCompleted = false;
      final stop = harness.listener.stop().whenComplete(() {
        stopCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(stopCompleted, isFalse);

      transferGate.complete();
      await stop;
      expect(harness.operations, <String>[
        'begin',
        'transfer:attachment-handoff',
        'end:task-handoff',
      ]);
      await harness.close();
    },
  );

  test(
    'P269 foreground handoff fails closed when iOS refuses a native task',
    () async {
      final harness = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.resumed,
        grantedTaskId: null,
      );

      await expectLater(
        harness.listener
            .reserveGroupMediaReceiveCriticalTaskForForegroundHandoff(),
        throwsStateError,
      );
      expect(harness.operations, <String>['begin']);
      await harness.close();
    },
  );

  test(
    'P269 stop waits for an idempotently released foreground reservation',
    () async {
      final harness = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.resumed,
        grantedTaskId: 'task-stop-reservation',
      );
      final reservation = await harness.listener
          .reserveGroupMediaReceiveCriticalTaskForForegroundHandoff();

      harness.lifecycle.value = AppLifecycleState.hidden;
      await harness.receiveOrdinaryMedia('stop-reservation');
      await harness.transferStarted.future.timeout(const Duration(seconds: 2));
      await harness.coordinator.waitForIdle();
      expect(harness.operations, <String>[
        'begin',
        'transfer:attachment-stop-reservation',
      ]);

      var stopCompleted = false;
      final stop = harness.listener.stop().whenComplete(() {
        stopCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(stopCompleted, isFalse);

      await reservation.release();
      await reservation.release();
      await stop;
      expect(harness.operations, <String>[
        'begin',
        'transfer:attachment-stop-reservation',
        'end:task-stop-reservation',
      ]);
      await harness.close();
    },
  );

  test(
    'P269 two overlapping background media messages share one critical task and stop waits',
    () async {
      final transferGate = Completer<void>();
      final harness = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.paused,
        grantedTaskId: 'task-overlap',
        transferGate: transferGate,
      );

      await harness.receiveOrdinaryMedia('overlap-a');
      await harness.transferStarted.future.timeout(const Duration(seconds: 2));
      await harness.receiveOrdinaryMedia('overlap-b');
      await Future<void>.delayed(Duration.zero);
      expect(
        harness.operations.where((operation) => operation == 'begin'),
        hasLength(1),
      );
      expect(harness.operations, isNot(contains('end:task-overlap')));

      var stopCompleted = false;
      final stop = harness.listener.stop().whenComplete(() {
        stopCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(stopCompleted, isFalse);

      transferGate.complete();
      await stop;
      expect(harness.operations, <String>[
        'begin',
        'transfer:attachment-overlap-a',
        'transfer:attachment-overlap-b',
        'end:task-overlap',
      ]);
      await harness.close();
    },
  );

  test(
    'P269 background group media receive balances grant refusal success throw and stop wait',
    () async {
      final transferGate = Completer<void>();
      final granted = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.paused,
        grantedTaskId: 'task-granted',
        transferGate: transferGate,
      );
      await granted.receiveOrdinaryMedia('granted');
      await granted.transferStarted.future.timeout(const Duration(seconds: 2));
      expect(granted.operations, <String>[
        'begin',
        'transfer:attachment-granted',
      ]);

      var stopCompleted = false;
      final stop = granted.listener.stop().whenComplete(() {
        stopCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        stopCompleted,
        isFalse,
        reason: 'stop must await the receive batch',
      );
      expect(granted.operations, isNot(contains('end:task-granted')));

      transferGate.complete();
      await stop;
      expect(granted.operations, <String>[
        'begin',
        'transfer:attachment-granted',
        'end:task-granted',
      ]);
      await granted.close();

      final refused = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.hidden,
        grantedTaskId: null,
      );
      await refused.receiveOrdinaryMedia('refused');
      await refused.transferStarted.future.timeout(const Duration(seconds: 2));
      await refused.coordinator.waitForIdle();
      expect(refused.operations, <String>[
        'begin',
        'transfer:attachment-refused',
      ]);
      await refused.close();

      final interrupted = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.inactive,
        grantedTaskId: 'task-interrupted',
        throwDuringTransfer: true,
      );
      await interrupted.receiveOrdinaryMedia('interrupted');
      await interrupted.transferStarted.future.timeout(
        const Duration(seconds: 2),
      );
      await interrupted.coordinator.waitForIdle();
      expect(interrupted.operations, <String>[
        'begin',
        'transfer:attachment-interrupted',
        'end:task-interrupted',
      ]);
      final retryable = await interrupted.mediaRepo.getAttachmentById(
        'attachment-interrupted',
      );
      expect(retryable, isNotNull);
      expect(retryable!.downloadStatus, 'pending');
      expect(retryable.localPath, isNull);
      await interrupted.close();

      final resumed = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.resumed,
        grantedTaskId: 'must-not-be-used',
      );
      await resumed.receiveOrdinaryMedia('resumed');
      await resumed.transferStarted.future.timeout(const Duration(seconds: 2));
      await resumed.coordinator.waitForIdle();
      expect(resumed.operations, <String>['transfer:attachment-resumed']);
      await resumed.close();

      final ineligible = await _ListenerHarness.create(
        lifecycleState: AppLifecycleState.paused,
        grantedTaskId: 'must-not-be-used',
      );
      await ineligible.receiveTextOnly('text');
      await ineligible.receivePrivateMedia('private');
      await Future<void>.delayed(Duration.zero);
      expect(ineligible.operations, isEmpty);
      await ineligible.close();
    },
  );
}
