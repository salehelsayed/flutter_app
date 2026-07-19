import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _config({
  String role = privateMediaOutboxSenderRole,
  int phase = 1,
}) => <String, dynamic>{
  'schema': privateMediaOutboxE2ERequestSchema,
  'transport_action': privateMediaOutboxE2EAction,
  'scenario': privateMediaOutboxE2EScenario,
  'role': role,
  'phase': phase,
  'runId': 'run-media-outbox-1',
  'nonce': 'nonce-media-outbox-1',
  'stepId': 'private-media-outbox-$role-$phase-run-media-outbox-1',
  'contactPeerId': 'contact-media-outbox-1',
  'messageId': 'a000000$phase',
  'attachmentId': 'attachment-media-outbox-$phase',
  'timeoutMs': 180000,
};

void main() {
  test('parses exact role phase and run-bound identity tuple', () {
    final sender = PrivateMediaOutboxE2ERequest.fromConfig(_config());
    expect(sender.isSender, isTrue);
    expect(sender.phase, 1);
    expect(sender.timeout, const Duration(minutes: 3));

    final receiver = PrivateMediaOutboxE2ERequest.fromConfig(
      _config(role: privateMediaOutboxReceiverRole, phase: 2),
    );
    expect(receiver.isSender, isFalse);
    expect(receiver.phase, 2);
    expect(receiver.messageId, 'a0000002');
    expect(receiver.attachmentId, 'attachment-media-outbox-2');
  });

  test('rejects stale schema action scenario role phase and step bindings', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value['schema'] = 'stale',
      (value) => value['transport_action'] = 'send_chat_message',
      (value) => value['scenario'] = 'android.other',
      (value) => value['role'] = 'primary',
      (value) => value['phase'] = 3,
      (value) => value['stepId'] = 'private-media-outbox-stale',
      (value) => value['nonce'] = '../unsafe',
      (value) => value['messageId'] = 'prefix-is-not-exact',
      (value) => value['attachmentId'] = 'attachment with space',
    ]) {
      final value = _config();
      mutation(value);
      expect(
        () => PrivateMediaOutboxE2ERequest.fromConfig(value),
        throwsFormatException,
      );
    }
  });

  test('controller delegates only to its current mounted endpoint', () async {
    final controller = PrivateMediaOutboxE2EController(enabled: true);
    final requests = <PrivateMediaOutboxE2ERequest>[];
    final progress = <Map<String, Object?>>[];
    var hostReleases = 0;
    final token = controller.registerEndpoint((
      request,
      writeProgress,
      waitForHostRelease,
    ) async {
      requests.add(request);
      await writeProgress(privateMediaOutboxE2EArmedReceipt(request));
      await waitForHostRelease(request);
      return privateMediaOutboxE2ECompletedReceipt(
        request,
        messageIdHash: privateMediaOutboxSafeHash(request.messageId),
        attachmentIdHash: privateMediaOutboxSafeHash(request.attachmentId),
        events: <Map<String, Object?>>[
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxNetworkRestoredEvent,
            timestampMs: 1,
          ),
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxLeaseClaimedEvent,
            source: privateMediaOutboxNetworkRestoredSource,
            timestampMs: 2,
          ),
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxEncryptionPreparedEvent,
            timestampMs: 3,
          ),
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxUploadStartEvent,
            timestampMs: 4,
          ),
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxSendSuccessEvent,
            timestampMs: 5,
          ),
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxReceivedEvent,
            timestampMs: 6,
          ),
        ],
      );
    });

    final result = await runPrivateMediaOutboxE2EAction(
      config: _config(),
      controller: controller,
      writeProgress: (value) async => progress.add(value),
      waitForHostRelease: (_) async => hostReleases++,
      installedProfileOverride: privateMediaOutboxE2EBuildProfile,
    );

    expect(requests, hasLength(1));
    expect(hostReleases, 1);
    expect(progress.single['status'], 'armed');
    expect(result['status'], 'complete');
    expect(result['success'], isTrue);
    expect(result['runCorrelationSha256'], hasLength(64));
    expect(result.toString(), isNot(contains('contact-media-outbox-1')));

    controller.unregisterEndpoint(Object());
    expect(controller.hasMountedEndpoint, isTrue);
    controller.unregisterEndpoint(token);
    expect(controller.hasMountedEndpoint, isFalse);
    expect(
      () => runPrivateMediaOutboxE2EAction(
        config: _config(),
        controller: controller,
        writeProgress: (_) async {},
        waitForHostRelease: (_) async {},
        installedProfileOverride: privateMediaOutboxE2EBuildProfile,
      ),
      throwsStateError,
    );
  });

  test('installed build profile is attested before endpoint dispatch', () {
    expect(
      () => requirePrivateMediaOutboxE2EBuildProfile(
        installedProfileId: privateMediaOutboxE2EBuildProfile,
      ),
      returnsNormally,
    );
    expect(
      () => requirePrivateMediaOutboxE2EBuildProfile(
        installedProfileId: 'android.e2e.standard',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('attested main-app APK'),
        ),
      ),
    );
  });

  test('queued progress and event evidence are exact and privacy safe', () {
    final request = PrivateMediaOutboxE2ERequest.fromConfig(_config(phase: 2));
    final queued = privateMediaOutboxE2EQueuedReceipt(request);
    final resumed = privateMediaOutboxE2EResumedQueuedReceipt(request);
    final claim = privateMediaOutboxE2EEventEvidence(
      request,
      event: privateMediaOutboxLeaseClaimedEvent,
      source: privateMediaOutboxNetworkRestoredSource,
      timestampMs: 42,
    );

    expect(queued['status'], 'queued');
    expect(queued['queuedNoRed'], isTrue);
    expect(queued['encryptionPreparedCount'], 1);
    expect(queued['uploadRequestCount'], 1);
    expect(resumed['status'], 'resumed_queued');
    expect(resumed['offlineResumeAttemptCount'], 0);
    expect(resumed['pauseResumeRemainedQueued'], isTrue);
    expect(claim.keys, <String>{
      'event',
      'runCorrelationSha256',
      'attachmentSha256',
      'timestampMs',
      'source',
    });
    expect(claim['source'], privateMediaOutboxNetworkRestoredSource);
    expect(claim.toString(), isNot(contains(request.attachmentId)));
    expect(
      () => privateMediaOutboxE2EEventEvidence(
        request,
        event: privateMediaOutboxUploadStartEvent,
        source: privateMediaOutboxNetworkRestoredSource,
        timestampMs: 43,
      ),
      throwsFormatException,
    );
  });

  test('disabled controller cannot expose a production conversation seam', () {
    final controller = PrivateMediaOutboxE2EController(enabled: false);
    expect(
      () => controller.registerEndpoint((_, _, _) async => <String, Object?>{}),
      throwsStateError,
    );
    expect(controller.hasMountedEndpoint, isFalse);
  });

  test(
    'endpoint readiness opens the exact contact and waits for mount',
    () async {
      final request = PrivateMediaOutboxE2ERequest.fromConfig(_config());
      final controller = PrivateMediaOutboxE2EController(enabled: true);
      final opened = <String>[];

      await ensurePrivateMediaOutboxE2EEndpoint(
        controller: controller,
        request: request,
        openConversationByPeerId: (peerId) async {
          opened.add(peerId);
          Future<void>.delayed(const Duration(milliseconds: 2), () {
            controller.registerEndpoint((_, _, _) async => <String, Object?>{});
          });
        },
        timeout: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(opened, <String>['contact-media-outbox-1']);
      expect(controller.hasMountedEndpoint, isTrue);
    },
  );

  test('host release is exact run-bound and hash-only', () {
    final request = PrivateMediaOutboxE2ERequest.fromConfig(_config());
    final release = privateMediaOutboxE2EHostRelease(request);

    expect(release['release'], privateMediaOutboxSenderOfflineRelease);
    expect(release['messageIdHash'], request.messageIdHash);
    expect(release['attachmentIdHash'], request.attachmentIdHash);
    expect(release.toString(), isNot(contains(request.messageId)));
    expect(release.toString(), isNot(contains(request.attachmentId)));
    expect(
      () => validatePrivateMediaOutboxE2EHostRelease(
        request,
        Map<String, dynamic>.from(release),
      ),
      returnsNormally,
    );

    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value['nonce'] = 'stale-nonce',
      (value) => value['phase'] = 2,
      (value) => value['messageIdHash'] = '0' * 64,
      (value) => value['extra'] = true,
    ]) {
      final changed = Map<String, dynamic>.from(release);
      mutation(changed);
      expect(
        () => validatePrivateMediaOutboxE2EHostRelease(request, changed),
        throwsFormatException,
      );
    }
  });

  test(
    'endpoint readiness fails closed without launcher or mounted route',
    () async {
      final request = PrivateMediaOutboxE2ERequest.fromConfig(_config());
      final controller = PrivateMediaOutboxE2EController(enabled: true);

      await expectLater(
        ensurePrivateMediaOutboxE2EEndpoint(
          controller: controller,
          request: request,
          openConversationByPeerId: null,
        ),
        throwsStateError,
      );
      await expectLater(
        ensurePrivateMediaOutboxE2EEndpoint(
          controller: controller,
          request: request,
          openConversationByPeerId: (_) async {},
          timeout: const Duration(milliseconds: 2),
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsStateError,
      );
    },
  );

  test('failure receipt exposes only safe bound hashes and error type', () {
    final receipt = privateMediaOutboxE2EFailureReceipt(
      config: _config(role: privateMediaOutboxReceiverRole, phase: 2),
      error: StateError('secret path peer key and media bytes'),
    );

    expect(receipt['schema'], privateMediaOutboxE2EEndpointResultSchema);
    expect(receipt['status'], 'failed');
    expect(receipt['success'], isFalse);
    expect(receipt['role'], privateMediaOutboxReceiverRole);
    expect(receipt['phase'], 2);
    expect(receipt['errorType'], 'StateError');
    expect(receipt.toString(), isNot(contains('secret path')));
    expect(receipt.toString(), isNot(contains('contact-media-outbox-1')));
  });
}
