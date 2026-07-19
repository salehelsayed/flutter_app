import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _card(MessageUploadProgressViewState progress) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: LetterCard(
      senderPeerId: 'me',
      senderName: 'You',
      text: '',
      time: '12:00',
      isIncoming: false,
      status: 'sending',
      messageUploadProgress: progress,
    ),
  ),
);

void main() {
  testWidgets('renders automatic message upload percent', (tester) async {
    await tester.pumpWidget(
      _card(
        const MessageUploadProgressViewState(
          messageId: 'message-a',
          attachmentId: 'attachment-a',
          sentBytes: 5,
          totalBytes: 10,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('message-upload-progress-message-a')),
      findsOneWidget,
    );
    expect(find.text('Sending automatically…'), findsOneWidget);
    expect(find.text('Uploading photo · 50%'), findsOneWidget);
  });

  testWidgets('uses localized fallback when the bridge omits total bytes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(
        const MessageUploadProgressViewState(
          messageId: 'message-a',
          attachmentId: 'attachment-a',
          sentBytes: 5,
          totalBytes: 0,
        ),
      ),
    );

    expect(find.text('Sending automatically…'), findsOneWidget);
    expect(find.text('Uploading photo…'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
