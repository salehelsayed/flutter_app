import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/post_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';

void main() {
  testWidgets('Arabic-only post body drives RTL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PostCard(
            post: _post(text: 'مرحبا'),
          ),
        ),
      ),
    );

    expect(find.text('مرحبا'), findsOneWidget);
    expect(_linkableTextFor(tester, 'مرحبا').textDirection, TextDirection.rtl);
  });

  testWidgets('Arabic-first mixed post body drives RTL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PostCard(
            post: _post(text: 'مرحبا Hello 123'),
          ),
        ),
      ),
    );

    expect(find.text('مرحبا Hello 123'), findsOneWidget);
    expect(
      _linkableTextFor(tester, 'مرحبا Hello 123').textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('English-first mixed post body stays LTR', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PostCard(
            post: _post(text: 'Hello مرحبا 123'),
          ),
        ),
      ),
    );

    expect(find.text('Hello مرحبا 123'), findsOneWidget);
    expect(
      _linkableTextFor(tester, 'Hello مرحبا 123').textDirection,
      TextDirection.ltr,
    );
  });
}

LinkableText _linkableTextFor(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is LinkableText && widget.text == text,
    description: 'LinkableText("$text")',
  );
  expect(finder, findsOneWidget);
  return tester.widget<LinkableText>(finder);
}

PostModel _post({required String text}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
