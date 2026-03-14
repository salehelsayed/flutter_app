import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flutter_app/features/home/presentation/widgets/qr_code_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows shimmer placeholder when qrData is null', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const QRCodeSection(qrData: null)));

    expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('shimmer keeps animating past the initial pulse duration', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const QRCodeSection(qrData: null)));

    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('shows QR image when qrData is provided', (tester) async {
    await tester.pumpWidget(wrap(const QRCodeSection(qrData: 'mknoon://qr')));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsNothing);
  });
}
