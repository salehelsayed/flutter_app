// Not a *_test.dart file on purpose: this is a visual CAPTURE harness, run
// explicitly to render every Orbit3 constellation mode × archetype to a PNG so
// the prototype can be eyeballed without launching a simulator. Names/motion are
// off (test fonts are box-glyphs; the SHAPE is the fingerprint).
//
//   flutter test test/features/orbit3/orbit3_constellation_preview_capture.dart
//
// Output: build/orbit3_previews/<mode>_<archetype>.png

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_archetype_data.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_constellation_geometry.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_constellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const outDir = 'build/orbit3_previews';
  Directory(outDir).createSync(recursive: true);

  testWidgets('capture all constellation modes × archetypes', (tester) async {
    tester.view.physicalSize = const ui.Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> capture(
        String name, Orbit3ConstellationMode mode, Orbit3Archetype archetype,
        {double zoom = 1.0}) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF06070C),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 360,
                height: 360,
                color: const Color(0xFF06070C),
                child: Orbit3Constellation(
                  userPeerId: 'orbit3-you',
                  profiles: Orbit3ArchetypeData.build(archetype),
                  mode: mode,
                  namesVisible: false,
                  motionEnabled: false,
                  searchQuery: '',
                  t: 0.0,
                  zoom: zoom,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    for (final mode in Orbit3ConstellationMode.values) {
      for (final archetype in Orbit3Archetype.values) {
        await capture('${mode.name}_${archetype.name}', mode, archetype);
      }
    }
    // Zoomed-in frames to show avatars blooming + the milky-way reveal.
    await capture('galaxyZOOM_connector', Orbit3ConstellationMode.galaxy,
        Orbit3Archetype.connector,
        zoom: 3.0);
    await capture('zodiacZOOM_chatterbox', Orbit3ConstellationMode.zodiac,
        Orbit3Archetype.chatterbox,
        zoom: 2.6);
    await capture('gravityZOOM_connector', Orbit3ConstellationMode.gravity,
        Orbit3Archetype.connector,
        zoom: 2.6);
  });
}
