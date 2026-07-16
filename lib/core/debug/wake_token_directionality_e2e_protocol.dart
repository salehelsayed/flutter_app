/// Host-safe protocol for the two-Android wake-token directionality campaign.
///
/// The physical issuer proves the token accepted by the real relay register
/// request. The emulator presenter independently proves the value persisted in
/// its production received-token store and the value attached at the accepted
/// production `inbox:store` boundary. Endpoint receipts contain hashes only.
const String wakeTokenDirectionalityScenarioId =
    'android.wake_token_directionality';
const String wakeTokenDirectionalityProfileId = 'android.e2e.wake_token';
const String wakeTokenIssuerRole = 'issuer';
const String wakeTokenPresenterRole = 'presenter';
const String wakeTokenIssuerAction = 'wake_token_issue_register';
const String wakeTokenPresenterAction = 'wake_token_store_attach';
const String wakeTokenIssuerRequestSchema =
    'mknoon.sims.wake-token-issuer-request.v1';
const String wakeTokenPresenterRequestSchema =
    'mknoon.sims.wake-token-presenter-request.v1';
const String wakeTokenEndpointResultSchema =
    'mknoon.sims.wake-token-endpoint-result.v1';
const String wakeTokenDurableEvidenceSchema =
    'mknoon.sims.wake-token-directionality-evidence.v1';

String wakeTokenIssuerStepId(String runId) => 'wake-token-issuer-$runId';

String wakeTokenPresenterStepId(String runId) => 'wake-token-presenter-$runId';

String wakeTokenAttachmentMessage(String runId, String nonce) =>
    '{"kind":"mknoon.sims.wake-token-directionality.v1",'
    '"runId":"$runId","nonce":"$nonce"}';

bool isWakeTokenDirectionalityAction(Object? value) =>
    value == wakeTokenIssuerAction || value == wakeTokenPresenterAction;
