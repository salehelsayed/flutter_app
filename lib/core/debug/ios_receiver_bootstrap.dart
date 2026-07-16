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
  Duration timeout = const Duration(minutes: 2),
}) async {
  if (!Platform.isIOS ||
      !isIosReceiverBootstrapBuildProfile(_compiledSimsBuildProfile)) {
    return;
  }

  try {
    final current = currentPeerId()?.trim() ?? '';
    final peerDeviceId = isIosReceiverBootstrapTransportPeerId(current)
        ? current
        : await peerIds
              .map((value) => value?.trim() ?? '')
              .firstWhere(isIosReceiverBootstrapTransportPeerId)
              .timeout(timeout);
    final deadline = DateTime.now().add(timeout);
    var mlKemPublicKey = '';
    while (DateTime.now().isBefore(deadline)) {
      mlKemPublicKey = (await loadMlKemPublicKey())?.trim() ?? '';
      if (isIosReceiverBootstrapMlKemPublicKey(mlKemPublicKey)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!isIosReceiverBootstrapMlKemPublicKey(mlKemPublicKey)) {
      return;
    }
    await _iosReceiverBootstrapChannel.invokeMethod<void>(
      'publishTransportPeerId',
      <String, String>{
        'peerDeviceId': peerDeviceId,
        'mlKemPublicKey': mlKemPublicKey,
      },
    );
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
