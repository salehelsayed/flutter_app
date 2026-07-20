import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_exit_recovery_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  final candidate = GroupMember(
    groupId: 'group-1',
    peerId: 'peer-bob',
    username: 'Bob',
    role: MemberRole.writer,
    joinedAt: DateTime.utc(2026, 7, 19),
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<GroupMember> candidates = const [],
    bool pendingRoleSync = false,
    Locale locale = const Locale('en'),
    TextScaler textScaler = TextScaler.noScaling,
    required Future<GroupExitPromotionUiResult> Function(GroupMember) onPromote,
    required Future<bool> Function() onRetry,
    required Future<bool> Function() onContinue,
    required Future<bool> Function() onDissolve,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => GroupExitRecoverySheet(
                    groupName: 'Night Owls',
                    candidates: candidates,
                    pendingRoleSync: pendingRoleSync,
                    onPromote: onPromote,
                    onRetryPendingSync: onRetry,
                    onContinueLeave: onContinue,
                    onDissolve: onDissolve,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sole admin guidance is non-destructive and handles no eligible successor',
    (tester) async {
      var promoteCalls = 0;
      var retryCalls = 0;
      var continueCalls = 0;
      var dissolveCalls = 0;
      await pumpSheet(
        tester,
        onPromote: (_) async {
          promoteCalls++;
          return GroupExitPromotionUiResult.readyToLeave;
        },
        onRetry: () async {
          retryCalls++;
          return false;
        },
        onContinue: () async {
          continueCalls++;
          return false;
        },
        onDissolve: () async {
          dissolveCalls++;
          return false;
        },
      );

      final context = tester.element(find.byType(GroupExitRecoverySheet));
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.group_exit_only_admin_title), findsOneWidget);
      expect(
        find.text(l10n.group_exit_only_admin_body('Night Owls')),
        findsOneWidget,
      );
      expect(find.text(l10n.group_exit_no_eligible_successor), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-exit-choose-admin')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('group-exit-dissolve')));
      await tester.pumpAndSettle();
      expect(dissolveCalls, 1);
      expect(find.byType(GroupExitRecoverySheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-exit-keep')));
      await tester.pumpAndSettle();
      expect(find.byType(GroupExitRecoverySheet), findsNothing);
      expect(promoteCalls, 0);
      expect(retryCalls, 0);
      expect(continueCalls, 0);
      expect(dissolveCalls, 1);
    },
  );

  testWidgets('promotion UI waits for durable sync without promoting twice', (
    tester,
  ) async {
    final promotionGate = Completer<GroupExitPromotionUiResult>();
    var promotionCalls = 0;
    var retryCalls = 0;
    await pumpSheet(
      tester,
      candidates: [candidate],
      onPromote: (_) {
        promotionCalls++;
        return promotionGate.future;
      },
      onRetry: () async => false,
      onContinue: () async => false,
      onDissolve: () async => false,
    );
    await tester.tap(find.byKey(const ValueKey('group-exit-choose-admin')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('group-exit-candidate-peer-bob')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('group-exit-promote')));
    await tester.tap(
      find.byKey(const ValueKey('group-exit-promote')),
      warnIfMissed: false,
    );
    expect(promotionCalls, 1);
    promotionGate.complete(GroupExitPromotionUiResult.pendingSync);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-exit-retry-sync')), findsOneWidget);

    // Close/reopen with the durable role row still present.
    await tester.tap(find.byKey(const ValueKey('group-exit-close')));
    await tester.pumpAndSettle();
    await pumpSheet(
      tester,
      candidates: [candidate],
      pendingRoleSync: true,
      onPromote: (_) async {
        promotionCalls++;
        return GroupExitPromotionUiResult.readyToLeave;
      },
      onRetry: () async {
        retryCalls++;
        return retryCalls > 1;
      },
      onContinue: () async => false,
      onDissolve: () async => false,
    );
    await tester.tap(find.byKey(const ValueKey('group-exit-retry-sync')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-exit-continue')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-exit-retry-sync')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-exit-continue')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-exit-stay')));
    await tester.pumpAndSettle();
    expect(promotionCalls, 1);
    expect(retryCalls, 2);
  });

  testWidgets('retry failure leaves the recovery sheet operable', (
    tester,
  ) async {
    var retryCalls = 0;
    await pumpSheet(
      tester,
      pendingRoleSync: true,
      onPromote: (_) async => GroupExitPromotionUiResult.failed,
      onRetry: () async {
        retryCalls++;
        if (retryCalls == 1) {
          throw StateError('transient pending-row read failure');
        }
        return true;
      },
      onContinue: () async => false,
      onDissolve: () async => false,
    );

    final retryFinder = find.byKey(const ValueKey('group-exit-retry-sync'));
    await tester.tap(retryFinder);
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
    expect(tester.widget<FilledButton>(retryFinder).onPressed, isNotNull);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('group-exit-close')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(retryFinder);
    await tester.pumpAndSettle();
    expect(retryCalls, 2);
    expect(find.byKey(const ValueKey('group-exit-continue')), findsOneWidget);
  });

  testWidgets('exit guidance is semantic RTL and large-text safe', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSheet(
      tester,
      candidates: [candidate],
      locale: const Locale('ar'),
      textScaler: const TextScaler.linear(2),
      onPromote: (_) async => GroupExitPromotionUiResult.failed,
      onRetry: () async => false,
      onContinue: () async => false,
      onDissolve: () async => false,
    );

    expect(
      Directionality.of(tester.element(find.byType(GroupExitRecoverySheet))),
      TextDirection.rtl,
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final sheetContext = tester.element(find.byType(GroupExitRecoverySheet));
    final l10n = AppLocalizations.of(sheetContext)!;
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('group-exit-choose-admin')),
      ),
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('group-exit-close'))),
      matchesSemantics(
        tooltip: l10n.group_exit_keep_and_close_semantics,
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('group-exit-choose-admin')));
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<String>), findsOneWidget);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('group-exit-candidate-peer-bob')),
      ),
      matchesSemantics(
        label: 'Bob',
        hasCheckedState: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GroupExitRecoverySheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-exit-choose-admin')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('group-exit-close')));
    await tester.pumpAndSettle();
    expect(find.byType(GroupExitRecoverySheet), findsNothing);
    semantics.dispose();
  });
}
