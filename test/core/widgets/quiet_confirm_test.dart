import 'package:flutter/material.dart';
import 'package:flutter_app/core/widgets/quiet_confirm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quiet confirm renders as a centered success pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showQuietConfirm(context, 'Link copied'),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    final pillFinder = find.byKey(const ValueKey('quiet-confirm'));
    expect(pillFinder, findsOneWidget);
    final snackBar = tester.widget<SnackBar>(pillFinder);
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.width, isNotNull);
    expect(snackBar.width, lessThan(tester.view.physicalSize.width));
    expect(snackBar.shape, isA<StadiumBorder>());
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Link copied'), findsOneWidget);
  });
}
