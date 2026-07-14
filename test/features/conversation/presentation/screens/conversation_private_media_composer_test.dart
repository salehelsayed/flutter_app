import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizationsEn());

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

void main() {
  test('eligibility has value equality for incremental composer state', () {
    const first = PrivateMediaEligibility(
      attachmentCount: 1,
      attachmentKind: PrivateMediaAttachmentKind.video,
    );
    const second = PrivateMediaEligibility(
      attachmentCount: 1,
      attachmentKind: PrivateMediaAttachmentKind.video,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('eligible attachment replacement resets the selected private mode', () {
    final next = normalizePrivateMediaComposerPolicy(
      selectedPolicy: const PrivateMediaPolicy.protected(),
      eligibility: const PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
      ),
      eligibleAttachmentIdentityChanged: true,
    );

    expect(next, const PrivateMediaPolicy.ordinary());
  });

  Widget buildComposer({
    required PrivateMediaEligibility eligibility,
    required ValueChanged<PrivateMediaPolicy> onPolicyChanged,
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        _TestAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComposeArea(
            onSend: (_) {},
            hasAttachments: eligibility.attachmentCount > 0,
            privateMediaEligibility: eligibility,
            privateMediaPolicy: policy,
            onPrivateMediaPolicyChanged: onPolicyChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('selector appears only for one eligible image', (tester) async {
    for (final kind in const [
      PrivateMediaAttachmentKind.image,
      PrivateMediaAttachmentKind.gif,
      PrivateMediaAttachmentKind.video,
    ]) {
      await tester.pumpWidget(
        buildComposer(
          eligibility: PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: kind,
          ),
          onPolicyChanged: (_) {},
        ),
      );
      expect(
        find.byKey(const ValueKey('private-media-selector')),
        findsOneWidget,
        reason: kind.name,
      );
    }

    for (final eligibility in const [
      PrivateMediaEligibility(
        attachmentCount: 0,
        attachmentKind: PrivateMediaAttachmentKind.unknown,
      ),
      PrivateMediaEligibility(
        attachmentCount: 2,
        attachmentKind: PrivateMediaAttachmentKind.image,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.audio,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.file,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
        hasTextOrCaption: true,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
        isEdit: true,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
        isForward: true,
      ),
    ]) {
      await tester.pumpWidget(
        buildComposer(eligibility: eligibility, onPolicyChanged: (_) {}),
      );
      expect(
        find.byKey(const ValueKey('private-media-selector')),
        findsNothing,
        reason: eligibility.attachmentKind.name,
      );
    }
  });

  testWidgets('protected selection emits the typed policy', (tester) async {
    PrivateMediaPolicy? selected;
    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        ),
        onPolicyChanged: (policy) => selected = policy,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('private-media-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('private-media-option-protected')),
    );
    await tester.pumpAndSettle();

    expect(selected?.mode, PrivateMediaMode.protected);
    expect(selected?.durationSeconds, isNull);
  });

  testWidgets('view-once and exact disappearing durations emit typed policy', (
    tester,
  ) async {
    final cases = <({Key key, PrivateMediaPolicy expected})>[
      (
        key: const ValueKey('private-media-option-view-once'),
        expected: const PrivateMediaPolicy.viewOnce(),
      ),
      (
        key: const ValueKey('private-media-option-disappearing-1h'),
        expected: PrivateMediaPolicy.disappearing(3600),
      ),
      (
        key: const ValueKey('private-media-option-disappearing-1d'),
        expected: PrivateMediaPolicy.disappearing(86400),
      ),
      (
        key: const ValueKey('private-media-option-disappearing-7d'),
        expected: PrivateMediaPolicy.disappearing(604800),
      ),
    ];

    for (final testCase in cases) {
      PrivateMediaPolicy? selected;
      await tester.pumpWidget(
        buildComposer(
          eligibility: const PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.video,
          ),
          onPolicyChanged: (policy) => selected = policy,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('private-media-selector')));
      await tester.pumpAndSettle();
      expect(
        find.text('Available for one view on this device.'),
        findsOneWidget,
      );
      expect(
        find.text('The expiry time is calculated on the receiving device.'),
        findsNWidgets(3),
      );
      await tester.tap(find.byKey(testCase.key));
      await tester.pumpAndSettle();
      expect(selected, testCase.expected, reason: testCase.key.toString());
    }
  });

  testWidgets('typing text resets a selected private policy', (tester) async {
    PrivateMediaPolicy? selected;
    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        ),
        policy: const PrivateMediaPolicy.protected(),
        onPolicyChanged: (policy) => selected = policy,
      ),
    );

    await tester.enterText(find.byType(TextField), 'caption');
    await tester.pump();

    expect(selected, const PrivateMediaPolicy.ordinary());
  });

  test('every stale or ineligible composer shape resets private policy', () {
    final cases = const [
      PrivateMediaEligibility(
        attachmentCount: 0,
        attachmentKind: PrivateMediaAttachmentKind.unknown,
      ),
      PrivateMediaEligibility(
        attachmentCount: 2,
        attachmentKind: PrivateMediaAttachmentKind.image,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.audio,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.file,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
        hasTextOrCaption: true,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
        isEdit: true,
      ),
      PrivateMediaEligibility(
        attachmentCount: 1,
        attachmentKind: PrivateMediaAttachmentKind.image,
        isForward: true,
      ),
    ];

    for (final eligibility in cases) {
      final next = normalizePrivateMediaComposerPolicy(
        selectedPolicy: const PrivateMediaPolicy.protected(),
        eligibility: eligibility,
        eligibleAttachmentIdentityChanged: false,
      );
      expect(next, const PrivateMediaPolicy.ordinary());
    }
  });
}
