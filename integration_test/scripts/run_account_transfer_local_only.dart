import 'dart:io';

import 'contact_transfer_native_evidence.dart';

bool _privateLanAddress(String value) {
  final address = InternetAddress.tryParse(value);
  if (address == null || address.isLoopback) return false;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    return (bytes[0] & 0xfe) == 0xfc ||
        bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
  }
  return bytes[0] == 10 ||
      bytes[0] == 192 && bytes[1] == 168 ||
      bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31;
}

List<String> validateAccountTransferLocalOnlyObservations(
  ContactTransferNativeEvidence evidence,
) {
  final failures = <String>[];
  final row = evidence.observations;
  final window = (
    blocked: row['internetBlockedAtMs'] as int,
    discovery: row['discoveredAtMs'] as int,
    started: row['transferStartedAtMs'] as int,
    complete: row['transferCompletedAtMs'] as int,
    restored: row['internetRestoredAtMs'] as int,
  );
  if (!(window.blocked < window.discovery &&
      window.discovery <= window.started &&
      window.started < window.complete &&
      window.complete < window.restored)) {
    failures.add(
      'real local discovery and completed move must occur inside the measured internet-isolation window',
    );
  }
  if (row['transport'] != 'wifi_lan' ||
      row['discoverySource'] != 'local_discovery' ||
      !_privateLanAddress(row['oldLocalAddress'] as String) ||
      !_privateLanAddress(row['newLocalAddress'] as String) ||
      row['oldLocalAddress'] == row['newLocalAddress'] ||
      (row['transferredBytes'] as int) <= 0 ||
      row['manifestBytes'] != row['transferredBytes'] ||
      row['sourcePayloadSha256'] != row['importedPayloadSha256'] ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${row['sourcePayloadSha256']}')) {
    failures.add(
      'distinct non-loopback LAN endpoints must carry the exact complete manifest payload',
    );
  }
  final probes = journeyGapRows(row['internetProbes']);
  for (final side in ['old', 'new']) {
    final during = probes
        .where(
          (probe) =>
              probe['role'] == side &&
              (probe['atMs'] as int) >= window.blocked &&
              (probe['atMs'] as int) <= window.complete,
        )
        .toList();
    final after = probes
        .where(
          (probe) =>
              probe['role'] == side && (probe['atMs'] as int) > window.restored,
        )
        .toList();
    if (during.length < 2 ||
        during.any((probe) => probe['reachable'] != false) ||
        after.isEmpty ||
        !after.any((probe) => probe['reachable'] == true)) {
      failures.add(
        '$side: independently observed Internet failure during transfer and recovery afterward required',
      );
    }
  }
  if (row['relayBytesDuringTransfer'] != 0 ||
      row['newHistoryUsableBeforeInternet'] != true ||
      row['newActiveAfterCutover'] != true ||
      row['oldActiveAfterCutover'] != false ||
      row['ownedNetworkStateRestored'] != true) {
    failures.add(
      'local transfer must complete independently of relay recovery and restore only owned network state',
    );
  }
  return failures;
}

Future<void> main(List<String> arguments) async {
  final failures = <String>[];
  var evaluated = false;
  if (arguments.contains('--receipt')) {
    try {
      final evidence = await ContactTransferNativeEvidence.load(
        arguments,
        journeyId: 'TRANSFER-004',
        requiredKinds: [
          'network-isolation',
          'local-discovery',
          'transfer-stream',
          'native-cutover',
          'network-restoration',
        ],
      );
      evaluated = true;
      failures.addAll(validateAccountTransferLocalOnlyObservations(evidence));
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'TRANSFER-004 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'TRANSFER-004',
    ids: ['DC-019', 'TRANSFER-004'],
    captureGap:
        'Existing loopback bundle/runtime tests have no actual paired-device LAN '
        'discovery plus independently observed internet-isolation/traffic capture producer.',
    prerequisites: [
      'Future fapp pins available paired targets on a real local Wi-Fi network, exact candidate and owned reversible network changes.',
      'Retain independent external-connectivity/traffic evidence on both endpoints throughout transfer; private IP or a receipt boolean alone cannot establish isolation.',
      'Capture local discovery, complete payload bytes, usable import/cutover before Internet restoration, then observed connectivity recovery; no infrastructure changes here.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
