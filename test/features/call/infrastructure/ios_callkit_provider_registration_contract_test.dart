import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-boundary checks only. These do not reproduce callservicesd or prove
/// that iOS delivers didActivate; the native lifecycle tests exercise the
/// controller with a deliberately stale provider-registration model.
void main() {
  final source = File(
    'ios/Runner/MknoonCallKitController.swift',
  ).readAsStringSync();

  test('every incoming report refreshes the existing provider first', () {
    final reports = RegExp(
      r'^\s*provider\.reportNewIncomingCall\(',
      multiLine: true,
    ).allMatches(source);
    expect(reports, isNotEmpty);
    for (final report in reports) {
      expect(
        source
            .substring(0, report.start)
            .trimRight()
            .endsWith('provider.refreshConfiguration()'),
        isTrue,
        reason:
            'A new CallKit report must register the current audio session '
            'before reporting, including mandatory duplicate/busy pushes.',
      );
    }
  });

  test(
    'outgoing start refreshes before requesting its CallKit transaction',
    () {
      final request = source.indexOf(
        'transactionRequester.request(CXTransaction(action: action))',
      );
      expect(request, greaterThanOrEqualTo(0));
      expect(
        source
            .substring(0, request)
            .trimRight()
            .endsWith('provider.refreshConfiguration()'),
        isTrue,
        reason:
            'Outgoing calls must register the current audio session before '
            'CallKit can perform their start action.',
      );
    },
  );

  test('refresh uses the configuration setter on the same provider', () {
    expect(
      RegExp(
        r'extension CXProvider: MknoonCallProviding\s*\{\s*'
        r'func refreshConfiguration\(\)\s*\{\s*'
        r'(?:\/\/[^\n]*\n\s*)*'
        r'let currentConfiguration = configuration\s*'
        r'configuration = currentConfiguration\s*\}',
      ).hasMatch(source),
      isTrue,
      reason:
          'Reassigning the existing configuration refreshes CallKit\'s '
          'audio-session registration without replacing its provider.',
    );
  });
}
