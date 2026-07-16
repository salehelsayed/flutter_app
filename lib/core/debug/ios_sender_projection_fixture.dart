import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'ios_receiver_bootstrap_contract.dart';
import 'ios_sender_projection_fixture_contract.dart';

const String _compiledSimsBuildProfile = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

const MethodChannel _channel = MethodChannel(
  'mknoon/sims_ios_receiver_bootstrap',
);

/// Polls the native, protected-file command seam for one exact sender seed or
/// cleanup request. All raw sender data stays in the app process and protected
/// container; method completion returns only action/status/digests.
Future<void> runIosSenderProjectionFixtureLoop({
  required IosSenderProjectionFixtureCoordinator coordinator,
  Duration lifetime = const Duration(minutes: 45),
  Duration pollInterval = const Duration(milliseconds: 250),
}) async {
  if (!Platform.isIOS ||
      !isIosReceiverBootstrapBuildProfile(_compiledSimsBuildProfile)) {
    return;
  }

  final deadline = DateTime.now().add(lifetime);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'takeSenderProjectionRequest',
      );
      if (raw == null) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      if (raw is! Map) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      final command = <String, Object?>{};
      for (final entry in raw.entries) {
        if (entry.key is! String) {
          command.clear();
          break;
        }
        command[entry.key as String] = entry.value;
      }
      final request = IosSenderProjectionRequest.tryParse(
        command,
        now: DateTime.now().toUtc(),
      );
      if (request == null) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      final outcome = await coordinator.execute(request);
      await _channel.invokeMethod<void>(
        'completeSenderProjectionRequest',
        <String, String>{
          'captureNonce': request.captureNonce,
          'action': request.action,
          'apnsPayloadSha256': request.apnsPayloadSha256,
          'fixtureDigest': request.fixtureDigest,
          'status': outcome.status,
          'resultCode': outcome.resultCode,
        },
      );
    } on MissingPluginException {
      await Future<void>.delayed(pollInterval);
    } on PlatformException {
      await Future<void>.delayed(pollInterval);
    } on Object {
      await Future<void>.delayed(pollInterval);
    }
  }
}
