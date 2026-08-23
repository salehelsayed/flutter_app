import 'dart:convert';
import 'dart:io';

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

  final bootstrap = File(
    'integration_test/scripts/ios_receiver_bootstrap.py',
  ).readAsStringSync();
  final inventory = File(
    'ios/Runner/IosNotificationRecoveryCoordinator.swift',
  ).readAsStringSync();
  final handoff = File(
    'ios/Runner/IosReceiverBootstrapHandoff.swift',
  ).readAsStringSync();
  final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  for (final required in const <String>[
    'mknoon.sims.ios-group-notification-observation-request.v1',
    'mknoon.sims.ios-group-notification-observation-result.v1',
    'mknoon.sims.ios-group-notification-observation-host-receipt.v1',
    '"expectedGroupIdSha256": group_sha256',
    '"expectedEventIdSha256": event_sha256',
    '"expectedTargetMessageIdSha256": target_message_sha256',
    '"sampledThroughDeadline"',
    '"badSourceSeen"',
    '"duplicateSeen"',
    'control.terminate(',
    '"preTapCleanupLaunchCount": 0',
  ]) {
    if (!bootstrap.contains(required)) {
      _fail('group observation bootstrap contract is missing: $required');
    }
  }
  for (final required in const <String>[
    'static let stableSampleTarget = 3',
    'static let stableSampleIntervalMilliseconds = 500',
    'static let observationDeadlineMilliseconds = 8_000',
  ]) {
    if (!inventory.contains(required)) {
      _fail('native inventory timing contract is missing: $required');
    }
  }
  if (!handoff.contains('takeGroupNotificationObservationRequest()') ||
      !handoff.contains('completeGroupNotificationObservationRequest(') ||
      !appDelegate.contains('IosGroupNotificationFullHorizonSampler') ||
      !appDelegate.contains(
        'processPendingIosGroupNotificationObservation()',
      ) ||
      !appDelegate.contains(
        '// Intentionally do not release iosNotificationRecoveryProofInFlight.',
      )) {
    _fail('group observation fence and full-horizon sampler are incomplete');
  }
}
