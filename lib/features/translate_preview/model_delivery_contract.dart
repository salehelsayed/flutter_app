import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_runtime.dart';

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

final class TranslatorMemoryTemporarilyUnavailable implements Exception {
  const TranslatorMemoryTemporarilyUnavailable();
}

final class TranslatorMemoryUnsupported implements Exception {
  const TranslatorMemoryUnsupported();
}

/// The download logic the translator UI drives. The UI depends only on this
/// file.
abstract class ModelDeliveryController {
  ValueListenable<ModelDeliveryState> get state;

  /// Static OS, process ABI and total-RAM eligibility. False until known.
  /// An eligible phone can still be blocked by inference or memory safety;
  /// that does not remove its manual recovery entry in Settings.
  ValueListenable<bool> get deviceSupported;

  /// The Settings "Download over mobile data" switch.
  ValueListenable<bool> get allowMobileData;

  ValueListenable<bool> get memoryNoticePending;

  /// Persists consumption before the sole app UI owner presents the notice.
  Future<bool> consumeMemoryNotice();

  /// Explicit Settings recovery; never downloads or loads a model.
  Future<void> retryMemorySafety();

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

/// The shared production download, or null outside mobile or in disabled tests.
/// A test override avoids constructing any production adapters.
ModelDeliveryController? get translatePreviewDelivery =>
    debugModelDeliveryOverride ?? productionTranslatePreviewDelivery;
