import 'package:flutter/foundation.dart';

/// Where the one on-device translator download stands. The Thought and voice
/// links, the download sheet and the Settings row all render from this.
sealed class ModelDeliveryState {
  const ModelDeliveryState();
}

/// This phone cannot run the model. Nothing is offered.
final class ModelUnsupported extends ModelDeliveryState {
  const ModelUnsupported();
}

final class ModelNotDownloaded extends ModelDeliveryState {
  const ModelNotDownloaded({
    required this.totalBytes,
    required this.freeBytes,
    required this.onWifi,
  });

  final int totalBytes;
  final int freeBytes;
  final bool onWifi;
}

final class ModelNotEnoughSpace extends ModelDeliveryState {
  const ModelNotEnoughSpace({
    required this.totalBytes,
    required this.neededBytes,
    required this.freeBytes,
  });

  final int totalBytes;

  /// The download plus the room needed to unpack it.
  final int neededBytes;
  final int freeBytes;
}

/// A started download that has received part of the file.
sealed class ModelDeliveryInProgress extends ModelDeliveryState {
  const ModelDeliveryInProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  int get percent =>
      totalBytes <= 0 ? 0 : (receivedBytes * 100 ~/ totalBytes).clamp(0, 100);
}

final class ModelDownloading extends ModelDeliveryInProgress {
  const ModelDownloading({
    required super.receivedBytes,
    required super.totalBytes,
    this.remaining,
  });

  /// Null until the controller has a stable estimate.
  final Duration? remaining;
}

/// Queued or interrupted because only mobile data is available and the user
/// has not allowed it.
final class ModelWaitingForWifi extends ModelDeliveryInProgress {
  const ModelWaitingForWifi({
    required super.receivedBytes,
    required super.totalBytes,
  });
}

/// Stopped by the user, or by a restart, with the part already received kept.
final class ModelPaused extends ModelDeliveryInProgress {
  const ModelPaused({required super.receivedBytes, required super.totalBytes});
}

/// The silent retries ran out (broken file or server error).
final class ModelFailed extends ModelDeliveryState {
  const ModelFailed();
}

final class ModelReady extends ModelDeliveryState {
  const ModelReady({required this.sizeBytes});

  final int sizeBytes;
}

/// The download logic the translator UI drives. The UI depends only on this
/// file.
abstract class ModelDeliveryController {
  ValueListenable<ModelDeliveryState> get state;

  /// The Settings "Download over mobile data" switch.
  ValueListenable<bool> get allowMobileData;

  Future<void> setAllowMobileData(bool allow);

  /// Rechecks available space and connectivity without starting or resuming.
  Future<void> refresh();

  Future<void> start({required bool allowMobileData});

  Future<void> pause();

  Future<void> resume();

  Future<void> retry();

  Future<void> remove();
}

@visibleForTesting
ModelDeliveryController? debugModelDeliveryOverride;

/// Null until the download logic is wired in. The links then behave as if the
/// model is already on the phone, as the owner preview does today.
ModelDeliveryController? get translatePreviewDelivery =>
    debugModelDeliveryOverride;
