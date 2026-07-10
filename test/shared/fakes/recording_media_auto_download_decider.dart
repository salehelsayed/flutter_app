import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

/// One recorded policy consultation (229).
class RecordedAutoDownloadRequest {
  const RecordedAutoDownloadRequest({
    required this.conversationKind,
    required this.storageOwner,
    required this.mediaType,
    required this.downloadStatus,
    required this.userInitiated,
    required this.isProtected,
  });

  final MediaConversationKind conversationKind;
  final MediaOwnerLane? storageOwner;
  final String mediaType;
  final String downloadStatus;
  final bool userInitiated;
  final bool isProtected;
}

/// Recording [MediaAutoDownloadDecider] fake shared by the 229 direct/group
/// wiring tests. Returns [allow] for every consultation and records the full
/// request so tests can pin conversation kind, storage owner, media type and
/// status at the exact moment of the decision.
class RecordingMediaAutoDownloadDecider implements MediaAutoDownloadDecider {
  RecordingMediaAutoDownloadDecider({this.allow = true});

  bool allow;
  final List<RecordedAutoDownloadRequest> requests = [];

  @override
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  }) async {
    requests.add(
      RecordedAutoDownloadRequest(
        conversationKind: conversationKind,
        storageOwner: storageOwner,
        mediaType: mediaType,
        downloadStatus: downloadStatus,
        userInitiated: userInitiated,
        isProtected: isProtected,
      ),
    );
    return allow;
  }
}
