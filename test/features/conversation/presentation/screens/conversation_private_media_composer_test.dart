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

const _selectorEligibilityTestName =
    'selector appears only for one eligible image or video and GIF stays keep in chat';

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
    String recipientName = 'Lina',
    TargetPlatform targetPlatform = TargetPlatform.android,
    bool senderReopenEnabled = false,
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
            privateMediaRecipientName: recipientName,
            privateMediaTargetPlatform: targetPlatform,
            privateMediaSenderReopenEnabled: senderReopenEnabled,
          ),
        ),
      ),
    );
  }

  testWidgets(_selectorEligibilityTestName, (tester) async {
    for (final kind in const [
      PrivateMediaAttachmentKind.image,
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
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('private-media-selector')),
          matching: find.text('Keep in chat'),
        ),
        findsOneWidget,
        reason: kind.name,
      );
    }

    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.gif,
        ),
        policy: const PrivateMediaPolicy.protected(),
        onPolicyChanged: (_) {},
      ),
    );
    expect(
      find.byKey(const ValueKey('private-media-selector')),
      findsNothing,
      reason: 'a new GIF draft has no private-mode selector',
    );
    expect(find.text('Protected view'), findsNothing);

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

  testWidgets('sheet keeps selection provisional until CTA commits it', (
    tester,
  ) async {
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
    await tester.pump();

    expect(selected, isNull);
    expect(find.text('Use Protected view'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('private-media-use-mode')));
    await tester.pumpAndSettle();

    expect(selected?.mode, PrivateMediaMode.protected);
    expect(selected?.durationSeconds, isNull);
  });

  testWidgets('sheet uses consequence-led labels, title, and duration chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        ),
        onPolicyChanged: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('private-media-selector')));
    await tester.pumpAndSettle();

    expect(find.text('How should Lina see this photo?'), findsOneWidget);
    expect(find.text('Keep in chat'), findsNWidgets(2));
    expect(find.text('Protected view'), findsOneWidget);
    expect(find.text('They can save or share it.'), findsOneWidget);
    expect(
      find.text('They can view it again, but not save or share it.'),
      findsOneWidget,
    );
    expect(find.text('Disappears after they open it once.'), findsOneWidget);
    expect(
      find.text("Disappears from Lina's phone after a time you choose."),
      findsOneWidget,
    );
    expect(find.text('Set an expiry'), findsOneWidget);
    expect(find.text('1 hour'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('private-media-option-expiry')));
    await tester.pump();
    expect(find.text('1 hour'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget);
    expect(find.text('Ordinary'), findsNothing);
  });

  testWidgets('chip renders Protected view after protected selection', (
    tester,
  ) async {
    var selectedPolicy = const PrivateMediaPolicy.ordinary();

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => buildComposer(
          eligibility: const PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.image,
          ),
          policy: selectedPolicy,
          onPolicyChanged: (policy) {
            setState(() => selectedPolicy = policy);
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('private-media-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('private-media-option-protected')),
    );
    await tester.tap(find.byKey(const ValueKey('private-media-use-mode')));
    await tester.pumpAndSettle();

    expect(selectedPolicy, const PrivateMediaPolicy.protected());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('private-media-selector')),
        matching: find.text('Protected view'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('view-once and exact disappearing durations emit typed policy', (
    tester,
  ) async {
    final cases =
        <({Key? modeKey, Key? durationKey, PrivateMediaPolicy expected})>[
          (
            modeKey: const ValueKey('private-media-option-view-once'),
            durationKey: null,
            expected: const PrivateMediaPolicy.viewOnce(),
          ),
          (
            modeKey: const ValueKey('private-media-option-expiry'),
            durationKey: const ValueKey('private-media-option-disappearing-1h'),
            expected: PrivateMediaPolicy.disappearing(3600),
          ),
          (
            modeKey: const ValueKey('private-media-option-expiry'),
            durationKey: const ValueKey('private-media-option-disappearing-1d'),
            expected: PrivateMediaPolicy.disappearing(86400),
          ),
          (
            modeKey: const ValueKey('private-media-option-expiry'),
            durationKey: const ValueKey('private-media-option-disappearing-7d'),
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
      await tester.tap(find.byKey(testCase.modeKey!));
      await tester.pump();
      if (testCase.durationKey != null) {
        await tester.tap(find.byKey(testCase.durationKey!));
        await tester.pump();
      }
      expect(selected, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('private-media-use-mode')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('private-media-use-mode')));
      await tester.pumpAndSettle();
      expect(
        selected,
        testCase.expected,
        reason: testCase.durationKey?.toString() ?? testCase.modeKey.toString(),
      );
    }
  });

  testWidgets('dismissing the sheet does not commit provisional state', (
    tester,
  ) async {
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
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });

  testWidgets('summary is derived from externally supplied policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        ),
        policy: const PrivateMediaPolicy.protected(),
        onPolicyChanged: (_) {},
      ),
    );

    expect(find.text('Protected view'), findsOneWidget);
    expect(find.text('Viewable again · no saving or sharing'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        ),
        policy: const PrivateMediaPolicy.ordinary(),
        onPolicyChanged: (_) {},
      ),
    );
    await tester.pump();

    expect(find.text('Keep in chat'), findsOneWidget);
    expect(find.text('Normal photo · can be saved or shared'), findsOneWidget);
  });

  testWidgets('disclosure is platform-true and sender reopen is gated', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.video,
        ),
        recipientName: 'Lina',
        targetPlatform: TargetPlatform.iOS,
        onPolicyChanged: (_) {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('private-media-selector')));
    await tester.pumpAndSettle();
    expect(find.text('How should Lina see this video?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('private-media-option-protected')),
    );
    await tester.pump();

    final disclosure = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('private-media-policy-disclosure')),
        matching: find.byType(Text),
      ),
    );
    expect(
      disclosure.data,
      contains('iOS cannot reliably prevent screenshots'),
    );
    expect(
      disclosure.data,
      isNot(contains('You can reopen it once here after sending.')),
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      buildComposer(
        eligibility: const PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        ),
        senderReopenEnabled: true,
        onPolicyChanged: (_) {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('private-media-selector')));
    await tester.pumpAndSettle();
    expect(find.text('How should Lina see this photo?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('private-media-option-view-once')),
    );
    await tester.pump();
    expect(
      find.textContaining('You can reopen it once here after sending.'),
      findsOneWidget,
    );
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
    const attachmentCounts = <int>[0, 1, 2];
    const flags = <bool>[false, true];
    final selectedPolicies = <PrivateMediaPolicy>[
      const PrivateMediaPolicy.protected(),
      const PrivateMediaPolicy.viewOnce(),
      PrivateMediaPolicy.disappearing(3600),
    ];

    for (final selectedPolicy in selectedPolicies) {
      for (final attachmentCount in attachmentCounts) {
        for (final attachmentKind in PrivateMediaAttachmentKind.values) {
          for (final hasTextOrCaption in flags) {
            for (final isEdit in flags) {
              for (final isForward in flags) {
                final eligibility = PrivateMediaEligibility(
                  attachmentCount: attachmentCount,
                  attachmentKind: attachmentKind,
                  hasTextOrCaption: hasTextOrCaption,
                  isEdit: isEdit,
                  isForward: isForward,
                );
                final isEligibleNewSelection =
                    attachmentCount == 1 &&
                    (attachmentKind == PrivateMediaAttachmentKind.image ||
                        attachmentKind == PrivateMediaAttachmentKind.video) &&
                    !hasTextOrCaption &&
                    !isEdit &&
                    !isForward;
                final reason =
                    'policy=${selectedPolicy.mode.wireValue} '
                    'count=$attachmentCount kind=${attachmentKind.name} '
                    'caption=$hasTextOrCaption edit=$isEdit '
                    'forward=$isForward';

                final next = normalizePrivateMediaComposerPolicy(
                  selectedPolicy: selectedPolicy,
                  eligibility: eligibility,
                  eligibleAttachmentIdentityChanged: isEligibleNewSelection,
                );
                expect(
                  next,
                  const PrivateMediaPolicy.ordinary(),
                  reason: reason,
                );

                if (isEligibleNewSelection) {
                  final retained = normalizePrivateMediaComposerPolicy(
                    selectedPolicy: selectedPolicy,
                    eligibility: eligibility,
                    eligibleAttachmentIdentityChanged: false,
                  );
                  expect(retained, selectedPolicy, reason: reason);
                }
              }
            }
          }
        }
      }
    }
  });
}
