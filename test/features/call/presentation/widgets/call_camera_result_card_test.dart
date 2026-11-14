import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_camera_result_card.dart';
import 'package:flutter_test/flutter_test.dart';

// Owner-approved screen 14 copy; product localization remains a separate binding.
const _title = 'Camera access is off';
const _unavailable = 'Camera unavailable';
const _explanation = 'Allow camera access in Settings to turn on your video.';
const _hearing = 'Layla can still hear you.';

Future<void> _pump(
  WidgetTester tester, {
  CallCameraResultCardKind kind = CallCameraResultCardKind.permissionDenied,
  bool audible = false,
  VoidCallback? settings,
  VoidCallback? dismiss,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  double width = 600,
  double height = 600,
  String title = _title,
  String explanation = _explanation,
  String settingsLabel = 'Open Settings',
  String dismissLabel = 'Not now',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: direction,
                child: CallCameraResultCard(
                  kind: kind,
                  title: title,
                  dismissLabel: dismissLabel,
                  onDismiss: dismiss ?? () {},
                  permissionExplanation: explanation,
                  hearingExplanation: _hearing,
                  audioAudible: audible,
                  settingsLabel: settingsLabel,
                  onOpenSettings: settings,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'VUI4 permission card invokes only explicit settings and dismissal',
    (tester) async {
      var settings = 0;
      var dismissed = 0;
      await _pump(
        tester,
        audible: true,
        settings: () => settings++,
        dismiss: () => dismissed++,
      );
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_explanation), findsOneWidget);
      expect(find.text(_hearing), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(settings, 0);
      expect(dismissed, 0);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(settings, 1);
      expect(dismissed, 0);
      // A settings return/rebuild is presentation only, never another action.
      await tester.pump();
      expect(settings, 1);
      await tester.tap(find.text('Not now'));
      expect(dismissed, 1);
      expect(settings, 1);
    },
  );

  for (final kind in [
    CallCameraResultCardKind.permissionRestricted,
    CallCameraResultCardKind.unavailable,
  ]) {
    testWidgets('VUI4 ${kind.name} never offers settings or permission copy', (
      tester,
    ) async {
      var settings = 0;
      await _pump(
        tester,
        kind: kind,
        title: _unavailable,
        audible: true,
        settings: () => settings++,
      );
      expect(find.text(_unavailable), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.text(_explanation), findsNothing);
      expect(find.text(_hearing), findsNothing);
      expect(settings, 0);
    });
  }

  testWidgets('VUI4 muted or disconnected audio omits hearing claim', (
    tester,
  ) async {
    await _pump(tester, audible: false, settings: () {});
    expect(find.text(_title), findsOneWidget);
    expect(find.text(_explanation), findsOneWidget);
    expect(find.text(_hearing), findsNothing);
    await _pump(tester, audible: true, settings: () {});
    expect(find.text(_hearing), findsOneWidget);
    await _pump(tester, audible: false, settings: () {});
    expect(find.text(_hearing), findsNothing);
  });

  testWidgets('VUI4 absent settings route stays dismissible', (tester) async {
    var dismissed = 0;
    await _pump(tester, dismiss: () => dismissed++);
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
    expect(find.text('Not now'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    expect(dismissed, 1);
  });

  testWidgets('VUI4 RTL large text narrow card keeps actions reachable', (
    tester,
  ) async {
    var settings = 0;
    const title = 'الوصول إلى الكاميرا غير مسموح';
    const action = 'فتح الإعدادات';
    const dismiss = 'ليس الآن';
    await _pump(
      tester,
      direction: TextDirection.rtl,
      scale: 2.5,
      width: 280,
      height: 320,
      title: title,
      explanation: 'اسمح بالوصول إلى الكاميرا من الإعدادات لتشغيل الفيديو.',
      settingsLabel: action,
      dismissLabel: dismiss,
      settings: () => settings++,
    );
    expect(find.text(title), findsOneWidget);
    expect(find.text(action), findsOneWidget);
    expect(find.text(dismiss), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(action));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    expect(settings, 1);
    final button = find.ancestor(
      of: find.text(action),
      matching: find.byType(FilledButton),
    );
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
