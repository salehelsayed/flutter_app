import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/qr_action_cards.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('QRActionCards', () {
    testWidgets('renders two action cards in a Row', (tester) async {
      await tester.pumpWidget(wrap(QRActionCards(
        onMyQR: () {},
        onScanQR: () {},
      )));
      expect(find.byType(Row), findsWidgets);
      expect(find.byType(Expanded), findsNWidgets(2));
    });

    testWidgets('renders qr_code and camera_alt_outlined icons', (tester) async {
      await tester.pumpWidget(wrap(QRActionCards(
        onMyQR: () {},
        onScanQR: () {},
      )));
      expect(find.byIcon(Icons.qr_code), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    });

    testWidgets('calls onMyQR when first card tapped', (tester) async {
      var myQRTapped = false;
      await tester.pumpWidget(wrap(QRActionCards(
        onMyQR: () => myQRTapped = true,
        onScanQR: () {},
      )));
      await tester.tap(find.text('My QR Code'));
      expect(myQRTapped, isTrue);
    });

    testWidgets('calls onScanQR when second card tapped', (tester) async {
      var scanQRTapped = false;
      await tester.pumpWidget(wrap(QRActionCards(
        onMyQR: () {},
        onScanQR: () => scanQRTapped = true,
      )));
      await tester.tap(find.text('Scan QR Code'));
      expect(scanQRTapped, isTrue);
    });

    testWidgets('renders title and subtitle text for each card', (tester) async {
      await tester.pumpWidget(wrap(QRActionCards(
        onMyQR: () {},
        onScanQR: () {},
      )));
      expect(find.text('My QR Code'), findsOneWidget);
      expect(find.text('Share to add friends'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.text('Add a friend instantly'), findsOneWidget);
    });
  });
}
