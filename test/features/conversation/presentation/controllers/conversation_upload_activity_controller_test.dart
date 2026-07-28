import 'dart:async';

import 'package:flutter_app/shared/widgets/conversation/conversation_upload_activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversationUploadActivityController', () {
    test(
      'scopes monotonic progress and publishes once per accepted event',
      () async {
        var owners = <String, String>{'blob-1': 'message-1'};
        var acquireCount = 0;
        var releaseCount = 0;
        final controller = ConversationUploadActivityController<String>(
          scopeId: 'peer-a',
          resolveActiveOwners: () => owners,
          acquireWake: () async => acquireCount++,
          releaseWake: () async => releaseCount++,
        );
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);

        final operation = controller.beginOperation(
          messageId: 'message-1',
          composerSnapshot: 'draft-a',
        );
        await controller.startTracking(operation, totalBytes: 100);
        controller.markUploadStarted(operation, 'blob-1');
        notifications = 0;

        controller.applyProgress({
          'id': 'blob-1',
          'toPeerId': 'peer-b',
          'sentBytes': 30,
          'totalBytes': 100,
        });
        controller.applyProgress({
          'id': 'unknown',
          'toPeerId': 'peer-a',
          'sentBytes': 30,
          'totalBytes': 100,
        });
        expect(notifications, 0);

        controller.applyProgress({
          'id': 'blob-1',
          'toPeerId': 'peer-a',
          'sentBytes': 40,
          'totalBytes': 100,
        });
        expect(notifications, 1);
        expect(controller.aggregateProgress?.sentBytes, 40);
        expect(controller.messageProgress['message-1']?.sentBytes, 40);

        controller.applyProgress({
          'id': 'blob-1',
          'toPeerId': 'peer-a',
          'sentBytes': 40,
          'totalBytes': 100,
        });
        controller.applyProgress({
          'id': 'blob-1',
          'toPeerId': 'peer-a',
          'sentBytes': 20,
          'totalBytes': 100,
        });
        expect(notifications, 1);

        owners = <String, String>{};
        controller.applyProgress({
          'id': 'unknown',
          'toPeerId': 'peer-a',
          'sentBytes': 50,
        });
        expect(notifications, 2);
        expect(controller.messageProgress, isEmpty);
        expect(acquireCount, 1);
        expect(releaseCount, 0);

        await controller.complete(operation);
        expect(releaseCount, 1);
      },
    );

    test(
      'detaching a view suppresses UI without releasing the operation wake hold',
      () async {
        var releaseCount = 0;
        final controller = ConversationUploadActivityController<String>(
          scopeId: 'group-a',
          resolveActiveOwners: () => const {'blob-a': 'message-a'},
          acquireWake: () async {},
          releaseWake: () async => releaseCount++,
        );
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);

        final oldOperation = controller.beginOperation(
          messageId: 'message-a',
          composerSnapshot: 'old-draft',
        );
        await controller.startTracking(oldOperation, totalBytes: 100);
        controller.detachView();
        final afterDetach = notifications;

        controller.applyProgress({
          'id': 'blob-a',
          'toPeerId': 'group-a',
          'sentBytes': 75,
          'totalBytes': 100,
        });
        expect(notifications, afterDetach);
        expect(releaseCount, 0);

        controller.rebind(
          scopeId: 'group-b',
          resolveActiveOwners: () => const {'blob-b': 'message-b'},
        );
        final newOperation = controller.beginOperation(
          messageId: 'message-b',
          composerSnapshot: 'new-draft',
        );
        await controller.startTracking(newOperation, totalBytes: 50);
        controller.markUploadStarted(newOperation, 'blob-b');
        expect(controller.activeOperation, same(newOperation));

        await controller.complete(oldOperation);
        expect(releaseCount, 1);
        expect(controller.activeOperation, same(newOperation));
        expect(controller.isTracking, isTrue);

        await controller.complete(newOperation);
        expect(releaseCount, 2);
      },
    );

    test(
      'cancel and terminal completion finalize and release the exact operation once',
      () async {
        var finalizerCount = 0;
        var releaseCount = 0;
        final controller = ConversationUploadActivityController<String>(
          scopeId: 'peer-a',
          resolveActiveOwners: () => const {'blob-1': 'message-1'},
          acquireWake: () async {},
          releaseWake: () async => releaseCount++,
        );
        addTearDown(controller.dispose);

        late final ConversationUploadOperation<String> operation;
        operation = controller.beginOperation(
          messageId: 'message-1',
          composerSnapshot: 'exact-snapshot',
          cancelFinalizer: (captured) async {
            finalizerCount++;
            expect(captured, same(operation));
            expect(captured.scopeId, 'peer-a');
            expect(captured.composerSnapshot, 'exact-snapshot');
            return true;
          },
        );
        await controller.startTracking(operation, totalBytes: 100);
        expect(controller.requestCancelActive(), isTrue);
        expect(controller.requestCancelActive(), isFalse);

        expect(await controller.finalizeCancellation(operation), isTrue);
        expect(await controller.finalizeCancellation(operation), isTrue);
        await controller.complete(operation);

        expect(finalizerCount, 1);
        expect(releaseCount, 1);
        expect(controller.activeOperation, isNull);
        expect(controller.isTracking, isFalse);
      },
    );

    test('owns and cancels the bound progress subscription', () async {
      final progress = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(progress.close);
      var ownerResolutionCount = 0;
      final controller = ConversationUploadActivityController<void>(
        scopeId: 'peer-a',
        resolveActiveOwners: () {
          ownerResolutionCount++;
          return const <String, String>{};
        },
        acquireWake: () async {},
        releaseWake: () async {},
      );
      controller.bindProgressStream(progress.stream);

      progress.add({'id': 'unknown', 'toPeerId': 'peer-a', 'sentBytes': 1});
      await Future<void>.delayed(Duration.zero);
      expect(ownerResolutionCount, 1);

      controller.dispose();
      progress.add({'id': 'unknown', 'toPeerId': 'peer-a', 'sentBytes': 2});
      await Future<void>.delayed(Duration.zero);
      expect(ownerResolutionCount, 1);
    });
  });
}
