import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void main() {
  Widget wrap(BackgroundReadableColors colors, Widget child) {
    return MaterialApp(
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(body: Center(child: child)),
    );
  }

  BoxDecoration avatarFrame(WidgetTester tester, Color fill) {
    return tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.color == fill);
  }

  testWidgets('photo frame uses Signal border and fill on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(
      wrap(
        colors,
        UserAvatar(avatarBytes: Uint8List.fromList(_transparentPng), size: 40),
      ),
    );

    final decoration = avatarFrame(tester, colors.avatarFrameFill);
    expect(decoration.color, colors.avatarFrameFill);
    expect((decoration.border as Border).top.color, colors.avatarFrameBorder);
  });

  testWidgets('fallback frame uses Signal border and fill on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(wrap(colors, const UserAvatar(size: 40)));

    final decoration = avatarFrame(tester, colors.avatarFrameFill);
    expect(decoration.color, colors.avatarFrameFill);
    expect((decoration.border as Border).top.color, colors.avatarFrameBorder);
  });

  testWidgets('dark frame literals stay unchanged', (tester) async {
    await tester.pumpWidget(
      wrap(BackgroundReadableColors.dark, const UserAvatar(size: 40)),
    );

    final decoration = avatarFrame(tester, const Color(0xB316181E));
    expect((decoration.border as Border).top.color, const Color(0x59FFFFFF));
  });
}
