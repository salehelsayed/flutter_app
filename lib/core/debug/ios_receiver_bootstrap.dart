import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'ios_receiver_bootstrap_contract.dart';

const String _compiledSimsBuildProfile = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

const MethodChannel _iosReceiverBootstrapChannel = MethodChannel(
  'mknoon/sims_ios_receiver_bootstrap',
);

/// Publishes only the public libp2p transport identity to the native SIMS
/// handoff. The raw APNs token never crosses Flutter or a log/argument seam.
Future<void> publishIosReceiverBootstrapIdentityWhenReady({
  required String? Function() currentPeerId,
  required Stream<String?> peerIds,
  required Future<String?> Function() loadMlKemPublicKey,
  Duration timeout = iosReceiverBootstrapIdentityPublicationTimeout,
}) async {
  if (!Platform.isIOS ||
      !isIosReceiverBootstrapBuildProfile(_compiledSimsBuildProfile)) {
    return;
  }

  try {
    if (timeout <= Duration.zero) return;
    final deadline = DateTime.now().add(timeout);
    final current = currentPeerId()?.trim() ?? '';
    var peerDeviceId = current;
    if (!isIosReceiverBootstrapTransportPeerId(peerDeviceId)) {
      final peerBudget = deadline.difference(DateTime.now());
      if (peerBudget <= Duration.zero) return;
      peerDeviceId = await peerIds
          .map((value) => value?.trim() ?? '')
          .firstWhere(isIosReceiverBootstrapTransportPeerId)
          .timeout(peerBudget);
    }
    var mlKemPublicKey = '';
    while (DateTime.now().isBefore(deadline)) {
      final keyBudget = deadline.difference(DateTime.now());
      if (keyBudget <= Duration.zero) return;
      mlKemPublicKey =
          (await loadMlKemPublicKey().timeout(keyBudget))?.trim() ?? '';
      if (isIosReceiverBootstrapMlKemPublicKey(mlKemPublicKey)) {
        break;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      const pollInterval = Duration(milliseconds: 250);
      await Future<void>.delayed(
        remaining < pollInterval ? remaining : pollInterval,
      );
    }
    if (!isIosReceiverBootstrapMlKemPublicKey(mlKemPublicKey)) {
      return;
    }
    final publicationBudget = deadline.difference(DateTime.now());
    if (publicationBudget <= Duration.zero) return;
    await _iosReceiverBootstrapChannel
        .invokeMethod<void>('publishTransportPeerId', <String, String>{
          'peerDeviceId': peerDeviceId,
          'mlKemPublicKey': mlKemPublicKey,
        })
        .timeout(publicationBudget);
  } on PlatformException {
    // This test-only handoff is never load-bearing for production startup.
    // The host-side bootstrap times out with a redacted typed failure.
  } on MissingPluginException {
    // Normal builds intentionally do not install the native channel.
  } on TimeoutException {
    // The redacted host-side timeout remains the authoritative verdict.
  } on Object {
    // Never let a test-only handoff become load-bearing for app startup.
  }
}
