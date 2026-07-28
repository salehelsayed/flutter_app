import 'dart:io';

import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PendingComposerMedia pendingMedia(
    String path, {
    required int budgetBytes,
    int? width,
    int? height,
    int? durationMs,
  }) {
    return PendingComposerMedia(
      file: File(path),
      budgetBytes: budgetBytes,
      width: width,
      height: height,
      durationMs: durationMs,
    );
  }

  ConversationComposerViewState projectedState({
    required List<PendingComposerMedia> pendingAttachments,
    bool isUploading = false,
    VoiceRecordingState recordingState = VoiceRecordingState.idle,
    PrivateMediaPolicy privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
  }) {
    return ConversationComposerViewState(
      pendingAttachments: pendingAttachments
          .map((attachment) => attachment.file)
          .toList(growable: false),
      invalidAttachmentIndices: const <int>{1},
      invalidAttachmentReasons: const <int, String>{1: 'too_large'},
      hasTotalSizeOverflow: false,
      isUploading: isUploading,
      isProcessing: true,
      processingProgress: 0.5,
      processingCurrent: 1,
      processingTotal: 2,
      recordingState: recordingState,
      recordingDuration: const Duration(seconds: 3),
      amplitudeValues: const <double>[0.1, 0.6],
      privateMediaEligibility: const PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
      ),
      privateMediaPolicy: privateMediaPolicy,
    );
  }

  test(
    'publishes only semantic composer changes and restores the exact common snapshot',
    () {
      final first = pendingMedia(
        '/tmp/controller-first.jpg',
        budgetBytes: 123,
        width: 20,
        height: 30,
      );
      final second = pendingMedia(
        '/tmp/controller-second.mp4',
        budgetBytes: 456,
        width: 40,
        height: 50,
        durationMs: 6000,
      );
      final initialState = projectedState(
        pendingAttachments: <PendingComposerMedia>[first],
      );
      final controller = ConversationComposerController(
        initialState: initialState,
        initialPendingAttachments: <PendingComposerMedia>[first],
      );
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      final samePathAndSemantics = projectedState(
        pendingAttachments: <PendingComposerMedia>[
          pendingMedia(
            first.file.path,
            budgetBytes: 999,
            width: 99,
            height: 99,
          ),
        ],
      );
      expect(
        controller.publish(
          state: samePathAndSemantics,
          pendingAttachments: <PendingComposerMedia>[
            pendingMedia(
              first.file.path,
              budgetBytes: 999,
              width: 99,
              height: 99,
            ),
          ],
        ),
        isFalse,
      );
      expect(notifications, 0);
      expect(controller.pendingAttachments.single.budgetBytes, 999);

      final changedState = projectedState(
        pendingAttachments: <PendingComposerMedia>[first, second],
        isUploading: true,
        recordingState: VoiceRecordingState.recording,
      );
      expect(
        controller.publish(
          state: changedState,
          pendingAttachments: <PendingComposerMedia>[first, second],
        ),
        isTrue,
      );
      expect(notifications, 1);

      final snapshot = controller.snapshot(
        draftText: 'kept draft',
        quotedMessageId: 'quoted-message',
      );
      expect(snapshot.draftText, 'kept draft');
      expect(snapshot.quotedMessageId, 'quoted-message');
      expect(
        snapshot.pendingAttachments
            .map((attachment) => attachment.file.path)
            .toList(),
        <String>[first.file.path, second.file.path],
      );

      controller.publish(
        state: const ConversationComposerViewState(),
        pendingAttachments: const <PendingComposerMedia>[],
      );
      expect(notifications, 2);

      final restoredState = projectedState(
        pendingAttachments: snapshot.pendingAttachments,
        isUploading: false,
      );
      expect(
        controller.restoreSnapshot(snapshot, state: restoredState),
        isTrue,
      );
      expect(notifications, 3);
      expect(controller.value, same(restoredState));
      expect(controller.pendingAttachments, snapshot.pendingAttachments);
      expect(controller.pendingAttachments[0].budgetBytes, first.budgetBytes);
      expect(controller.pendingAttachments[1].durationMs, second.durationMs);

      expect(
        () => controller.pendingAttachments.add(first),
        throwsUnsupportedError,
      );
      expect(() => snapshot.pendingAttachments.clear(), throwsUnsupportedError);
    },
  );

  test('lane policy projection stays outside the shared controller', () {
    final attachment = pendingMedia(
      '/tmp/controller-policy.jpg',
      budgetBytes: 321,
    );
    final controller = ConversationComposerController();
    addTearDown(controller.dispose);

    final directProjection = projectedState(
      pendingAttachments: <PendingComposerMedia>[attachment],
      privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
    );
    controller.publish(
      state: directProjection,
      pendingAttachments: <PendingComposerMedia>[attachment],
    );
    expect(
      controller.value.privateMediaPolicy,
      const PrivateMediaPolicy.viewOnce(),
    );

    final ordinaryProjection = projectedState(
      pendingAttachments: <PendingComposerMedia>[attachment],
      privateMediaPolicy: const PrivateMediaPolicy.ordinary(),
    );
    controller.publish(state: ordinaryProjection);
    expect(
      controller.value.privateMediaPolicy,
      const PrivateMediaPolicy.ordinary(),
    );
  });
}
