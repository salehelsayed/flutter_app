import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_return_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // SE-42 device finding (2026-10-14): on a screen with no other semantics
  // sibling, the bar's label merged into the root node, so Android reported
  // full-screen bounds and a tap at their centre missed the bar.
  testWidgets('accessibility node has the bar bounds, not the screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var returned = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Like the call overlay: above the navigator, so no route node.
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CallReturnBar(
                name: 'Synthetic peer',
                state: CallState.connected,
                connectedAt: DateTime.utc(2026, 10, 14, 12),
                muted: false,
                now: () => DateTime.utc(2026, 10, 14, 12, 0, 5),
                onReturn: () => returned++,
              ),
            ),
          ],
        ),
      ),
    );

    final bar = tester.getRect(find.byKey(const ValueKey('call-return-bar')));
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Return to call,')),
    );
    expect(node.parent, isNotNull, reason: 'must not be the root node');
    var rect = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final transform = n.transform;
      if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
    }
    final ratio = tester.view.devicePixelRatio;
    expect(
      Rect.fromLTRB(
        rect.left / ratio,
        rect.top / ratio,
        rect.right / ratio,
        rect.bottom / ratio,
      ),
      bar,
    );

    tester.semantics.tap(find.semantics.byLabel(RegExp('^Return to call,')));
    expect(returned, 1);
    semantics.dispose();
  });
}
