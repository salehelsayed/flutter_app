import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/widgets/video_processing_notice.dart';

void main() {
  testWidgets('retry notice remains readable and expires with accessible navigation',
      (tester) async {
    late BuildContext noticeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: Builder(builder: (context) {
              noticeContext = context;
              return const TextField();
            }),
          ),
        ),
      ),
    );
    showVideoProcessingNotice(
      noticeContext,
      message: 'Video stopped',
      retryLabel: 'Retry',
      onRetry: () {},
    );
    await tester.pumpAndSettle();
    final notice = tester.widget<SnackBar>(find.byType(SnackBar));
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    expect(notice.persist, isFalse);
    expect(notice.behavior, SnackBarBehavior.floating);
    expect(notice.margin!.resolve(TextDirection.ltr).bottom, greaterThanOrEqualTo(80));
    expect(action.textColor, isNot(notice.backgroundColor));
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Video stopped'), findsNothing);
  });
}
