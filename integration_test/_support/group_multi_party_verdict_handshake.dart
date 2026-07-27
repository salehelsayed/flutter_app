/// Logical signal written by the host after it has captured [role]'s verdict.
String groupMultiPartyVerdictHostCapturedSignalName(String role) =>
    '${role}_verdict_host_captured';

/// Publishes a role verdict and, when required, keeps the harness alive until
/// the host confirms that the verdict has left the app-private sandbox.
Future<void> writeGroupMultiPartyVerdictAndAwaitHostCapture({
  required String role,
  required bool requireHostCapture,
  required void Function() writeVerdict,
  required Future<void> Function(String signalName) waitForSignal,
}) async {
  writeVerdict();
  if (!requireHostCapture) return;
  await waitForSignal(groupMultiPartyVerdictHostCapturedSignalName(role));
}

/// Captures every role verdict before quiescing the broker and releasing any
/// strict Android harness.
///
/// Keeping acknowledgements behind the all-verdict and final-sync barriers
/// prevents an early role uninstall from breaking signal exchange needed by a
/// later role. Once the broker is stopped, acknowledgements are delivered
/// target-only in role order.
Future<List<T>> captureGroupMultiPartyVerdictsAtTerminalBarrier<T>({
  required Iterable<String> roles,
  required bool acknowledgeHostCapture,
  required Future<T> Function(String role) captureVerdict,
  required Future<void> Function() synchronizeHeldRoles,
  required Future<void> Function() stopSignalBroker,
  required Future<void> Function(String role, String signalName)
  deliverAcknowledgement,
  required Future<void> Function(String role) awaitRoleExit,
}) async {
  final orderedRoles = List<String>.of(roles);
  final verdicts = await Future.wait<T>(orderedRoles.map(captureVerdict));
  if (acknowledgeHostCapture) {
    await synchronizeHeldRoles();
    await stopSignalBroker();
    for (final role in orderedRoles) {
      await deliverAcknowledgement(
        role,
        groupMultiPartyVerdictHostCapturedSignalName(role),
      );
    }
  }
  for (final role in orderedRoles) {
    await awaitRoleExit(role);
  }
  return verdicts;
}
