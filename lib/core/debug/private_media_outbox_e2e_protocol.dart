/// Host-safe constants for the production private-media outbox device proof.
///
/// Keep this file free of Flutter and plugin imports so the bare-Dart SIMS
/// adapter can share the exact request/result and event vocabulary.
const String privateMediaOutboxE2EAction = 'private_media_outbox_e2e';
const String privateMediaOutboxE2ERequestSchema =
    'mknoon.sims.private-media-outbox-request.v1';
const String privateMediaOutboxE2EEndpointResultSchema =
    'mknoon.sims.private-media-outbox-endpoint.v1';
const String privateMediaOutboxE2EHostReleaseSchema =
    'mknoon.sims.private-media-outbox-host-release.v1';
const String privateMediaOutboxE2EHostReleaseFileName =
    'private_media_outbox_e2e_host_release.json';
const String privateMediaOutboxE2EScenario =
    'android.connectivity_restore_media_outbox';
const String privateMediaOutboxE2EBuildProfile = 'android.e2e.main';
const String privateMediaOutboxSenderRole = 'sender';
const String privateMediaOutboxReceiverRole = 'receiver';
const String privateMediaOutboxSenderOfflineRelease = 'sender_offline';
const String privateMediaOutboxConversationReadyCondition =
    'conversation identity and media dependencies';
const String privateMediaOutboxOfflineLifecycleCondition =
    'offline background and foreground cycle';

const String privateMediaOutboxNetworkRestoredEvent =
    'PENDING_RETRIER_NETWORK_RESTORED_TRIGGER';
const String privateMediaOutboxLeaseClaimedEvent = 'MEDIA_UPLOAD_LEASE_CLAIMED';
const String privateMediaOutboxEncryptionPreparedEvent =
    'MEDIA_ENCRYPTION_PREPARED';
const String privateMediaOutboxUploadStartEvent = 'MEDIA_UPLOAD_START';
const String privateMediaOutboxSendSuccessEvent = 'CHAT_MSG_SEND_SUCCESS';
const String privateMediaOutboxReceivedEvent =
    'PRIVATE_MEDIA_OUTBOX_E2E_RECEIVED';
const String privateMediaOutboxNetworkRestoredSource = 'network_restored';
