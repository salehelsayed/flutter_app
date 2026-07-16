/// Pure, host-safe protocol values shared by the production main-app observer
/// and the build-free Android campaign adapter.
const String connectivityRestoreScenarioId =
    'android.connectivity_restore_inbox_drain';
const String connectivityRestoreObserveAction = 'connectivity_restore_observe';
const String connectivityRestoreObserveRequestSchema =
    'mknoon.sims.connectivity-restore-window-request.v1';
const String connectivityRestoreObserveResultSchema =
    'mknoon.sims.connectivity-restore-observation.v1';

List<String> connectivityRestoreExpectedTexts(String runId) =>
    List<String>.unmodifiable(
      List<String>.generate(
        3,
        (index) => 'SIMS connectivity restore $runId message ${index + 1}/3',
      ),
    );

String connectivityRestoreSendStepId(String runId) =>
    'connectivity-send-$runId';
