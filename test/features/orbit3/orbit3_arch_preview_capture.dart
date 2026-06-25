// Not a *_test.dart file on purpose: a visual CAPTURE harness, run explicitly to
// render the Orbit3 One Circle ARCH (collapsed near the circle + expanded arcs
// above the circle) to PNGs so the layout can be eyeballed without a simulator.
//
//   flutter test test/features/orbit3/orbit3_arch_preview_capture.dart
//
// Output: build/orbit3_previews/arch_*.png

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/features/orbit3/presentation/screens/orbit3_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const outDir = 'build/orbit3_previews';
  Directory(outDir).createSync(recursive: true);

  testWidgets('capture orbit3 arch collapsed + expanded', (tester) async {
    // Short, device-like surface so the cap+scroll + no-overlap are exercised.
    tester.view.physicalSize = const ui.Size(390, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) {
        return;
      }
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: key,
        child: const Orbit3Screen(userPeerId: 'orbit3-you'),
      ),
    ));

    // Stepped pumps: staggered avatar-entrance Timers fire AND their animations
    // advance frame-by-frame (a single huge pump leaves them stuck at t=0).
    Future<void> drain() async {
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> goTo(String pop) async {
      for (var i = 0; i < 6; i++) {
        if (find.text(pop).evaluate().isNotEmpty) break;
        await tester.tap(find.byKey(const ValueKey('orbit3-population-cycler')));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await drain();
    }

    // Default population is 24 → arch "+11" sitting just above the outer ring.
    await drain();
    await capture('arch_pop24_collapsed');

    await goTo('50'); // arch "+37"
    await capture('arch_pop50_collapsed');

    // Expand → the arc rows fill the space ABOVE the still-visible circle.
    await tester.tap(find.byKey(const ValueKey('orbit3-arch-overflow')));
    await tester.pump(const Duration(milliseconds: 350));
    await drain();
    await capture('arch_pop50_expanded');

    // 100 users (168 C5): cycling closes the arch; reopen + capture.
    await goTo('100');
    await tester.tap(find.byKey(const ValueKey('orbit3-arch-overflow')));
    await tester.pump(const Duration(milliseconds: 350));
    await drain();
    await capture('arch_pop100_expanded');

    // Wide spacing (168 fix): avatars must stay ON the rings + 7 per arch.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('orbit3-spacing-inc')));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await drain();
    await capture('arch_pop100_wide_spacing');
  });
}
