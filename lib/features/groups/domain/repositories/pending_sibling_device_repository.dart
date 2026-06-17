import '../models/pending_sibling_device.dart';

/// R2: optional repository capability for same-user sibling devices awaiting a
/// user trust decision before admission. Implemented by the group repository
/// (mixin), consumed by the listener hold seam + the trust-prompt UI.
abstract class PendingSiblingDeviceRepository {
  Future<void> savePendingSiblingDevice(PendingSiblingDevice device);

  Future<List<PendingSiblingDevice>> getPendingSiblingDevicesForGroup(
    String groupId,
  );

  Future<PendingSiblingDevice?> getPendingSiblingDevice(
    String groupId,
    String memberPeerId,
    String deviceId,
  );

  Future<void> deletePendingSiblingDevice(
    String groupId,
    String memberPeerId,
    String deviceId,
  );
}
