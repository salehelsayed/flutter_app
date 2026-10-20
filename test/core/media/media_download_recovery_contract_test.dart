import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_download_recovery_registry.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

void main() {
  test('every retryable receive status has an honest, wired recovery owner', () {
    final policy = File(
      'lib/core/media/group_media_integrity_policy.dart',
    ).readAsStringSync();
    final declared = RegExp(
      r"const String kMediaDownloadStatus\w+ = '([^']+)';",
    ).allMatches(policy).map((match) => match.group(1)!).toSet();
    const unowned = MediaAttachment(
      id: 'unowned',
      messageId: 'message',
      mime: 'image/jpeg',
      size: 4096,
      mediaType: 'image',
      downloadStatus: kMediaDownloadStatusFailed,
      createdAt: '2026-10-20T00:00:00Z',
    );
    expect(
      GroupMediaIntegrityPolicy.isUnavailableMedia(unowned),
      isTrue,
      reason:
          'an unowned adapter has no registered direct/group recovery owner',
    );
    for (final owner in MediaOwnerLane.values) {
      for (final status in declared) {
        final attachment = MediaAttachment(
          id: 'blob',
          messageId: 'message',
          mime: 'image/jpeg',
          size: 4096,
          mediaType: 'image',
          downloadStatus: status,
          ownerLane: owner,
          createdAt: '2026-10-20T00:00:00Z',
          downloadRetryCount: 0,
        );
        final retryable =
            {
              kMediaDownloadStatusPending,
              kMediaDownloadStatusDownloading,
            }.contains(status) ||
            GroupMediaIntegrityPolicy.isRetryableDownloadFailure(attachment);
        if (retryable) {
          expect(
            mediaDownloadRecoveryOwners[status],
            contains(owner),
            reason: '$owner $status needs a durable owner',
          );
        }
        if (mediaDownloadRecoveryOwners[status]?.contains(owner) ?? false) {
          expect(
            GroupMediaIntegrityPolicy.isUnavailableMedia(attachment),
            isFalse,
            reason:
                '$owner $status is recovery work, not proven unavailability',
          );
        }
      }
    }
    final bootstrap = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final root = File('lib/app/application_root.dart').readAsStringSync();
    final resume = File(
      'lib/app/lifecycle/handle_app_resumed.dart',
    ).readAsStringSync();
    final retrier = File(
      'lib/core/services/pending_message_retrier.dart',
    ).readAsStringSync();
    final restored = retrier.substring(
      retrier.indexOf('Future<void> _flushUnackedOnNetworkRestored()'),
      retrier.indexOf('void _scheduleDirectUploadRetry()'),
    );
    expect(bootstrap, matches(RegExp(r'loadRetryableMediaMessageIds:\s*\(')));
    expect(
      RegExp(
        r'dbLoadRetryableDirectMediaMessageIds\(\s*db',
      ).hasMatch(bootstrap),
      isTrue,
      reason: 'direct page loader wired',
    );
    expect(
      bootstrap,
      matches(
        RegExp(r'chatMessageListener\s*\.\s*retryIncompleteMediaDownloads\('),
      ),
    );
    expect(
      root,
      contains(
        'drainDirectMediaBlobCustodyFn: widget.drainDirectMediaBlobCustody',
      ),
    );
    expect(resume.contains('await drainDirectMediaBlobCustodyFn()'), isTrue);
    expect(restored.contains('await _drainDirectMediaBlobCustody()'), isTrue);
    expect(
      bootstrap.contains('action: groupMediaDownloadCoordinator.call'),
      isTrue,
    );
    expect(
      root,
      matches(
        RegExp(
          r'retryIncompleteGroupDownloadsFn:\s*widget.groupMediaDownloadCoordinator\?\.call',
        ),
      ),
    );
    expect(resume.contains('await retryIncompleteGroupDownloadsFn()'), isTrue);
    expect(restored.contains('retryIncompleteGroupDownloadsFn'), isTrue);
    expect(restored.contains('await retryGroupDownloads()'), isTrue);
  });
}
