import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/widgets/background_choice_control.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({
    Locale locale = const Locale('en'),
    BackgroundPreference value = BackgroundPreference.defaultBackground,
    ValueChanged<BackgroundPreference>? onChanged,
    String? errorText,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BackgroundChoiceControl(
          value: value,
          onChanged: onChanged ?? (_) {},
          errorText: errorText,
        ),
      ),
    );
  }

  testWidgets('shows both background options with default selected', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('The current ambient background.'), findsOneWidget);
    expect(find.text('Cosmic'), findsOneWidget);
    expect(find.text('A deep starfield for Feed.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-choice-default-selected-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('background-choice-cosmic-selected-icon')),
      findsNothing,
    );
  });

  testWidgets('shows cosmic selected', (tester) async {
    await tester.pumpWidget(wrap(value: BackgroundPreference.cosmic));

    expect(
      find.byKey(const ValueKey('background-choice-default-selected-icon')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('background-choice-cosmic-selected-icon')),
      findsOneWidget,
    );
  });

  testWidgets('tapping options notifies selection', (tester) async {
    BackgroundPreference? selected;
    await tester.pumpWidget(wrap(onChanged: (value) => selected = value));

    await tester.tap(find.byKey(const ValueKey('background-choice-default')));

    expect(selected, BackgroundPreference.defaultBackground);

    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));

    expect(selected, BackgroundPreference.cosmic);
  });

  testWidgets('exposes control purpose and selected option in semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(wrap());

      final controlNode = tester.getSemantics(
        find.byKey(const ValueKey('background-choice-control-semantics')),
      );
      expect(controlNode.label, contains('App background setting'));
      expect(controlNode.value, 'Default selected');

      final optionNode = tester.getSemantics(
        find.byKey(const ValueKey('background-choice-default-semantics')),
      );
      expect(optionNode.label, contains('Default'));
      expect(optionNode.value, 'Default selected');
      expect(optionNode.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(optionNode.hasFlag(SemanticsFlag.isSelected), isTrue);

      final cosmicNode = tester.getSemantics(
        find.byKey(const ValueKey('background-choice-cosmic-semantics')),
      );
      expect(cosmicNode.label, contains('Cosmic'));
      expect(cosmicNode.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(cosmicNode.hasFlag(SemanticsFlag.isSelected), isFalse);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('exposes cosmic selected state in semantics', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(wrap(value: BackgroundPreference.cosmic));

      final controlNode = tester.getSemantics(
        find.byKey(const ValueKey('background-choice-control-semantics')),
      );
      expect(controlNode.value, 'Cosmic selected');

      final cosmicNode = tester.getSemantics(
        find.byKey(const ValueKey('background-choice-cosmic-semantics')),
      );
      expect(cosmicNode.label, contains('Cosmic'));
      expect(cosmicNode.value, 'Cosmic selected');
      expect(cosmicNode.hasFlag(SemanticsFlag.isSelected), isTrue);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('resolves background option copy for supported locales', (
    tester,
  ) async {
    final cases = <Locale, List<String>>{
      const Locale('en'): ['Background', 'Cosmic'],
      const Locale('de'): ['Hintergrund', 'Kosmisch'],
      const Locale('ar'): ['الخلفية', 'كونية'],
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(wrap(locale: entry.key));

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('background-choice-title')),
      );
      expect(title.data, entry.value.first);
      expect(title.data, isNotEmpty);
      expect(title.data, isNot(contains('settings_')));
      expect(find.text(entry.value.last), findsOneWidget);
    }
  });

  testWidgets('shows failed-save copy when provided', (tester) async {
    await tester.pumpWidget(
      wrap(errorText: 'Background choice could not be saved'),
    );

    expect(find.text('Background choice could not be saved'), findsOneWidget);
  });
}
