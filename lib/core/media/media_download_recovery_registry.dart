import 'group_media_integrity_policy.dart';
import 'media_owner_lane.dart';

/// Existing durable receive recovery owners; this is a wiring contract,
/// not another dispatcher or retry service. Parent and user policy still gate
/// whether a registered candidate may transfer.
const mediaDownloadRecoveryOwners = <String, Set<MediaOwnerLane>>{
  kMediaDownloadStatusPending: {MediaOwnerLane.direct, MediaOwnerLane.group},
  kMediaDownloadStatusDownloading: {
    MediaOwnerLane.direct,
    MediaOwnerLane.group,
  },
  kMediaDownloadStatusFailed: {MediaOwnerLane.direct, MediaOwnerLane.group},
  kMediaDownloadStatusRetryWaiting: {MediaOwnerLane.direct},
  kMediaDownloadStatusNotFoundRetry1: {
    MediaOwnerLane.direct,
    MediaOwnerLane.group,
  },
  kMediaDownloadStatusNotFoundRetry2: {
    MediaOwnerLane.direct,
    MediaOwnerLane.group,
  },
  kMediaDownloadStatusNotFoundRetry3: {
    MediaOwnerLane.direct,
    MediaOwnerLane.group,
  },
};
