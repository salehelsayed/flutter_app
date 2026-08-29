import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(BackgroundReadableColors colors, {bool isRecording = false}) {
    return MaterialApp(
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(
        body: Center(
          child: VoiceRecordButton(
            onTapDown: () {},
            onTapUp: () {},
            onTapCancel: () {},
            isRecording: isRecording,
          ),
        ),
      ),
    );
  }

  BoxDecoration buttonDecoration(WidgetTester tester) {
    return tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .single
            .decoration
        as BoxDecoration;
  }

  testWidgets('idle mic fill, border, and icon use Signal tones on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(wrap(colors));
    await tester.pump();

    final decoration = buttonDecoration(tester);
    expect(decoration.color, colors.micBg);
    expect((decoration.border as Border).top.color, colors.micBorder);

    final icon = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
    expect(icon.color, colors.micIcon);
  });

  testWidgets('recording mic fill and shadow use Signal accent on light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(wrap(colors, isRecording: true));
    await tester.pump();

    final decoration = buttonDecoration(tester);
    expect(decoration.color, colors.accent);
    expect(decoration.boxShadow!.single.color, colors.micShadow);

    final icon = tester.widget<Icon>(find.byIcon(Icons.arrow_upward_rounded));
    expect(icon.color, colors.accentIcon);
  });

  testWidgets('dark mic literals stay unchanged', (tester) async {
    await tester.pumpWidget(wrap(BackgroundReadableColors.dark));
    await tester.pump();

    final decoration = buttonDecoration(tester);
    expect(decoration.color, const Color(0x261DB954));
    expect((decoration.border as Border).top.color, const Color(0x4D1DB954));

    final icon = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
    expect(icon.color, const Color(0xFF1DB954));
  });
}
