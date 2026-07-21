import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/widgets/group_exit_diagnostics_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _lri = '\u2066';
const _pdi = '\u2069';

class _FakeDiagnosticRepository implements GroupExitDiagnosticRepository {
  List<GroupExitDiagnostic> rows = <GroupExitDiagnostic>[];
  Object? loadError;
  Object? clearError;
  Future<List<GroupExitDiagnostic>> Function()? loadHandler;
  void Function()? afterClear;
  final calls = <String>[];

  @override
  Future<void> appendOutcome(List<GroupExitDiagnostic> diagnostics) async {
    calls.add('append');
    rows.addAll(diagnostics);
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    if (clearError case final error?) throw error;
    rows.clear();
    afterClear?.call();
  }

  @override
  Future<List<GroupExitDiagnostic>> loadForAction({
    required String groupId,
    required String intentId,
  }) async => List<GroupExitDiagnostic>.of(rows);

  @override
  Future<List<GroupExitDiagnostic>> loadNewest() async {
    calls.add('load');
    if (loadHandler case final handler?) return handler();
    if (loadError case final error?) throw error;
    return List<GroupExitDiagnostic>.of(rows);
  }
}

GroupExitDiagnostic _diagnostic(
  GroupExitDiagnosticPublicCode code, {
  required int id,
  String groupId = 'private-group-id',
  String intentId = 'private-intent-id',
}) {
  final kind = code == GroupExitDiagnosticPublicCode.ex10
      ? GroupExitDiagnosticKind.dissolvedShell
      : GroupExitDiagnosticKind.voluntary;
  final severity = switch (code) {
    GroupExitDiagnosticPublicCode.ex07 ||
    GroupExitDiagnosticPublicCode.ex08 ||
    GroupExitDiagnosticPublicCode.ex09 => GroupExitDiagnosticSeverity.warning,
    _ => GroupExitDiagnosticSeverity.failure,
  };
  final phase = switch (code) {
    GroupExitDiagnosticPublicCode.ex01 => GroupExitDiagnosticPhase.authority,
    GroupExitDiagnosticPublicCode.ex02 => GroupExitDiagnosticPhase.roleSync,
    GroupExitDiagnosticPublicCode.ex03 => GroupExitDiagnosticPhase.notice,
    GroupExitDiagnosticPublicCode.ex04 ||
    GroupExitDiagnosticPublicCode.ex05 ||
    GroupExitDiagnosticPublicCode.ex06 ||
    GroupExitDiagnosticPublicCode.ex99 => GroupExitDiagnosticPhase.native,
    GroupExitDiagnosticPublicCode.ex07 => GroupExitDiagnosticPhase.cleanup,
    GroupExitDiagnosticPublicCode.ex08 => GroupExitDiagnosticPhase.delivery,
    GroupExitDiagnosticPublicCode.ex09 => GroupExitDiagnosticPhase.rotation,
    GroupExitDiagnosticPublicCode.ex10 => GroupExitDiagnosticPhase.localDelete,
  };
  final reason = switch (code) {
    GroupExitDiagnosticPublicCode.ex01 =>
      GroupExitDiagnosticReason.authorityUnavailable,
    GroupExitDiagnosticPublicCode.ex02 =>
      GroupExitDiagnosticReason.roleSyncFailed,
    GroupExitDiagnosticPublicCode.ex03 =>
      GroupExitDiagnosticReason.noticePrepareFailed,
    GroupExitDiagnosticPublicCode.ex04 =>
      GroupExitDiagnosticReason.nodeNotInitialized,
    GroupExitDiagnosticPublicCode.ex05 =>
      GroupExitDiagnosticReason.nativeRejected,
    GroupExitDiagnosticPublicCode.ex06 =>
      GroupExitDiagnosticReason.nativeUncertain,
    GroupExitDiagnosticPublicCode.ex07 =>
      GroupExitDiagnosticReason.cleanupIncomplete,
    GroupExitDiagnosticPublicCode.ex08 =>
      GroupExitDiagnosticReason.noticeDeliveryDegraded,
    GroupExitDiagnosticPublicCode.ex09 =>
      GroupExitDiagnosticReason.rotationDeferred,
    GroupExitDiagnosticPublicCode.ex10 =>
      GroupExitDiagnosticReason.terminalShellCleanup,
    GroupExitDiagnosticPublicCode.ex99 => GroupExitDiagnosticReason.unexpected,
  };
  final diagnostic = GroupExitDiagnostic.create(
    occurredAt: DateTime.utc(2026, 7, 21, 9, id),
    groupId: groupId,
    intentId:
        code == GroupExitDiagnosticPublicCode.ex01 ||
            code == GroupExitDiagnosticPublicCode.ex02 ||
            code == GroupExitDiagnosticPublicCode.ex10
        ? null
        : intentId,
    kind: kind,
    severity: severity,
    phase: phase,
    publicCode: code,
    reason: reason,
  );
  return GroupExitDiagnostic.fromMap({...diagnostic.toMap(), 'id': id});
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      extensions: const [BackgroundReadableColors.dark],
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'PB266-13 release Settings discovery hides loading and empty but exposes '
    'initial error and nonempty history',
    (tester) async {
      final repository = _FakeDiagnosticRepository();
      final pending = Completer<List<GroupExitDiagnostic>>();
      repository.loadHandler = () => pending.future;

      await tester.pumpWidget(
        _app(
          GroupExitDiagnosticsSection(
            repository: repository,
            backgroundPreference: BackgroundPreference.defaultBackground,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('group-exit-diagnostics-loading-hidden')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-exit-diagnostics-open-row')),
        findsNothing,
      );

      pending.complete(const []);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-exit-diagnostics-empty-hidden')),
        findsOneWidget,
      );

      repository.loadHandler = null;
      repository.loadError = StateError('hostile database detail');
      await tester.pumpWidget(
        _app(
          GroupExitDiagnosticsSection(
            key: const ValueKey('error-instance'),
            repository: repository,
            backgroundPreference: BackgroundPreference.defaultBackground,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-exit-diagnostics-unavailable-row')),
        findsOneWidget,
      );
      expect(find.textContaining('hostile database detail'), findsNothing);

      repository
        ..loadError = null
        ..rows = [_diagnostic(GroupExitDiagnosticPublicCode.ex04, id: 1)];
      await tester.tap(
        find.byKey(const ValueKey('group-exit-diagnostics-unavailable-row')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-exit-diagnostics-open-row')),
        findsOneWidget,
      );
      expect(find.text('1 saved records'), findsOneWidget);
    },
  );

  testWidgets(
    'PB266-13 reload and clear are explicit retain data on failure and '
    'requery after clear',
    (tester) async {
      final old = _diagnostic(GroupExitDiagnosticPublicCode.ex04, id: 1);
      final reloaded = _diagnostic(GroupExitDiagnosticPublicCode.ex08, id: 2);
      final afterClear = _diagnostic(GroupExitDiagnosticPublicCode.ex10, id: 3);
      final repository = _FakeDiagnosticRepository()..rows = [old];

      await tester.pumpWidget(
        _app(
          GroupExitDiagnosticsSheet(
            repository: repository,
            initialDiagnostics: [old],
          ),
        ),
      );

      repository.rows = [reloaded];
      await tester.tap(
        find.byKey(const ValueKey('group-exit-diagnostics-reload')),
      );
      await tester.pump();
      expect(find.text('Group exit history reloaded.'), findsOneWidget);
      expect(find.text('${_lri}EX08$_pdi'), findsOneWidget);

      repository.loadError = StateError('private reload failure');
      await tester.tap(
        find.byKey(const ValueKey('group-exit-diagnostics-reload')),
      );
      await tester.pump();
      expect(
        find.text(
          'Couldn’t reload group exit history. Existing records are unchanged.',
        ),
        findsOneWidget,
      );
      expect(find.text('${_lri}EX08$_pdi'), findsOneWidget);
      expect(find.textContaining('private reload failure'), findsNothing);

      repository
        ..loadError = null
        ..clearError = StateError('private clear failure');
      await tester.tap(
        find.byKey(const ValueKey('group-exit-diagnostics-clear')),
      );
      await tester.pump();
      expect(
        find.text(
          'Couldn’t clear group exit history. Existing records are unchanged.',
        ),
        findsOneWidget,
      );
      expect(find.text('${_lri}EX08$_pdi'), findsOneWidget);

      repository
        ..clearError = null
        ..afterClear = () => repository.rows.add(afterClear);
      final callsBeforeClear = repository.calls.length;
      await tester.tap(
        find.byKey(const ValueKey('group-exit-diagnostics-clear')),
      );
      await tester.pump();
      expect(repository.calls.sublist(callsBeforeClear), ['clear', 'load']);
      expect(find.text('Group exit history cleared.'), findsOneWidget);
      expect(find.text('${_lri}EX10$_pdi'), findsOneWidget);
      expect(find.text('${_lri}EX08$_pdi'), findsNothing);

      expect(find.text(groupExitIntentRef('private-intent-id')), findsNothing);
      expect(find.textContaining('terminal_shell_cleanup'), findsNothing);
      expect(find.textContaining('private-group-id'), findsNothing);
      expect(
        find.textContaining(groupExitGroupRef('private-group-id')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PB266-14 all exit codes are isolated announced and overflow safe in '
    'en ar de',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final diagnostics = [
        for (var i = 0; i < GroupExitDiagnosticPublicCode.values.length; i++)
          _diagnostic(GroupExitDiagnosticPublicCode.values[i], id: i + 1),
      ];

      for (final locale in const [Locale('en'), Locale('ar'), Locale('de')]) {
        final repository = _FakeDiagnosticRepository()..rows = diagnostics;
        await tester.pumpWidget(
          _app(
            GroupExitDiagnosticsSheet(
              key: ValueKey(locale.languageCode),
              repository: repository,
              initialDiagnostics: diagnostics,
            ),
            locale: locale,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pump();

        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('group-exit-diagnostics-live-history')),
        );
        expect(
          semantics.getSemanticsData().flagsCollection.isLiveRegion,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('group-exit-diagnostic-11')),
          findsOneWidget,
        );

        for (final code in GroupExitDiagnosticPublicCode.values.reversed) {
          final finder = find.text('$_lri${code.code}$_pdi');
          for (
            var attempt = 0;
            finder.evaluate().isEmpty && attempt < 20;
            attempt++
          ) {
            await tester.drag(
              find.byKey(const ValueKey('group-exit-diagnostics-list')),
              const Offset(0, -180),
            );
            await tester.pump();
          }
          expect(finder, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
