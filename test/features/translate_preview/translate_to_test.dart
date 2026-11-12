// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/chat_search.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/private_translator_settings_section.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_widgets.dart';
import 'package:flutter_app/features/translate_preview/translate_to_widgets.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/features/translate_preview/translation_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_model_delivery_controller.dart';

const _arabicIn = 'صباح الخير! هل أنت متفرغ هذا المساء؟';
const _arabicOut = 'نلتقي عند النهر غدا';
const _englishIn = 'See you at seven tonight';
const _translated = 'Good morning! Are you free this evening?';

class _RecordingAi implements OnDeviceAi {
  _RecordingAi([this.result = _translated]);

  final String result;
  final calls = <({String text, String languageName})>[];

  @override
  Future<String> translate(String text, {required String languageName}) async {
    calls.add((text: text, languageName: languageName));
    return result;
  }

  @override
  Future<String> transcribe(String audioPath) => throw UnimplementedError();
}

/// Android's pinned SharedPreferences: a failed delete returns false.
class _FailingRemove extends Fake implements SharedPreferences {
  _FailingRemove(this._real);

  final SharedPreferences _real;

  @override
  String? getString(String key) => _real.getString(key);

  @override
  List<String>? getStringList(String key) => _real.getStringList(key);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _real.setStringList(key, value);

  @override
  Future<bool> remove(String key) async => false;
}

ConversationMessage _text(String id, String text, {required bool incoming}) =>
    ConversationMessage(
      id: id,
      contactPeerId: 'peer-b',
      senderPeerId: incoming ? 'peer-b' : 'peer-a',
      text: text,
      timestamp: '2026-11-10T09:00:00.000Z',
      status: 'delivered',
      isIncoming: incoming,
      createdAt: '2026-11-10T09:00:00.000Z',
    );

Widget _screen(
  List<ConversationMessage> messages, {
  String ownPeerId = 'peer-a',
}) => localizedApp(
  Scaffold(
    body: ConversationScreen(
      contactPeerId: 'peer-b',
      contactUsername: 'User-B',
      connectionDate: 'October 28, 2026',
      ownPeerId: ownPeerId,
      messages: messages,
      onSend: (_) {},
      onBack: () {},
      hasMoreOlderMessages: false,
      initialLoadDone: true,
    ),
  ),
);

