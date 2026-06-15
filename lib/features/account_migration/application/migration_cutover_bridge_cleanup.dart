import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';

MigrationCutoverLeaseCleanup buildBridgeMigrationCutoverLeaseCleanup({
  required Bridge bridge,
  required Future<void> Function() clearLocalStalePushToken,
  Future<void> Function()? stopLocalRuntime,
  String? namespace,
  List<String>? serverAddresses,
}) {
  return MigrationCutoverLeaseCleanup(
    clearLocalStalePushToken: clearLocalStalePushToken,
    stopLocalRuntime: stopLocalRuntime,
    unregisterPersonalRendezvous: () async {
      final response = await callP2PRendezvousUnregister(
        bridge,
        namespace: namespace,
        serverAddresses: serverAddresses,
      );
      if (response['ok'] != true) {
        throw StateError('rendezvous unregister failed');
      }
    },
    unregisterInboxPushToken: () async {
      final response = await callP2PInboxUnregisterToken(
        bridge,
        serverAddresses: serverAddresses,
      );
      if (response['ok'] != true) {
        throw StateError('inbox push-token unregister failed');
      }
    },
  );
}
