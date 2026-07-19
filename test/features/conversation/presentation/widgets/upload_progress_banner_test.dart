import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('upload banner shows percent progress with unchanged title', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UploadProgressBanner(
            state: UploadProgressViewState(sentBytes: 68, totalBytes: 100),
          ),
        ),
      ),
    );

    expect(find.textContaining('68%'), findsOneWidget);
    expect(find.text('Uploading media'), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });
}
