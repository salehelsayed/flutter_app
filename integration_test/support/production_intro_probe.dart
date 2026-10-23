import 'dart:convert';
import 'dart:io';

import 'production_journey_peer.dart';

/// Reads the existing legacy-intro receipt through the owned production app.
/// Its generic preamble performs health/inbox work: this is not a passive
/// observation. Natural-delivery UI evidence must precede this probe whenever
/// a scenario claims automatic delivery or replay without a forced drain.
/// It submits no introductions, decisions, contacts or chat messages.
Future<Map<String, Object?>> readProductionIntroductionSnapshot(
  ProductionJourneyPeer peer, {
  required String expectedPeerId,
}) async {
  if (peer.isIosSimulator) throw StateError('this probe is Android-only');
  final current = await peer.command('identity');
  if (current['peerId'] != expectedPeerId) {
    throw StateError(
      'introduction probe identity does not match the bound invocation',
    );
  }
  final step =
      'catalog-intro-${peer.invocation.nonce}-${DateTime.now().microsecondsSinceEpoch}';
  await peer.writeAppFile('intro_e2e_config.json', {'stepId': step});
  final receipt = await waitForProductionObservation(
    'current existing introduction observation receipt',
    const Duration(minutes: 3),
    () async {
      // readAppFile() is scoped to production-journey/. The existing intro
      // protocol lives at this fixed documents-root filename instead.
      final result = await peer.adb([
        'exec-out',
        'run-as',
        peer.packageName,
        'cat',
        'app_flutter/intro_e2e_result.json',
      ], allowFailure: true);
      if (result.exitCode != 0) return null;
      Object? value;
      try {
        value = jsonDecode('${result.stdout}');
      } on FormatException {
        return null;
      }
      if (value is! Map ||
          value['stepId'] != step ||
          !{'complete', 'failed'}.contains(value['status'])) {
        return null;
      }
      final copied = Map<String, Object?>.from(value);
      await File(
        '${peer.output.path}/$step.json',
      ).writeAsString(jsonEncode(copied));
      if (value['success'] != true) {
        throw StateError(
          'existing introduction observation failed; retained exact current receipt',
        );
      }
      final snapshot = value['snapshot'];
      if (snapshot is! Map ||
          snapshot['identity'] is! Map ||
          (snapshot['identity'] as Map)['peerId'] != expectedPeerId) {
        throw StateError(
          'existing introduction snapshot belongs to the wrong account',
        );
      }
      return copied;
    },
  );
  return {
    ...receipt,
    'observedRunId': peer.invocation.runId,
    'observedNonce': peer.invocation.nonce,
    'observedRole': peer.invocation.role,
    'probePreambleDrainsInbox': true,
  };
}
