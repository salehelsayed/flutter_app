import 'dart:async';

import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';

({Future<ActiveIdentityReporter?> reporter, Future<void> Function() dispose})
prepareProductionActiveIdentityReporter({
  required String documentsPath,
  Future<EngagementChatCheckpointStore> Function(String privateDirectory)?
  openGroupWitnessStore,
  int Function()? groupNowMilliseconds,
  Future<EngagementChatCheckpointStore> Function(String privateDirectory)?
  openChatWitnessStore,
  int Function()? chatNowMilliseconds,
}) {
  const budget = Duration(seconds: 2);
  var retired = false;
  EngagementChatCheckpointStore? groupStore;
  EngagementChatCheckpointStore? chatStore;
  ActiveIdentityReporter? activeReporter;
  Future<EngagementChatCheckpointStore?> openStore(
    Future<EngagementChatCheckpointStore> Function(String) opener,
    String privateDirectory,
  ) async {
    final opening = Future<EngagementChatCheckpointStore>.sync(
      () => opener(privateDirectory),
    );
    try {
      return await opening.timeout(budget);
    } on Object {
      // A timed-out open must never attach to a later or retired owner.
      unawaited(
        opening
            .then<void>(
              (store) => store.close(),
              onError: (Object _, StackTrace __) {},
            )
            .catchError((Object _) {}),
      );
    }
    return null;
  }

  Future<ActiveIdentityReporter?> prepare() async {
    // Independent optional stores share the existing wall-clock open budget.
    final stores = await Future.wait([
      openStore(
        openGroupWitnessStore ?? EngagementChatCheckpointStore.open,
        '$documentsPath/active_identity/group',
      ),
      openStore(
        openChatWitnessStore ?? EngagementChatCheckpointStore.open,
        '$documentsPath/active_identity/chat',
      ),
    ]);
    groupStore = stores[0];
    chatStore = stores[1];
    if (retired) return null;
    return activeReporter = ActiveIdentityReporter(
      statePath: '$documentsPath/active_identity/state.json',
      groupWitnessStore: groupStore,
      groupNowMilliseconds: groupNowMilliseconds,
      chatWitnessStore: chatStore,
      chatNowMilliseconds: chatNowMilliseconds,
    );
  }

  final ready = prepare();
  Future<void>? disposal;
  Future<void> cleanup(Future<void>? retiring) async {
    try {
      if (retiring != null) {
        await retiring;
      } else {
        final reporter = await ready;
        await reporter?.dispose();
      }
    } finally {
      try {
        await groupStore?.close();
      } finally {
        await chatStore?.close();
      }
    }
  }

  Future<void> dispose() {
    retired = true;
    // Retire a published reporter synchronously, before waiting for cleanup.
    return disposal ??= cleanup(activeReporter?.dispose()).timeout(
      budget,
      // The physical cleanup continues and keeps its existing writer fence.
      // Optional diagnostics cannot hold runtime shutdown indefinitely.
      onTimeout: () {},
    );
  }

  return (reporter: ready, dispose: dispose);
}
