import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private-media outbox dispatch precedes generic health and drain', () {
    final source = File(
      'lib/core/debug/intro_e2e_runner.dart',
    ).readAsStringSync();
    final poller = source.indexOf('void startIntroE2EPoller');
    final branch = source.indexOf(
      "config['transport_action'] == privateMediaOutboxE2EAction",
      poller,
    );
    final ensureMounted = source.indexOf(
      'ensurePrivateMediaOutboxE2EEndpoint(',
      branch,
    );
    final requireProfile = source.indexOf(
      'requirePrivateMediaOutboxE2EBuildProfile();',
      branch,
    );
    final consumeConfig = source.indexOf(
      'await _deleteConfigIfPresent();',
      branch,
    );
    final action = source.indexOf('await controller.run(', ensureMounted);
    final nextBranch = source.indexOf(
      "if (isGroupReactionE2EProbeAction(config['transport_action']))",
      action,
    );
    final generic = source.indexOf('await runIntroE2EActions(', poller);

    expect(poller, greaterThanOrEqualTo(0));
    expect(branch, greaterThan(poller));
    expect(consumeConfig, greaterThan(branch));
    expect(consumeConfig, lessThan(requireProfile));
    expect(requireProfile, greaterThan(branch));
    expect(requireProfile, lessThan(ensureMounted));
    expect(ensureMounted, greaterThan(branch));
    expect(action, greaterThan(branch));
    expect(action, greaterThan(ensureMounted));
    expect(action, lessThan(generic));
    expect(
      source.substring(action, nextBranch),
      contains('_waitForPrivateMediaOutboxE2EHostRelease'),
    );
    expect(
      source.substring(branch, action),
      contains('openConversationByPeerId: openConversationByPeerId'),
    );
    expect(
      source.substring(branch, nextBranch),
      isNot(contains('performImmediateHealthCheck')),
    );
    expect(
      source.substring(branch, nextBranch),
      isNot(contains('drainOfflineInbox')),
    );
    expect(
      RegExp(
        r'await _deleteConfigIfPresent\(\);',
      ).allMatches(source.substring(branch, nextBranch)),
      hasLength(1),
      reason: 'the consumed phase must not delete the next staged request',
    );
  });

  test('private-media sender is stably offline before host release', () {
    final source = File(
      'integration_test/scripts/'
      'run_connectivity_restore_media_outbox_sims.dart',
    ).readAsStringSync();
    final runPhase = source.indexOf('Future<Map<String, Object?>> _runPhase(');
    final isolate = source.indexOf(
      'await _setNetworkAvailable(physical, false);',
      runPhase,
    );
    final dwell = source.indexOf(
      'await Future<void>.delayed(_offlineObservationDwell);',
      isolate,
    );
    final recheck = source.indexOf(
      'if (await _networkAvailable(physical))',
      dwell,
    );
    final release = source.indexOf(
      'await _releasePrivateMediaSender(physical, senderRequest);',
      dwell,
    );

    expect(runPhase, greaterThanOrEqualTo(0));
    expect(isolate, greaterThan(runPhase));
    expect(dwell, greaterThan(isolate));
    expect(recheck, greaterThan(dwell));
    expect(release, greaterThan(recheck));
    expect(
      source,
      contains(
        'const Duration _offlineObservationDwell = Duration(seconds: 2)',
      ),
    );
  });

  test('sender completion permits acknowledged envelope cleanup', () {
    final source = File(
      'lib/features/conversation/presentation/screens/'
      'conversation_wired.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<bool> _isPrivateMediaOutboxE2ESenderDelivered(',
    );
    final end = source.indexOf(
      'Future<bool> _isPrivateMediaOutboxE2EReceiverDelivered(',
      start,
    );
    final predicate = source.substring(start, end);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(predicate, contains("parent.status == 'sending'"));
    expect(predicate, contains("attachment.downloadStatus != 'done'"));
    expect(
      predicate,
      isNot(contains('wireEnvelope')),
      reason:
          'acknowledged delivery may clear retry-only envelope persistence; '
          'the flow capture separately proves one exact wire send',
    );
  });
}
