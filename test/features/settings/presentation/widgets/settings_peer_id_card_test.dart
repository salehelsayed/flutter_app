import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_peer_id_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(
    Widget child, {
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  BoxDecoration cardDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.padding == const EdgeInsets.all(16) &&
            widget.decoration is BoxDecoration,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  BoxDecoration peerIdContainerDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.padding ==
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10) &&
            widget.decoration is BoxDecoration,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  BoxDecoration copyButtonDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.minWidth == 36 &&
            widget.constraints?.maxWidth == 36 &&
            widget.constraints?.minHeight == 36 &&
            widget.constraints?.maxHeight == 36 &&
            widget.decoration is BoxDecoration,
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  const testPeerId = '12D3KooWQTqttTb9ujg1pVRmMfNsntP5r1HuoJwHw6XqshXKpuGH';

  testWidgets('renders PEER ID label', (tester) async {
    await tester.pumpWidget(wrap(const SettingsPeerIdCard(peerId: testPeerId)));

    expect(find.text('PEER ID'), findsOneWidget);
  });

  testWidgets('renders full peer ID in monospace', (tester) async {
    await tester.pumpWidget(wrap(const SettingsPeerIdCard(peerId: testPeerId)));

    expect(find.text(testPeerId), findsOneWidget);
  });

  testWidgets('shows copy icon when isCopied=false', (tester) async {
    await tester.pumpWidget(
      wrap(const SettingsPeerIdCard(peerId: testPeerId, isCopied: false)),
    );

    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('shows check icon when isCopied=true', (tester) async {
    await tester.pumpWidget(
      wrap(const SettingsPeerIdCard(peerId: testPeerId, isCopied: true)),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);
  });

  testWidgets('shows helper text', (tester) async {
    await tester.pumpWidget(wrap(const SettingsPeerIdCard(peerId: testPeerId)));

    expect(find.text('Your unique identifier on the network'), findsOneWidget);
  });

  testWidgets('uses representative light readable roles', (tester) async {
    const colors = BackgroundReadableColors.representativeLight;
    await tester.pumpWidget(
      wrap(
        const SettingsPeerIdCard(peerId: testPeerId),
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final section = tester.widget<Text>(find.text('PEER ID'));
    expect(section.style?.color, colors.textMuted);

    final peerContainer = peerIdContainerDecoration(tester);
    expect(peerContainer.color, colors.surfaceSubtle);
    expect((peerContainer.border! as Border).top.color, colors.border);

    final peerText = tester.widget<Text>(find.text(testPeerId));
    expect(peerText.style?.color, colors.textPrimary);

    final helper = tester.widget<Text>(
      find.text('Your unique identifier on the network'),
    );
    expect(helper.style?.color, colors.textMuted);

    final copyButton = copyButtonDecoration(tester);
    expect(copyButton.color, colors.surfaceSubtle);
    expect((copyButton.border! as Border).top.color, colors.glassBorder);

    final copyIcon = tester.widget<Icon>(find.byIcon(Icons.copy));
    expect(copyIcon.color, colors.iconSecondary);
  });

  testWidgets('keeps dark readable roles and copied state', (tester) async {
    const colors = BackgroundReadableColors.dark;
    await tester.pumpWidget(
      wrap(
        const SettingsPeerIdCard(peerId: testPeerId, isCopied: true),
        readableColors: colors,
      ),
    );

    final card = cardDecoration(tester);
    expect(card.color, colors.glassSurface);
    expect((card.border! as Border).top.color, colors.glassBorder);

    final section = tester.widget<Text>(find.text('PEER ID'));
    expect(section.style?.color, colors.textMuted);

    final peerText = tester.widget<Text>(find.text(testPeerId));
    expect(peerText.style?.color, colors.textPrimary);

    final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(checkIcon.color, const Color(0xFF14B8A6));
  });

  testWidgets('uses darker copied accent on representative light', (
    tester,
  ) async {
    const colors = BackgroundReadableColors.representativeLight;
    await tester.pumpWidget(
      wrap(
        const SettingsPeerIdCard(peerId: testPeerId, isCopied: true),
        readableColors: colors,
      ),
    );

    final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(checkIcon.color, const Color(0xFF0F766E));
  });

  testWidgets('tapping copy button calls onCopy', (tester) async {
    var copied = false;
    await tester.pumpWidget(
      wrap(SettingsPeerIdCard(peerId: testPeerId, onCopy: () => copied = true)),
    );

    await tester.tap(find.byIcon(Icons.copy));
    expect(copied, isTrue);
  });
}
