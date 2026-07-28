import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
  test(
    'production post-launch phase schedules an unawaited group-invite sweep',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();

      // Startup: fire-and-forget, reusing the top-level repo handle, with a
      // dedicated catchError so a sweep failure never blocks startup.
      final startupInviteSweep = RegExp(
        r'unawaited\(\s*sweepExpiredGroupInvites\(\s*repo:\s*pendingGroupInviteRepository,?\s*\)\.catchError\(',
      ).hasMatch(productionSource);
      expect(
        startupInviteSweep,
        isTrue,
        reason: 'startup must schedule an unawaited group-invite sweep',
      );
      expect(
        productionSource,
        contains("event: 'GROUP_INVITE_SWEEP_STARTUP_ERROR'"),
      );
      expect(
        productionSource,
        contains('return GroupInviteSweepResult.empty;'),
      );
    },
  );

  test('application root awaits a group-invite sweep last on resume', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final applicationRootSource = await File(
      'lib/app/application_root.dart',
    ).readAsString();

    // Resume: awaited, placed after the post sweep and before
    // checkResumeAlreadyOnline so the 7d invite TTL never races recovery.
    final postSweep = applicationRootSource.indexOf(
      'await sweepExpiredPosts(\n        postRepo: widget.postRepository,',
    );
    expect(postSweep, isNonNegative);

    final inviteSweep = applicationRootSource.indexOf(
      'await sweepExpiredGroupInvites(\n        repo: widget.groupInviteListener.pendingInviteRepo,\n      );',
      postSweep,
    );
    expect(
      inviteSweep,
      greaterThan(postSweep),
      reason: 'resume invite sweep must run after the post sweep',
    );

    final checkOnline = applicationRootSource.indexOf(
      'widget.p2pService.checkResumeAlreadyOnline();',
      postSweep,
    );
    expect(checkOnline, greaterThan(inviteSweep));
  });
}
