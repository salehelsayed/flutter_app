/// Pure-Dart request/result contract shared by the debug-only app action and
/// the host-side Sims campaign.
const String androidDirectMediaBlobCustodyE2EAction =
    'direct_media_blob_custody_e2e';
const String androidDirectMediaBlobCustodyE2ERequestSchema =
    'mknoon.sims.android-direct-media-blob-custody-request.v1';
const String androidDirectMediaBlobCustodyE2EEndpointResultSchema =
    'mknoon.sims.android-direct-media-blob-custody-endpoint.v1';
const String androidDirectMediaBlobCustodyE2EScenario =
    'android.direct_media_blob_custody';
const String androidDirectMediaBlobCustodyE2EBuildProfile =
    'android.e2e.direct_media_custody';

const String androidDirectMediaBlobCustodySenderRole = 'sender';
const String androidDirectMediaBlobCustodyReceiverRole = 'receiver';

const String androidDirectMediaBlobCustodyReceiverArmPhase = 'receiver_arm';
const String androidDirectMediaBlobCustodySenderPreparePhase =
    'sender_prepare_pause';
const String androidDirectMediaBlobCustodySenderResumePhase = 'sender_resume';
const String androidDirectMediaBlobCustodyReceiverReopenPhase =
    'receiver_reopen';

String androidDirectMediaBlobCustodyStepId({
  required String role,
  required String phase,
  required String runId,
}) => 'direct-media-custody-$role-$phase-$runId';
