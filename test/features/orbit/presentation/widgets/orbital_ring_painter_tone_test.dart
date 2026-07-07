import 'package:flutter/material.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_ring_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default colors preserve the dark ring literals', () {
    const painter = OrbitalRingPainter();

    expect(painter.ring1Color, const Color(0x4081E6D9));
    expect(painter.ring2Color, const Color(0x33A78BFA));
    expect(painter.glowColor, const Color(0x1481E6D9));
  });

  testWidgets('painter accepts injected ring and glow colors', (tester) async {
    const ring1 = Color(0x47463A96);
    const ring2 = Color(0x61463A96);
    const glow = Color(0x24463A96);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: OrbitalRingPainter(
            ring1Color: ring1,
            ring2Color: ring2,
            glowColor: glow,
            arcs: [OrbitArcRing(radius: 140, phiMax: 0.4, arcIndex: 1)],
          ),
          size: Size(320, 320),
        ),
      ),
    );

    final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
    final painter = customPaint.painter! as OrbitalRingPainter;

    expect(painter.ring1Color, ring1);
    expect(painter.ring2Color, ring2);
    expect(painter.glowColor, glow);
    expect(painter.arcs.single.arcIndex, 1);
  });
}
