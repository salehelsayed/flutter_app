import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_sibling_device_prompt.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  final device = PendingSiblingDevice(
    groupId: 'g1',
    memberPeerId: 'bob',
    deviceId: 'bob-tablet',
    transportPeerId: 'bob-tablet',
    deviceSigningPublicKey: 'sign',
    mlKemPublicKey: 'mlkem',
    verifiedAccountSigningPublicKey: 'pk-bob',
    announcedAt: DateTime.utc(2026, 6, 17),
  );

  Future<void> pump(
    WidgetTester tester, {
    required VoidCallback onVerify,
    required VoidCallback onReject,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PendingSiblingDevicePrompt(
          view: PendingSiblingDeviceView(
            device: device,
            memberLabel: 'Bob',
            safetyNumber: '1234 5678 9012',
          ),
          onVerify: onVerify,
          onReject: onReject,
        ),
      ),
    ),
  );

  testWidgets('renders the member label + safety number', (tester) async {
    await pump(tester, onVerify: () {}, onReject: () {});
    expect(find.text('New device for Bob'), findsOneWidget);
    expect(find.text('1234 5678 9012'), findsOneWidget);
  });

  testWidgets('Verify and Reject fire their callbacks', (tester) async {
    var verified = false;
    var rejected = false;
    await pump(
      tester,
      onVerify: () => verified = true,
      onReject: () => rejected = true,
    );

    await tester.tap(find.byKey(const Key('pending-sibling-verify-g1:bob:bob-tablet')));
    expect(verified, isTrue);

    await tester.tap(find.byKey(const Key('pending-sibling-reject-g1:bob:bob-tablet')));
    expect(rejected, isTrue);
  });
}