void main() {
  late TranslationPreferences prefs;
  late FakeModelDeliveryController delivery;
  late _RecordingAi ai;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = TranslationPreferences();
    debugTranslationPreferencesOverride = prefs;
    delivery = FakeModelDeliveryController(
      const ModelReady(sizeBytes: 2600000000),
    );
    debugModelDeliveryOverride = delivery;
    ai = _RecordingAi();
    debugOnDeviceAiOverride = ai;
  });

  tearDown(() {
    debugTranslationPreferencesOverride = null;
    debugModelDeliveryOverride = null;
    debugOnDeviceAiOverride = null;
    debugTranslatePreviewEnabledOverride = null;
  });

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('translation target', () {
    testWidgets('follows the app language, then the chosen language, then the '
        'app language again', (tester) async {
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: TranslatePreview(text: _arabicIn, ai: ai),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('See translation'));
      await tester.pump();
      expect(ai.calls.last.languageName, 'English');

      await prefs.setTarget('de');
      await tester.pump();
      await tester.tap(find.text('See translation'));
      await tester.pump();
      expect(ai.calls.last.languageName, 'German');

      await prefs.setTarget(null);
      await tester.pump();
      await tester.tap(find.text('See translation'));
      await tester.pump();
      expect(ai.calls.last.languageName, 'English');
    });

    test('erasing the account forgets every chat switch but keeps the '
        'language', () async {
      await prefs.setTarget('de');
      await prefs.setShowTranslation('peer-b', true);

      await prefs.forgetChats();

      final stored = await SharedPreferences.getInstance();
      expect(stored.getStringList('translate_preview.shown_in_chats'), isNull);
      expect(prefs.showsTranslationIn('peer-b'), isFalse);
      expect(stored.getString('translate_preview.target'), 'de');
      expect(prefs.target.value, 'de');
    });

    test(
      'a failed delete fails the erasure and keeps the chat switch',
      () async {
        final real = await SharedPreferences.getInstance();
        final failing = TranslationPreferences(
          preferences: () async => _FailingRemove(real),
        );
        await failing.setShowTranslation('peer-b', true);

        await expectLater(failing.forgetChats(), throwsStateError);

        expect(
          real.getStringList('translate_preview.shown_in_chats'),
          hasLength(1),
        );
        expect(failing.showsTranslationIn('peer-b'), isTrue);
      },
    );

    testWidgets('the choice survives a restart', (tester) async {
      await prefs.setTarget('de');
      await prefs.setShowTranslation('peer-b', true);
      final reopened = TranslationPreferences();
      await reopened.setShowTranslation('peer-c', false);
      expect(reopened.target.value, 'de');
      expect(reopened.showsTranslationIn('peer-b'), isTrue);
      expect(reopened.showsTranslationIn('peer-c'), isFalse);
    });
  });

  group('Settings', () {
    Future<void> pumpSection(
      WidgetTester tester,
      ModelDeliveryState state,
    ) async {
      delivery.state.value = state;
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: SingleChildScrollView(
              child: PrivateTranslatorSettingsSection(controller: delivery),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Translate to shows the current language and the list sets '
        'it, filtered by search', (tester) async {
      await pumpSection(tester, const ModelReady(sizeBytes: 2600000000));
      expect(find.text('Translate to'), findsOneWidget);
      expect(find.text('The language you read translations in.'), findsOne);
      expect(find.text('Same as the app'), findsOneWidget);

      await tester.tap(find.text('Translate to'));
      await tester.pumpAndSettle();
      expect(find.text('Translate to'), findsNWidgets(2));
      expect(find.text('Same as the app'), findsNWidgets(2));
      expect(find.text('English'), findsWidgets);
      expect(find.text('All languages'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'germ');
      await tester.pump();
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('German'), findsOneWidget);
      expect(find.text('العربية'), findsNothing);
      expect(find.text('All languages'), findsNothing);

      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();
      expect(prefs.target.value, 'de');
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('Same as the app'), findsNothing);
    });

    testWidgets('mobile-data switch only while the translator is not on the '
        'phone', (tester) async {
      await pumpSection(tester, const ModelReady(sizeBytes: 2600000000));
      expect(find.text('Download over mobile data'), findsNothing);
      expect(find.byType(Switch), findsNothing);

      await pumpSection(
        tester,
        const ModelNotDownloaded(
          totalBytes: 2600000000,
          freeBytes: 18400000000,
          onWifi: true,
        ),
      );
      expect(find.text('Download over mobile data'), findsOneWidget);
      expect(find.text('Translate to'), findsOneWidget);
    });

    testWidgets('no Translate to row on a phone that cannot run it', (
      tester,
    ) async {
      await pumpSection(tester, const ModelUnsupported());
      expect(find.text('Translate to'), findsNothing);
    });
  });

  group('chat header', () {
    Widget header({
      Locale locale = const Locale('en'),
      BackgroundReadableColors colors = BackgroundReadableColors.dark,
      double textScale = 1,
    }) => localizedApp(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Theme(
            data: ThemeData(extensions: [colors]),
            child: Scaffold(
              body: ConversationScreen(
                backgroundPreference: colors.isLightSurface
                    ? BackgroundPreference.daylightLagoon
                    : BackgroundPreference.defaultBackground,
                contactPeerId: 'peer-b',
                contactUsername: 'User-B',
                connectionDate: 'October 28, 2026',
                ownPeerId: 'peer-a',
                messages: const [],
                onSend: (_) {},
                onBack: () {},
                onOverflow: () {},
                onCall: () {},
                showCallAction: true,
                callActionEnabled: true,
                search: ChatSearchController(
                  search: (_) async => const [],
                  onShow: (_) {},
                ),
                hasMoreOlderMessages: false,
                initialLoadDone: true,
              ),
            ),
          ),
        ),
      ),
      locale: locale,
    );

    testWidgets('BL25U2 causal ready icon stays between '
        'search and the menu', (tester) async {
      debugTranslatePreviewEnabledOverride = true;
      delivery.state.value = const ModelNotDownloaded(
        totalBytes: 2600000000,
        freeBytes: 18400000000,
        onWifi: true,
      );
      await tester.pumpWidget(header());
      expect(find.byIcon(Icons.translate), findsNothing);

      delivery.state.value = const ModelReady(sizeBytes: 2600000000);
      await tester.pump();
      expect(find.byIcon(Icons.translate), findsOneWidget);
      final call = tester.getCenter(find.byIcon(Icons.call_outlined)).dx;
      final search = tester.getCenter(find.byIcon(Icons.search_rounded)).dx;
      final translate = tester.getCenter(find.byIcon(Icons.translate)).dx;
      final more = tester.getCenter(find.byIcon(Icons.more_vert)).dx;
      expect([
        call,
        search,
        translate,
        more,
      ], orderedEquals([call, search, translate, more]..sort()));
      expect(call < search && search < translate && translate < more, isTrue);
      await finish(tester);
    });

    testWidgets(
      'BL25U2 causal ready header uses Translation tooltip and semantics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          debugTranslatePreviewEnabledOverride = true;
          await tester.pumpWidget(header());
          expect(find.byIcon(Icons.translate), findsOneWidget);
          expect(find.byTooltip('Translation'), findsOneWidget);
          expect(find.bySemanticsLabel('Translation'), findsOneWidget);
          await finish(tester);
        } finally {
          semantics.dispose();
        }
      },
    );

    for (final (language, label) in [
      ('en', 'Translation'),
      ('de', 'Übersetzung'),
      ('ar', 'الترجمة'),
    ]) {
      testWidgets('BL25U2 $language header label fits narrow 2x text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        debugTranslatePreviewEnabledOverride = true;
        await tester.pumpWidget(header(locale: Locale(language), textScale: 2));
        expect(find.byTooltip(label), findsOneWidget);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }

    for (final (tone, colors) in [
      ('dark', BackgroundReadableColors.dark),
      ('light', BackgroundReadableColors.representativeLight),
    ]) {
      for (final language in ['en', 'ar']) {
        testWidgets(
          'BL25U2 $tone $language header uses accent only while on with inset dot',
          (tester) async {
            debugTranslatePreviewEnabledOverride = true;
            await tester.pumpWidget(
              header(locale: Locale(language), colors: colors),
            );
            final button = find.ancestor(
              of: find.byIcon(Icons.translate),
              matching: find.byType(IconButton),
            );
            final dot = find.descendant(
              of: find.byType(ChatTranslateAction),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle &&
                    widget.constraints?.maxWidth == 7,
              ),
            );
            expect(tester.getSize(button), const Size.square(48));
            expect(tester.widget<IconButton>(button).iconSize, 22);
            expect(
              tester.widget<IconButton>(button).color,
              colors.iconSecondary,
            );
            expect(dot, findsNothing);
            await prefs.setShowTranslation('peer-b', true);
            await tester.pump();
            expect(tester.widget<IconButton>(button).color, colors.accent);
            expect(dot, findsOneWidget);
            final bounds = tester.getRect(button);
            final mark = tester.getRect(dot);
            expect(mark.size, const Size.square(7));
            expect(mark.top - bounds.top, 9);
            expect(
              language == 'ar'
                  ? mark.left - bounds.left
                  : bounds.right - mark.right,
              8,
            );
            expect(
              (tester.widget<Container>(dot).decoration! as BoxDecoration)
                  .color,
              colors.accent,
            );
            await prefs.setShowTranslation('peer-b', false);
            await tester.pump();
            expect(dot, findsNothing);
            expect(
              tester.widget<IconButton>(button).color,
              colors.iconSecondary,
            );
            expect(tester.takeException(), isNull);
            await finish(tester);
          },
        );
      }
    }

    testWidgets('the panel has the language row and a switch for this chat '
        'only', (tester) async {
      debugTranslatePreviewEnabledOverride = true;
      await tester.pumpWidget(header());
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Translate to'), findsOneWidget);
      expect(find.text('Same as the app'), findsOneWidget);
      expect(find.text('Show translation'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 500));
      expect(prefs.showsTranslationIn('peer-b'), isTrue);
      expect(prefs.showsTranslationIn('peer-c'), isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await finish(tester);
    });
  });

  group('chat', () {
    final messages = [
      _text('in-ar', _arabicIn, incoming: true),
      _text('out-ar', _arabicOut, incoming: false),
      _text('in-en', _englishIn, incoming: true),
    ];

    testWidgets('with Show translation on, a received message in another '
        'language keeps its text and shows the translation below it', (
      tester,
    ) async {
      debugTranslatePreviewEnabledOverride = true;
      await prefs.setShowTranslation('peer-b', true);
      await tester.pumpWidget(_screen(messages));
      await tester.pump();
      await tester.pump();

      expect(find.text(_arabicIn), findsOneWidget);
      expect(find.text(_translated), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_translated)).dy,
        greaterThan(tester.getTopLeft(find.text(_arabicIn)).dy),
      );
      expect(find.text(_arabicOut), findsOneWidget);
      expect(find.text(_englishIn), findsOneWidget);
      expect(ai.calls, [(text: _arabicIn, languageName: 'English')]);

      await prefs.setShowTranslation('peer-b', false);
      await tester.pump();
      expect(find.text(_arabicIn), findsOneWidget);
      expect(find.text(_translated), findsNothing);
      await finish(tester);
    });

    testWidgets(
      'BL25U2 real message footer preserves directions and uses 8px gaps and 15/21 text',
      (tester) async {
        const original = 'مرحبا بك! نلتقي في المكتبة مساء الغد';
        const translated = 'See you in the library tomorrow.';
        debugTranslatePreviewEnabledOverride = true;
        debugOnDeviceAiOverride = _RecordingAi(translated);
        await prefs.setShowTranslation('peer-b', true);
        await tester.pumpWidget(
          _screen([
            _text('layout-ar', original, incoming: true),
            _text('out-ar', _arabicOut, incoming: false),
            _text('in-en', _englishIn, incoming: true),
          ]),
        );
        await tester.pump();
        await tester.pump();
        final originalText = find.byWidgetPredicate(
          (widget) => widget is LinkableText && widget.text == original,
        );
        final translatedText = find.byWidgetPredicate(
          (widget) => widget is LinkableText && widget.text == translated,
        );
        expect(originalText, findsOneWidget);
        expect(translatedText, findsOneWidget);
        final footer = find.byKey(
          const ValueKey('message-translation-layout-ar'),
        );
        final divider = find.descendant(
          of: footer,
          matching: find.byType(Divider),
        );
        expect(divider, findsOneWidget);
        expect(
          tester.getTopLeft(divider).dy - tester.getBottomLeft(originalText).dy,
          8,
        );
        expect(
          tester.getTopLeft(translatedText).dy -
              tester.getBottomLeft(divider).dy,
          8,
        );
        expect(tester.widget<Divider>(divider).thickness, 1);
        final text = tester.widget<LinkableText>(translatedText);
        expect(text.style?.fontSize, 15);
        expect(text.style?.height, 21 / 15);
        expect(
          text.style?.color,
          tester.element(translatedText).backgroundReadableColors.textSecondary,
        );
        expect(text.textDirection, TextDirection.ltr);
        expect(
          tester.widget<LinkableText>(originalText).textDirection,
          TextDirection.rtl,
        );
        expect(
          find.byKey(const ValueKey('message-translation-out-ar')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('message-translation-in-en')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );

    testWidgets('a translation made for one account never shows for the '
        'account that replaces it', (tester) async {
      const text = 'مساء الخير يا صديقي';
      final incoming = [_text('in-ar-2', text, incoming: true)];
      debugTranslatePreviewEnabledOverride = true;
      await prefs.setShowTranslation('peer-b', true);
      debugOnDeviceAiOverride = _RecordingAi('translated for account A');
      await tester.pumpWidget(_screen(incoming, ownPeerId: 'account-a'));
      await tester.pump();
      await tester.pump();
      expect(find.text('translated for account A'), findsOneWidget);
      await finish(tester);

      final accountB = _RecordingAi('translated for account B');
      debugOnDeviceAiOverride = accountB;
      await tester.pumpWidget(_screen(incoming, ownPeerId: 'account-b'));
      await tester.pump();
      await tester.pump();

      expect(find.text('translated for account A'), findsNothing);
      expect(find.text('translated for account B'), findsOneWidget);
      expect(accountB.calls, [(text: text, languageName: 'English')]);
      await finish(tester);
    });

    testWidgets('with Show translation off only the original shows', (
      tester,
    ) async {
      debugTranslatePreviewEnabledOverride = true;
      await tester.pumpWidget(_screen(messages));
      await tester.pump();
      expect(find.text(_arabicIn), findsOneWidget);
      expect(find.text(_translated), findsNothing);
      expect(ai.calls, isEmpty);
      await finish(tester);
    });

    testWidgets('the header no longer shows the connected date', (
      tester,
    ) async {
      await tester.pumpWidget(_screen(messages));
      await tester.pump();
      expect(find.text('User-B'), findsOneWidget);
      expect(find.text('Connected October 28, 2026'), findsNothing);
      await finish(tester);
    });
  });
}
