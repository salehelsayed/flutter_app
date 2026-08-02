import 'package:flutter/services.dart';

typedef DroppedPushRecoveryPendingHandler =
    Future<void> Function(int? generation);

/// Narrow gateway for the content-free Android dropped-push recovery marker.
///
/// Reads never consume the marker. Native code clears it only through a
/// compare-and-acknowledge operation after Dart has converged both inboxes.
abstract interface class DroppedPushRecoveryGateway {
  Future<int?> pendingGeneration();

  Future<bool> acknowledgeGeneration(int generation);

  void register(DroppedPushRecoveryPendingHandler onRecoveryPending);

  void dispose();
}

class DroppedPushRecoveryBridge implements DroppedPushRecoveryGateway {
  static const channelName = 'mknoon/dropped_push_recovery';
  static const pendingGenerationMethod = 'pendingGeneration';
  static const acknowledgeGenerationMethod = 'acknowledgeGeneration';
  static const recoveryPendingMethod = 'recoveryPending';

  final MethodChannel _channel;

  DroppedPushRecoveryBridge({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  @override
  Future<int?> pendingGeneration() async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        pendingGenerationMethod,
      );
      return _positiveGeneration(value);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> acknowledgeGeneration(int generation) async {
    if (generation <= 0) return false;
    try {
      return await _channel.invokeMethod<bool>(
            acknowledgeGenerationMethod,
            <String, Object?>{'generation': generation},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  void register(DroppedPushRecoveryPendingHandler onRecoveryPending) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != recoveryPendingMethod) {
        throw MissingPluginException(
          'No implementation found for method ${call.method} on $channelName',
        );
      }
      await onRecoveryPending(_generationFromArguments(call.arguments));
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  int? _generationFromArguments(Object? arguments) {
    if (arguments is Map) {
      return _positiveGeneration(arguments['generation']);
    }
    return _positiveGeneration(arguments);
  }

  int? _positiveGeneration(Object? value) {
    if (value is! int) return null;
    return value > 0 ? value : null;
  }
}
