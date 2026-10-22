import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Native camera/permission is a platform-interface fake. This checks the real
// scanner route/controller's admission callback, not contact persistence or OS
// Settings. The complete contact/Orbit route remains UI-Update-owned.
void main() {
  for (final denied in [false, true]) {
    testWidgets(
      'CONTACT-001 ${denied ? 'denied' : 'cancelled'} camera admits no code; '
      'grant and reopen admits a fresh code once',
      (tester) async {
        final previous = MobileScannerPlatform.instance;
        final camera = _CameraPlatform()..granted = !denied;
        MobileScannerPlatform.instance = camera;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.runAsync(camera.frames.close);
          MobileScannerPlatform.instance = previous;
        });
        final admissions = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          QRScannerScreen(onScanned: admissions.add),
                    ),
                  ),
                  child: const Text('Open camera'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open camera'));
        await tester.pumpAndSettle();
        expect(camera.starts, 1);
        final scanner = tester.widget<MobileScanner>(
          find.byType(MobileScanner),
        );
        if (denied) {
          expect(
            scanner.controller!.value.error?.errorCode,
            MobileScannerErrorCode.permissionDenied,
          );
          expect(scanner.controller!.value.isRunning, isFalse);
        }
        expect(
          admissions,
          isEmpty,
          reason: 'cancel/denial cannot enter the downstream contact handler',
        );
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.text('Open camera'), findsOneWidget);
        expect(admissions, isEmpty);

        camera.granted = true;
        await tester.tap(find.text('Open camera'));
        await tester.pumpAndSettle();
        expect(camera.starts, 2);
        expect(
          tester
              .widget<MobileScanner>(find.byType(MobileScanner))
              .controller!
              .value
              .isRunning,
          isTrue,
        );
        final capture = BarcodeCapture(
          barcodes: const [
            Barcode(
              rawValue: 'fresh-synthetic-code',
              format: BarcodeFormat.qrCode,
            ),
          ],
        );
        camera.frames.add(capture);
        camera.frames.add(capture);
        await tester.pumpAndSettle();
        expect(admissions, ['fresh-synthetic-code']);
        expect(find.text('Open camera'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _CameraPlatform extends MobileScannerPlatform {
  bool granted = false;
  int starts = 0;
  final frames = StreamController<BarcodeCapture?>.broadcast(sync: true);

  @override
  Stream<BarcodeCapture?> get barcodesStream => frames.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox(width: 640, height: 480);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (!granted) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return MobileScannerViewAttributes(
      cameraDirection: options.cameraDirection,
      currentTorchMode: TorchState.off,
      size: const Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
}
