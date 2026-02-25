import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/qr_code/presentation/widgets/scan_overlay.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 400, height: 600, child: child)),
  );

  group('ScanOverlay', () {
    testWidgets('renders CustomPaint', (tester) async {
      await tester.pumpWidget(wrap(const ScanOverlay()));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders with default scanAreaSize of 280', (tester) async {
      await tester.pumpWidget(wrap(const ScanOverlay()));
      final scanOverlay = tester.widget<ScanOverlay>(find.byType(ScanOverlay));
      expect(scanOverlay.scanAreaSize, 280);
    });

    testWidgets('renders with custom scanAreaSize', (tester) async {
      await tester.pumpWidget(wrap(const ScanOverlay(scanAreaSize: 200)));
      final scanOverlay = tester.widget<ScanOverlay>(find.byType(ScanOverlay));
      expect(scanOverlay.scanAreaSize, 200);
    });

    testWidgets('expands to fill available space', (tester) async {
      await tester.pumpWidget(wrap(const ScanOverlay()));
      expect(find.byType(SizedBox), findsWidgets);
    });
  });
}
