import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'production_journey_controller.dart';
import 'sims_runtime_protocol.dart';

/// The retained sound campaign's nine encrypted projection fixtures. This is
/// deliberately not a blob-transfer fixture or a general send command.
final class ProductionSoundDescriptorClaims {
  final Set<int> _claimed = {};

  MediaAttachment claim(SimsRuntimeInvocation invocation, String caseId) {
    final number = int.tryParse(
      caseId.startsWith('S') ? caseId.substring(1) : '',
    );
    if (invocation.scenarioId != notificationSoundJourney ||
        invocation.role != 'alice' ||
        number == null ||
        number < 5 ||
        number > 13 ||
        caseId != 'S$number' ||
        invocation.values['fixtureId'] != invocation.runId ||
        !_claimed.add(number)) {
      throw StateError('sound descriptor claim rejected');
    }
    final type = ['image', 'video', 'audio'][(number - 5) % 3];
    final signal = caseId.toLowerCase();
    return MediaAttachment(
      id: 'notification-${invocation.runId}-$signal',
      messageId: 'notification-${invocation.runId}-$signal-message',
      mime: type == 'image' ? 'image/jpeg' : '$type/mp4',
      size: 4096,
      mediaType: type,
      width: type != 'audio' ? 640 : null,
      height: type != 'audio' ? 480 : null,
      durationMs: type != 'image' ? 3200 : null,
      localPath: 'media/notification_sound/$signal',
      downloadStatus: 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      waveform: type == 'audio' ? const [0.1, 0.4, 0.2] : null,
      contentHash: '${number - 4}' * 64,
      encryptionKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      encryptionNonce: 'AAAAAAAAAAAAAAAA',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
  }
}
