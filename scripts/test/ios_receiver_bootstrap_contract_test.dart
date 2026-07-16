import 'dart:convert';

import 'package:flutter_app/core/debug/ios_receiver_bootstrap_contract.dart';

Never _fail(String message) => throw StateError(message);

void main() {
  if (!isIosReceiverBootstrapBuildProfile('ios.device.production')) {
    _fail('the exact SIMS physical-iOS profile must enable the handoff');
  }
  for (final profile in <String>['', 'ios.simulator.e2e', 'production']) {
    if (isIosReceiverBootstrapBuildProfile(profile)) {
      _fail('non-bootstrap profile was accepted: $profile');
    }
  }

  const peer = '12D3KooW123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijk';
  if (!isIosReceiverBootstrapTransportPeerId(peer)) {
    _fail('valid libp2p transport peer id was rejected');
  }
  for (final invalid in <String>[
    '00008110-001A123E0E91801E',
    'peer-device-placeholder',
    '$peer\nextra',
  ]) {
    if (isIosReceiverBootstrapTransportPeerId(invalid)) {
      _fail('invalid transport identity was accepted');
    }
  }

  final mlKem = base64.encode(List<int>.filled(1184, 0x41));
  if (!isIosReceiverBootstrapMlKemPublicKey(mlKem) ||
      isIosReceiverBootstrapMlKemPublicKey('short')) {
    _fail('ML-KEM public-key shape validation is not fail-closed');
  }

  for (final authorization in <String>[
    'authorized',
    'provisional',
    'ephemeral',
  ]) {
    if (!isIosReceiverBootstrapNotificationAuthorization(authorization)) {
      _fail('accepted notification authorization was rejected');
    }
  }
  for (final authorization in <String>['denied', 'not_determined', '']) {
    if (isIosReceiverBootstrapNotificationAuthorization(authorization)) {
      _fail('unsafe notification authorization was accepted');
    }
  }
  if (!isIosReceiverBootstrapNotificationAlertSetting('enabled') ||
      isIosReceiverBootstrapNotificationAlertSetting('disabled')) {
    _fail('notification alert setting validation is not fail-closed');
  }
}
