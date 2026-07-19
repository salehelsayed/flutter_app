import 'dart:io';

import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e_conversation.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

PrivateMediaOutboxE2ERequest _request() =>
    PrivateMediaOutboxE2ERequest.fromConfig(<String, dynamic>{
      'schema': privateMediaOutboxE2ERequestSchema,
      'transport_action': privateMediaOutboxE2EAction,
      'scenario': privateMediaOutboxE2EScenario,
      'role': privateMediaOutboxSenderRole,
      'phase': 2,
      'runId': 'run-media-outbox-capture',
      'nonce': 'nonce-media-outbox-capture',
      'stepId': 'private-media-outbox-sender-2-run-media-outbox-capture',
      'contactPeerId': 'contact-media-outbox-capture',
      'messageId': 'feedbeef',
      'attachmentId': 'attachment-media-outbox-capture',
      'timeoutMs': 60000,
    });

void main() {
  late bool oldFlowLogging;

  setUp(() {
    oldFlowLogging = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
  });

  tearDown(() {
    setE2EFlowEventSink(null);
    flowEventLoggingEnabled = oldFlowLogging;
  });

  test(
    'capture separates initial issuance from exact restored causal window',
    () async {
      final request = _request();
      final capture = PrivateMediaOutboxE2EFlowCapture(request)..start();

      _emitUploadMilestone(request, privateMediaOutboxEncryptionPreparedEvent);
      _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
      expect(capture.initialEncryptionPreparedCount, 1);
      expect(capture.initialUploadRequestCount, 1);

      capture.markQueued();
      _emit(privateMediaOutboxNetworkRestoredEvent);
      _emit(
        privateMediaOutboxLeaseClaimedEvent,
        details: <String, dynamic>{
          'source': privateMediaOutboxNetworkRestoredSource,
          'attachmentSha256': request.attachmentIdHash,
        },
      );
      _emitUploadMilestone(request, privateMediaOutboxEncryptionPreparedEvent);
      _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
      _emit(
        privateMediaOutboxSendSuccessEvent,
        details: <String, dynamic>{'id': request.messageId},
      );

      await capture.waitForRestoredDeliverySignal();
      final events = await capture.sealAfterQuietPeriod(Duration.zero);
      expect(events.map((event) => event['event']), <String>[
        privateMediaOutboxNetworkRestoredEvent,
        privateMediaOutboxLeaseClaimedEvent,
        privateMediaOutboxEncryptionPreparedEvent,
        privateMediaOutboxUploadStartEvent,
        privateMediaOutboxSendSuccessEvent,
      ]);
      expect(capture.offlineResumeAttemptCount, 0);
      expect(events[1]['source'], privateMediaOutboxNetworkRestoredSource);
      expect(events[1]['attachmentSha256'], request.attachmentIdHash);
      expect(events.toString(), isNot(contains(request.attachmentId)));
      capture.dispose();
    },
  );

  test(
    'capture preserves an illegal pre-restore attempt for host rejection',
    () async {
      final request = _request();
      final capture = PrivateMediaOutboxE2EFlowCapture(request)..start();
      capture.markQueued();

      _emitUploadMilestone(request, privateMediaOutboxEncryptionPreparedEvent);
      _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
      _emit(privateMediaOutboxNetworkRestoredEvent);
      _emit(
        privateMediaOutboxLeaseClaimedEvent,
        details: <String, dynamic>{
          'source': privateMediaOutboxNetworkRestoredSource,
          'attachmentSha256': request.attachmentIdHash,
        },
      );
      _emitUploadMilestone(request, privateMediaOutboxEncryptionPreparedEvent);
      _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
      _emit(
        privateMediaOutboxSendSuccessEvent,
        details: <String, dynamic>{'id': request.messageId},
      );

      await capture.waitForRestoredDeliverySignal();
      await expectLater(
        capture.sealAfterQuietPeriod(Duration.zero),
        throwsStateError,
      );
      expect(capture.offlineResumeAttemptCount, 2);
      capture.dispose();
    },
  );

  test(
    'capture ignores concurrent milestones for another attachment',
    () async {
      final request = _request();
      final capture = PrivateMediaOutboxE2EFlowCapture(request)..start();
      capture.markQueued();
      final completion = capture.waitForRestoredDeliverySignal();
      _emit(privateMediaOutboxNetworkRestoredEvent);
      _emit(
        privateMediaOutboxLeaseClaimedEvent,
        details: <String, dynamic>{
          'source': privateMediaOutboxNetworkRestoredSource,
          'attachmentSha256': '0' * 64,
        },
      );
      _emit(
        privateMediaOutboxEncryptionPreparedEvent,
        details: <String, dynamic>{'attachmentSha256': '0' * 64},
      );
      _emit(
        privateMediaOutboxUploadStartEvent,
        details: <String, dynamic>{'attachmentSha256': '0' * 64},
      );
      _emit(
        privateMediaOutboxSendSuccessEvent,
        details: const <String, dynamic>{'id': 'other-id'},
      );
      _emit(
        privateMediaOutboxLeaseClaimedEvent,
        details: <String, dynamic>{
          'source': privateMediaOutboxNetworkRestoredSource,
          'attachmentSha256': request.attachmentIdHash,
        },
      );
      _emitUploadMilestone(request, privateMediaOutboxEncryptionPreparedEvent);
      _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
      _emit(
        privateMediaOutboxSendSuccessEvent,
        details: <String, dynamic>{'id': request.messageId},
      );

      await completion;
      final events = await capture.sealAfterQuietPeriod(Duration.zero);
      expect(events, hasLength(5));
      expect(events.toString(), isNot(contains('00000000')));
      capture.dispose();
    },
  );

  test(
    'capture rejects a second correlated envelope after first success',
    () async {
      final request = _request();
      final capture = PrivateMediaOutboxE2EFlowCapture(request)..start();
      capture.markQueued();

      _emit(privateMediaOutboxNetworkRestoredEvent);
      _emit(
        privateMediaOutboxLeaseClaimedEvent,
        details: <String, dynamic>{
          'source': privateMediaOutboxNetworkRestoredSource,
          'attachmentSha256': request.attachmentIdHash,
        },
      );
      _emitUploadMilestone(request, privateMediaOutboxEncryptionPreparedEvent);
      _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
      _emit(
        privateMediaOutboxSendSuccessEvent,
        details: <String, dynamic>{'id': request.messageId},
      );
      await capture.waitForRestoredDeliverySignal();

      _emit(
        privateMediaOutboxSendSuccessEvent,
        details: <String, dynamic>{'id': request.messageId},
      );

      await expectLater(
        capture.sealAfterQuietPeriod(Duration.zero),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('exactly once'),
          ),
        ),
      );
      capture.dispose();
    },
  );

  test('capture restores the prior E2E flow observer on dispose', () {
    final priorEvents = <String>[];
    setE2EFlowEventSink((payload) {
      priorEvents.add(payload['event']! as String);
    });
    final capture = PrivateMediaOutboxE2EFlowCapture(_request())..start();
    _emit('WHILE_CAPTURED');
    expect(priorEvents, isEmpty);

    capture.dispose();
    _emit('AFTER_CAPTURE');
    expect(priorEvents, <String>['AFTER_CAPTURE']);
  });

  test(
    'conversation endpoint proves queued resume and restored delivery',
    () async {
      final request = _request();
      final progress = <String>[];
      var sendCalls = 0;
      var hostReleaseWaits = 0;
      var offlineObservationWaits = 0;
      var resumeWaits = 0;
      final senderOrder = <String>[];
      final endpoint = PrivateMediaOutboxE2EConversationEndpoint(
        contactPeerId: request.contactPeerId,
        sendPrivateMedia: (_) async {
          senderOrder.add('send');
          sendCalls++;
          _emitUploadMilestone(
            request,
            privateMediaOutboxEncryptionPreparedEvent,
          );
          _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
        },
        isSenderQueued: (_) async => true,
        isSenderDelivered: (_) async => true,
        isReceiverDelivered: (_) async => false,
        waitForSenderHostRelease: () async {
          senderOrder.add('host-release');
          hostReleaseWaits++;
          expect(progress, <String>['armed']);
        },
        waitForSenderOfflineObservation: () async {
          senderOrder.add('offline-observed');
          offlineObservationWaits++;
        },
        waitForOfflinePauseResume: () async => resumeWaits++,
        pollInterval: Duration.zero,
        deliveryQuietPeriod: Duration.zero,
      );

      final completed = await endpoint.run(request, (receipt) async {
        final status = receipt['status']! as String;
        progress.add(status);
        if (status == 'resumed_queued') {
          _emit(privateMediaOutboxNetworkRestoredEvent);
          _emit(
            privateMediaOutboxLeaseClaimedEvent,
            details: <String, dynamic>{
              'source': privateMediaOutboxNetworkRestoredSource,
              'attachmentSha256': request.attachmentIdHash,
            },
          );
          _emitUploadMilestone(
            request,
            privateMediaOutboxEncryptionPreparedEvent,
          );
          _emitUploadMilestone(request, privateMediaOutboxUploadStartEvent);
          _emit(
            privateMediaOutboxSendSuccessEvent,
            details: <String, dynamic>{'id': request.messageId},
          );
        }
      });

      expect(sendCalls, 1);
      expect(hostReleaseWaits, 1);
      expect(offlineObservationWaits, 1);
      expect(senderOrder, <String>['host-release', 'offline-observed', 'send']);
      expect(resumeWaits, 1);
      expect(progress, <String>['armed', 'queued', 'resumed_queued']);
      expect(completed['status'], 'complete');
      expect(completed['events'], isA<List<Map<String, Object?>>>());
      expect(completed['events']! as List<Object?>, hasLength(5));
    },
  );

  test('receiver endpoint waits for exact persisted incoming media', () async {
    final sender = _request();
    final request = PrivateMediaOutboxE2ERequest.fromConfig(<String, dynamic>{
      'schema': privateMediaOutboxE2ERequestSchema,
      'transport_action': privateMediaOutboxE2EAction,
      'scenario': privateMediaOutboxE2EScenario,
      'role': privateMediaOutboxReceiverRole,
      'phase': sender.phase,
      'runId': sender.runId,
      'nonce': sender.nonce,
      'stepId': 'private-media-outbox-receiver-${sender.phase}-${sender.runId}',
      'contactPeerId': sender.contactPeerId,
      'messageId': sender.messageId,
      'attachmentId': sender.attachmentId,
      'timeoutMs': 60000,
    });
    var receiverChecks = 0;
    final endpoint = PrivateMediaOutboxE2EConversationEndpoint(
      contactPeerId: request.contactPeerId,
      sendPrivateMedia: (_) async => fail('receiver must not send'),
      isSenderQueued: (_) async => false,
      isSenderDelivered: (_) async => false,
      isReceiverDelivered: (_) async => ++receiverChecks >= 2,
      waitForSenderHostRelease: () async => fail('receiver must not release'),
      waitForSenderOfflineObservation: () async =>
          fail('receiver must not observe sender connectivity'),
      waitForOfflinePauseResume: () async => fail('receiver must not resume'),
      pollInterval: Duration.zero,
      nowMilliseconds: () => 77,
    );
    final progress = <String>[];

    final completed = await endpoint.run(
      request,
      (receipt) async => progress.add(receipt['status']! as String),
    );

    expect(progress, <String>['armed']);
    expect(receiverChecks, 2);
    final events = completed['events']! as List<Object?>;
    expect(events, hasLength(1));
    expect(
      (events.single! as Map<Object?, Object?>)['event'],
      privateMediaOutboxReceivedEvent,
    );
    expect((events.single! as Map<Object?, Object?>)['timestampMs'], 77);
  });

  test(
    'source fixture is a valid app-owned JPEG with a hash-only filename',
    () async {
      final root = await Directory.systemTemp.createTemp('plan260-outbox-');
      addTearDown(() => root.delete(recursive: true));
      final request = _request();
      final source = await createPrivateMediaOutboxE2ESource(
        mediaFileManager: _RootedMediaFileManager(root.path),
        request: request,
      );

      expect(await source.exists(), isTrue);
      final bytes = await source.readAsBytes();
      expect(bytes.take(3), <int>[0xff, 0xd8, 0xff]);
      expect(bytes.sublist(bytes.length - 2), <int>[0xff, 0xd9]);
      expect(source.path, endsWith('.jpg'));
      expect(source.path, contains(request.runCorrelationSha256));
      expect(source.path, isNot(contains(request.attachmentId)));
    },
  );
}

void _emit(String event, {Map<String, dynamic> details = const {}}) {
  emitFlowEvent(layer: 'FL', event: event, details: details);
}

void _emitUploadMilestone(PrivateMediaOutboxE2ERequest request, String event) {
  _emit(
    event,
    details: <String, dynamic>{'attachmentSha256': request.attachmentIdHash},
  );
}

final class _RootedMediaFileManager extends MediaFileManager {
  _RootedMediaFileManager(this.root);

  final String root;

  @override
  Future<String> trustedMediaRootPath() async => root;
}
