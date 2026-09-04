import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/linked_group_conversation_wired.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  test(
    'linked-group voice arming owns lease before admission awaits',
    () async {
      final recorder = FakeAudioRecorderService();
      addTearDown(recorder.dispose);
      final identity = Completer<LinkedGroupMediaAuthorIdentity?>();
      final owner = _owner(recorder, loadIdentity: () => identity.future);
      final leases = microphoneCaptureLeasesFor(recorder);

      final arming = owner.startVoiceRecording('group-1');

      expect(leases.acquire, throwsA(isA<MicrophoneCaptureLeaseRefused>()));
      identity.complete(null);
      expect(await arming, isFalse);
      leases.acquire().release();
    },
  );

  test('call lease rejects linked-group voice before admission work', () async {
    final recorder = FakeAudioRecorderService();
    addTearDown(recorder.dispose);
    final leases = microphoneCaptureLeasesFor(recorder);
    final callLease = leases.acquire();
    var identityReads = 0;
    final owner = _owner(
      recorder,
      loadIdentity: () async {
        identityReads++;
        return null;
      },
    );

    expect(await owner.startVoiceRecording('group-1'), isFalse);
    expect(identityReads, 0);
    callLease.release();
  });
}

LinkedGroupMediaVoiceActionOwner _owner(
  AudioRecorderService recorder, {
  required Future<LinkedGroupMediaAuthorIdentity?> Function() loadIdentity,
}) => LinkedGroupMediaVoiceActionOwner(
  bridge: _UnusedBridge(),
  groupRepository: _UnusedGroupRepository(),
  messageRepository: _UnusedGroupMessageRepository(),
  mediaAttachmentRepository: _UnusedMediaAttachmentRepository(),
  preparedCustodyCoordinator: PreparedGroupMediaBlobCustodyCoordinator(
    artifactStore: GroupMediaBlobArtifactStore(),
  ),
  loadIdentity: loadIdentity,
  retryStrictOutgoing: () async => 0,
  retryStrictIncoming: () async => 0,
  refreshProjection: () async {},
  audioRecorderService: recorder,
);

final class _UnusedBridge extends Fake implements Bridge {}

final class _UnusedGroupRepository extends Fake implements GroupRepository {}

final class _UnusedGroupMessageRepository extends Fake
    implements GroupMessageRepository {}

final class _UnusedMediaAttachmentRepository extends Fake
    implements MediaAttachmentRepository {}
