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
}
