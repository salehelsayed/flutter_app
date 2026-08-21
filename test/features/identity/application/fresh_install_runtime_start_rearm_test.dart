import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/app/bootstrap/role_aware_deferred_runtime_start.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

/// Fresh-install onboarding sequence, reproduced at the orchestration layer.
///
/// Device-observed 2026-08-21 (iPhone 11): on a fresh install the app shows
/// "Offline" forever after onboarding creates the identity, because
/// `StartupRouter._doStartP2P` awaits `ensureRuntimeServicesReady()` and that
/// await never returns, so `startP2PNode` is never reached. A relaunch — where
/// the identity already exists at boot — comes up Online in 189 ms.
///
/// The device trace proves attempt #1 (no identity yet) settles correctly:
///   RUNTIME_LATCH_BEGIN -> ROLE_AWARE_RUNTIME_START_BEGIN
///   -> RUNTIME_LATCH_JOIN_EXISTING        (a second caller joins in-flight)
///   -> ROLE_AWARE_RUNTIME_START_DEFERRED_NO_IDENTITY
///   -> RUNTIME_LATCH_SETTLED {started:false}
/// These tests pin what must happen on attempt #2, after the identity commits.
void main() {
  late bool identityExists;
  late int primaryStarts;

  RoleAwareDeferredRuntimeStart buildRoleAware() {
    return RoleAwareDeferredRuntimeStart(
      hasIdentity: () async => identityExists,
      loadLinkedAuthority: () async =>
          const LinkedInstallationAuthoritySnapshot(
            disposition: LinkedInstallationDisposition.primary,
            credential: null,
            failClosedReason: null,
          ),
      startPrimaryRuntimeServices: () async {
        primaryStarts += 1;
        return true;
      },
      startLinkedFoundationPrerequisites: () async => false,
    );
  }

  setUp(() {
    identityExists = false;
    primaryStarts = 0;
  });

  test(
    'latch re-arms after a no-identity attempt and starts on the next call',
    () async {
      final roleAware = buildRoleAware();
      final latch = AccountMigrationRuntimeStartupLatch(
        startRuntime: roleAware.start,
      );

      // Attempt #1: MyApp.initState fires before onboarding commits.
      await latch.ensureStarted();
      expect(primaryStarts, 0, reason: 'no identity yet');

      // Onboarding commits the identity.
      identityExists = true;

      // Attempt #2: StartupRouter._doStartP2P awaits this before startP2PNode.
      await latch.ensureStarted().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail(
          'ensureStarted() never returned after the identity committed — '
          'this is the device hang: startP2PNode is never reached and the '
          'connection badge stays "Offline" until the app is relaunched.',
        ),
      );
      expect(primaryStarts, 1, reason: 'runtime services must start');
    },
  );

  test(
    'a second caller that JOINS the in-flight no-identity attempt still '
    'gets a latch that re-arms (device trace shows RUNTIME_LATCH_JOIN_EXISTING)',
    () async {
      final roleAware = buildRoleAware();
      final latch = AccountMigrationRuntimeStartupLatch(
        startRuntime: roleAware.start,
      );

      // Two concurrent callers, exactly as on device: initState fires one and
      // a second joins the in-flight future before it settles.
      final first = latch.ensureStarted();
      final joined = latch.ensureStarted();
      await Future.wait([first, joined]);
      expect(primaryStarts, 0);

      identityExists = true;

      await latch.ensureStarted().timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            fail('ensureStarted() hung after a joined no-identity attempt'),
      );
      expect(primaryStarts, 1);
    },
  );
}
