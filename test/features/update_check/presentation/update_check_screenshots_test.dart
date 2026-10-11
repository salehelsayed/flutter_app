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
