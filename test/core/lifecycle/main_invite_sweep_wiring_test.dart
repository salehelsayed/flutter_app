import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
  test(
    'main.dart schedules an unawaited startup group-invite sweep next to the post sweep',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();

      // Startup: fire-and-forget, reusing the top-level repo handle, with a
      // dedicated catchError so a sweep failure never blocks startup.
      final startupInviteSweep = RegExp(
        r'unawaited\(\s*sweepExpiredGroupInvites\(\s*repo:\s*pendingGroupInviteRepository,?\s*\)\.catchError\(',
      ).hasMatch(mainSource);
      expect(
        startupInviteSweep,
        isTrue,
        reason: 'startup must schedule an unawaited group-invite sweep',
      );
      expect(mainSource, contains("event: 'GROUP_INVITE_SWEEP_STARTUP_ERROR'"));
      expect(mainSource, contains('return GroupInviteSweepResult.empty;'));
    },
  );

  test(
    'main.dart awaits a group-invite sweep last in the resume path (after the post sweep)',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();

      // Resume: awaited, placed after the post sweep and before
      // checkResumeAlreadyOnline so the 7d invite TTL never races recovery.
      final postSweep = mainSource.indexOf(
        'await sweepExpiredPosts(\n        postRepo: widget.postRepository,',
      );
      expect(postSweep, isNonNegative);

      final inviteSweep = mainSource.indexOf(
        'await sweepExpiredGroupInvites(\n        repo: widget.groupInviteListener.pendingInviteRepo,\n      );',
        postSweep,
      );
      expect(
        inviteSweep,
        greaterThan(postSweep),
        reason: 'resume invite sweep must run after the post sweep',
      );

      final checkOnline = mainSource.indexOf(
        'widget.p2pService.checkResumeAlreadyOnline();',
        postSweep,
      );
      expect(checkOnline, greaterThan(inviteSweep));
    },
  );
}
