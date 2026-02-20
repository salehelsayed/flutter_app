import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_peer_id_card.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
  }

  const testPeerId = '12D3KooWQTqttTb9ujg1pVRmMfNsntP5r1HuoJwHw6XqshXKpuGH';

  testWidgets('renders PEER ID label', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsPeerIdCard(peerId: testPeerId),
    ));

    expect(find.text('PEER ID'), findsOneWidget);
  });

  testWidgets('renders full peer ID in monospace', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsPeerIdCard(peerId: testPeerId),
    ));

    expect(find.text(testPeerId), findsOneWidget);
  });

  testWidgets('shows copy icon when isCopied=false', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsPeerIdCard(peerId: testPeerId, isCopied: false),
    ));

    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('shows check icon when isCopied=true', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsPeerIdCard(peerId: testPeerId, isCopied: true),
    ));

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);
  });

  testWidgets('shows helper text', (tester) async {
    await tester.pumpWidget(wrap(
      const SettingsPeerIdCard(peerId: testPeerId),
    ));

    expect(
      find.text('Your unique identifier on the network'),
      findsOneWidget,
    );
  });

  testWidgets('tapping copy button calls onCopy', (tester) async {
    var copied = false;
    await tester.pumpWidget(wrap(
      SettingsPeerIdCard(
        peerId: testPeerId,
        onCopy: () => copied = true,
      ),
    ));

    await tester.tap(find.byIcon(Icons.copy));
    expect(copied, isTrue);
  });
}
