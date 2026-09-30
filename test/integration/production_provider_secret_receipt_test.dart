import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';

import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_journey_peer.dart';

final class _ProviderReplyRunner implements AndroidHostProcessRunner {
  _ProviderReplyRunner(this.invocation, this.token);
  final SimsRuntimeInvocation invocation;
  final String? token;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(executable, 'adb');
    calls.add(arguments);
    if (arguments.contains('cat') &&
        arguments.contains(
          'app_flutter/production-journey/command-result.json',
        )) {
      return ProcessResult(
        0,
        0,
        jsonEncode({
          'invocation': invocation.toJson(),
          'sequence': 1,
          'operation': 'provider_token',
          'ok': true,
          'result': {'token': token},
        }),
        '',
      );
    }
    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  const invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.production_fcm.journey',
    scenarioId: notificationOpenJourney,
    role: 'bob',
    runId: 'secret-run',
    nonce: 'secret-nonce',
    values: {},
  );
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('secret-receipt-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  for (final token in ['real-secret-token', null]) {
    test(
      'provider token ${token == null ? 'failure' : 'success'} leaves no host receipt',
      () async {
        final runner = _ProviderReplyRunner(invocation, token);
        final peer = ProductionJourneyPeer(
          'emulator-5556',
          invocation,
          directory,
          runner,
          packageName: 'com.mknoon.app',
        );
        if (token == null) {
          await expectLater(peer.claimProviderToken(), throwsStateError);
        } else {
          expect(await peer.claimProviderToken(), token);
        }
        expect(
          directory
              .listSync(recursive: true)
              .whereType<File>()
              .any((file) => file.path.contains('provider_token')),
          isFalse,
        );
        expect(
          runner.calls.last,
          containsAll([
            'run-as',
            'com.mknoon.app',
            'rm',
            '-f',
            'app_flutter/production-journey/command-result.json',
          ]),
        );
        final staging = directory.listSync().whereType<File>().toList();
        expect(
          staging.every(
            (file) => !file.readAsStringSync().contains('real-secret-token'),
          ),
          isTrue,
        );
      },
    );
  }
}
