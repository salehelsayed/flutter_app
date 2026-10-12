import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/presentation/update_available_banner.dart';
import 'package:flutter_app/features/update_check/presentation/update_required_gate.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_update_check_service.dart';

/// Renders the SE-41 overlay and banner in EN and AR with real fonts. With
/// `--dart-define=SE41_SCREENSHOT_DIR=<dir>` it also writes PNGs for review.
void main() {
  setUpAll(_loadFonts);
  _textScaleCases();

  for (final locale in const [Locale('en'), Locale('ar')]) {
    for (final hard in const [true, false]) {
      final name = '${hard ? 'overlay' : 'banner'}_${locale.languageCode}';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 47 * 3);
        addTearDown(tester.view.reset);
        final service = FakeUpdateCheckService(
          decisions: [
            hard
                ? const UpdateDecisionHard(
                    minBuild: 120,
                    reasonCode: UpdateReasonCode.security,
                  )
                : const UpdateDecisionSoft(
                    latestBuild: 121,
                    reasonCode: UpdateReasonCode.general,
                  ),
          ],
        );
        final controller = UpdateCheckController(service: service);
        addTearDown(controller.dispose);
        final textTheme = ThemeData.light().textTheme.apply(
          fontFamily: 'Se41Roboto',
          fontFamilyFallback: const ['Se41Arabic'],
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('se41-screen'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(useMaterial3: true, textTheme: textTheme),
              builder: (context, child) => UpdateRequiredGate(
                controller: controller,
                callCapability: null,
                launchStore: (_) async => true,
                child: child!,
              ),
              home: const Scaffold(
                body: UpdateAvailableBannerHost(
                  child: Center(child: Icon(Icons.blur_circular, size: 160)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            ValueKey(
              hard ? 'update-required-overlay' : 'update-available-banner',
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, name);
      });
    }
  }
}

/// SE-41 copy review: the longest blocking bodies (protocol_change) in DE and
/// AR at the largest system text size (textScaler 2.0), on a large and a small
/// phone. The overlay must scroll or fit: no overflow, no clipped text, and
/// the update button must be reachable.
void _textScaleCases() {
  for (final locale in const [Locale('de'), Locale('ar')]) {
    for (final (device, size) in const [
      ('390x844', Size(390, 844)),
      ('320x568', Size(320, 568)),
    ]) {
      final name = 'overlay_${locale.languageCode}_textscale2_$device';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 47 * 3);
        addTearDown(tester.view.reset);
        final service = FakeUpdateCheckService(
          decisions: [
            const UpdateDecisionHard(
              minBuild: 120,
              reasonCode: UpdateReasonCode.protocolChange,
            ),
          ],
        );
        final controller = UpdateCheckController(service: service);
        addTearDown(controller.dispose);
        final textTheme = ThemeData.light().textTheme.apply(
          fontFamily: 'Se41Roboto',
          fontFamilyFallback: const ['Se41Arabic'],
        );
        var opened = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('se41-screen'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(useMaterial3: true, textTheme: textTheme),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: UpdateRequiredGate(
                  controller: controller,
                  callCapability: null,
                  launchStore: (_) async {
                    opened++;
                    return true;
                  },
                  child: child!,
                ),
              ),
              home: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Any RenderFlex overflow would be reported here.
        expect(tester.takeException(), isNull);
        final overlay = find.byKey(const ValueKey('update-required-overlay'));
        expect(overlay, findsOneWidget);

        final l10n = lookupAppLocalizations(locale);
        final body = find.text(l10n.update_required_body_protocol_change);
        expect(body, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(body);
        expect(paragraph.didExceedMaxLines, isFalse, reason: 'not clipped');
        expect(paragraph.textDirection, locale.languageCode == 'ar'
            ? TextDirection.rtl
            : TextDirection.ltr);

        // The button can be reached by scrolling and works.
        final button = find.text(l10n.update_required_button);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final screen = tester.getRect(overlay);
        expect(screen.contains(tester.getRect(button).center), isTrue);
        // The label, even when it wraps, stays inside the button shape.
        final shape = tester.getRect(
          find.ancestor(
            of: button,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        final label = tester.getRect(button);
        expect(shape.inflate(0.5).contains(label.topLeft), isTrue);
        expect(shape.inflate(0.5).contains(label.bottomRight), isTrue);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(tester.takeException(), isNull);
        await _capture(tester, name);
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('SE41_SCREENSHOT_DIR');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('se41-screen')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

// The pinned SDK's Roboto, Noto Naskh Arabic and Material icons, so the
// screenshots show real glyphs instead of the test font's boxes.
Future<void> _loadFonts() async {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(await config.readAsString())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
    (p) => p['name'] == 'flutter',
  );
  final sdk = Directory.fromUri(
    config.uri.resolve(flutter['rootUri'] as String),
  ).parent.parent;
  Future<ByteData> read(String path) =>
      File('${sdk.path}/$path').readAsBytes().then(ByteData.sublistView);
  final roboto = FontLoader('Se41Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(
      read('bin/cache/artifacts/material_fonts/Roboto-$weight.ttf'),
    );
  }
  await roboto.load();
  await (FontLoader('Se41Arabic')..addFont(
        read(
          'engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf',
        ),
      ))
      .load();
  await (FontLoader('MaterialIcons')..addFont(
        read('bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
      ))
      .load();
}
