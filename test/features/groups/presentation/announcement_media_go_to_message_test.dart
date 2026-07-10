import 'dart:async';

import 'package:flutter_app/features/groups/application/group_shared_media_navigation.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'AML-05 production route repeats old targets safely across load race and resume',
    () async {
      final repository = _DeferredAroundRepository();
      final coordinator = GroupSharedMediaAnchorRequestCoordinator();
      final older = coordinator.load(
        repository: repository,
        currentGroupId: 'announcement-a',
        requestedGroupId: 'announcement-a',
        messageId: 'old',
      );
      final newer = coordinator.load(
        repository: repository,
        currentGroupId: 'announcement-a',
        requestedGroupId: 'announcement-a',
        messageId: 'new',
      );
      repository.completers[1].complete([_message('new')]);
      expect((await newer)!.single.id, 'new');
      repository.completers[0].complete([_message('old')]);
      expect(await older, isNull);

      final repeated = coordinator.load(
        repository: repository,
        currentGroupId: 'announcement-a',
        requestedGroupId: 'announcement-a',
        messageId: 'old',
      );
      repository.completers[2].complete([_message('old')]);
      expect((await repeated)!.single.id, 'old');
    },
  );

  test(
    'AML-06 invalid or stale route targets fail closed without wrong highlight',
    () async {
      final repository = _DeferredAroundRepository();
      expect(
        await loadGroupSharedMediaAnchorWindow(
          repository: repository,
          currentGroupId: 'announcement-a',
          requestedGroupId: 'announcement-b',
          messageId: 'target',
        ),
        isEmpty,
      );
      expect(repository.completers, isEmpty);
    },
  );
}

GroupMessage _message(String id) => GroupMessage(
  id: id,
  groupId: 'announcement-a',
  senderPeerId: 'peer',
  text: id,
  timestamp: DateTime.utc(2026, 7, 10),
  isIncoming: true,
  createdAt: DateTime.utc(2026, 7, 10),
);

class _DeferredAroundRepository
    implements GroupMessageRepository, GroupMessageAroundRepository {
  final List<Completer<List<GroupMessage>>> completers = [];

  @override
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  }) {
    final completer = Completer<List<GroupMessage>>();
    completers.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
