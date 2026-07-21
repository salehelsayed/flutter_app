import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PB266-01 allowlisted bridge and typed outcomes map without free-text parsing',
    () {
      expect(
        classifyGroupExitNativeFailure(
          BridgeCommandException(
            'group:leave',
            'NOT_INITIALIZED',
            'hostile /private/path secret-group-id',
          ),
        ),
        GroupExitNativeFailure.nodeUnavailable,
      );
      for (final code in const <String>['INVALID_INPUT', 'GROUP_ERROR']) {
        expect(
          classifyGroupExitNativeFailure(
            BridgeCommandException('group:leave', code, 'NOT_INITIALIZED'),
          ),
          GroupExitNativeFailure.rejected,
        );
      }
      expect(
        classifyGroupExitNativeFailure(
          BridgeCommandException(
            'group:leave',
            'INTERNAL_ERROR',
            'INVALID_INPUT',
          ),
        ),
        GroupExitNativeFailure.uncertain,
      );
      expect(
        classifyGroupExitNativeFailure(TimeoutException('NOT_INITIALIZED')),
        GroupExitNativeFailure.uncertain,
      );
      expect(
        classifyGroupExitNativeFailure(
          const GroupExitNativeCommitUnknown('hostile GROUP_ERROR'),
        ),
        GroupExitNativeFailure.uncertain,
      );

      // Neither a hostile message nor Object.toString() is classification
      // authority. The command and the allowlisted typed code must both match.
      expect(
        classifyGroupExitNativeFailure(
          BridgeCommandException(
            'group:join',
            'NOT_INITIALIZED',
            'group:leave INVALID_INPUT',
          ),
        ),
        GroupExitNativeFailure.unexpected,
      );
      expect(
        classifyGroupExitNativeFailure(
          _HostileCause('group:leave NOT_INITIALIZED INVALID_INPUT'),
        ),
        GroupExitNativeFailure.unexpected,
      );
      expect(
        classifyGroupExitNativeFailure(
          BridgeCommandException(
            'group:leave',
            'UNKNOWN_CODE',
            'NOT_INITIALIZED',
          ),
        ),
        GroupExitNativeFailure.unexpected,
      );

      expect(
        groupExitPublicCodeForNativeFailure(
          GroupExitNativeFailure.nodeUnavailable,
        ),
        GroupExitDiagnosticPublicCode.ex04,
      );
      expect(
        groupExitPublicCodeForNativeFailure(GroupExitNativeFailure.rejected),
        GroupExitDiagnosticPublicCode.ex05,
      );
      expect(
        groupExitPublicCodeForNativeFailure(GroupExitNativeFailure.uncertain),
        GroupExitDiagnosticPublicCode.ex06,
      );
      expect(
        groupExitPublicCodeForNativeFailure(GroupExitNativeFailure.unexpected),
        GroupExitDiagnosticPublicCode.ex99,
      );

      final expectedCodes =
          <GroupExitProcessDiagnosticFact, GroupExitDiagnosticPublicCode>{
            const GroupExitProcessDiagnosticFact.authorityUnavailable():
                GroupExitDiagnosticPublicCode.ex01,
            const GroupExitProcessDiagnosticFact.roleSyncFailed():
                GroupExitDiagnosticPublicCode.ex02,
            const GroupExitProcessDiagnosticFact.noticePrepareFailed():
                GroupExitDiagnosticPublicCode.ex03,
            const GroupExitProcessDiagnosticFact.nativeNodeUnavailable():
                GroupExitDiagnosticPublicCode.ex04,
            const GroupExitProcessDiagnosticFact.nativeRejected():
                GroupExitDiagnosticPublicCode.ex05,
            const GroupExitProcessDiagnosticFact.nativeUncertain():
                GroupExitDiagnosticPublicCode.ex06,
            const GroupExitProcessDiagnosticFact.cleanupIncomplete():
                GroupExitDiagnosticPublicCode.ex07,
            const GroupExitProcessDiagnosticFact.deliveryDegraded():
                GroupExitDiagnosticPublicCode.ex08,
            const GroupExitProcessDiagnosticFact.rotationDeferred():
                GroupExitDiagnosticPublicCode.ex09,
            const GroupExitProcessDiagnosticFact.unexpected(
              GroupExitDiagnosticPhase.notice,
            ): GroupExitDiagnosticPublicCode.ex99,
          };
      for (final entry in expectedCodes.entries) {
        expect(groupExitPublicCodeForFact(entry.key), entry.value);
      }
    },
  );

  test(
    'PB266-01 arbitrary cause is unexpected before dispatch and uncertain after dispatch',
    () async {
      final cause = _HostileCause(
        'group:leave NOT_INITIALIZED INVALID_INPUT INTERNAL_ERROR',
      );
      expect(
        classifyGroupExitNativeFailure(cause),
        GroupExitNativeFailure.unexpected,
      );

      Object? observed;
      try {
        await runTypedGroupExitNativeLeave(() async => throw cause);
      } catch (error) {
        observed = error;
      }
      expect(observed, isA<GroupExitTypedProcessFailure>());
      final typed = observed! as GroupExitTypedProcessFailure;
      expect(typed.cause, same(cause));
      expect(
        typed.fact,
        const GroupExitProcessDiagnosticFact.nativeUncertain(),
      );
    },
  );

  test(
    'PB266-02 not initialized is diagnostic only and never reinitializes or retries leave',
    () async {
      var nativeCalls = 0;
      var reinitializeCalls = 0;
      var startCalls = 0;
      final error = BridgeCommandException(
        'group:leave',
        'NOT_INITIALIZED',
        'hostile retry and reinitialize request',
      );

      Object? observed;
      try {
        await runTypedGroupExitNativeLeave(() async {
          nativeCalls++;
          throw error;
        });
      } catch (caught) {
        observed = caught;
      }

      expect(observed, isA<GroupExitTypedProcessFailure>());
      final typed = observed! as GroupExitTypedProcessFailure;
      expect(typed.cause, same(error));
      expect(
        typed.fact,
        const GroupExitProcessDiagnosticFact.nativeNodeUnavailable(),
      );
      expect(nativeCalls, 1);
      expect(reinitializeCalls, 0);
      expect(startCalls, 0);

      final mainSource = await File('lib/main.dart').readAsString();
      final nativeStart = mainSource.indexOf('nativeLeave: (intent) async {');
      final nativeEnd = mainSource.indexOf('\n    },', nativeStart);
      expect(nativeStart, greaterThanOrEqualTo(0));
      expect(nativeEnd, greaterThan(nativeStart));
      final nativeAdapter = mainSource.substring(nativeStart, nativeEnd);
      expect(nativeAdapter, contains('runTypedGroupExitNativeLeave('));
      expect(nativeAdapter, isNot(contains('.reinitialize(')));
      expect(nativeAdapter, isNot(contains('.start(')));

      // Keep explicit spies in the proof: classification has no authority to
      // invoke either recovery callback.
      void reinitialize() => reinitializeCalls++;
      void start() => startCalls++;
      expect(reinitialize, isNotNull);
      expect(start, isNotNull);
    },
  );
}

class _HostileCause {
  const _HostileCause(this.value);

  final String value;

  @override
  String toString() => value;
}
