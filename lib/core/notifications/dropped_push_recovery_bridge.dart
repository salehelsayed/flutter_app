import 'package:flutter/services.dart';

typedef DroppedPushRecoveryPendingHandler =
    Future<void> Function(int? generation);

final class DroppedPushRecoveryMarker {
  const DroppedPushRecoveryMarker({
    required this.generation,
    required this.binding,
  });

  final int generation;
  final String binding;
}

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

/// Account/install fencing is published separately from marker consumption.
/// The H0 prerequisite always keeps [activateRecoveryWork] false.
abstract interface class DroppedPushRecoveryBindingPublisher {
  Future<bool> setCurrentBinding(
    String? binding, {
    required bool activateRecoveryWork,
  });
}

class DroppedPushRecoveryBridge
    implements DroppedPushRecoveryGateway, DroppedPushRecoveryBindingPublisher {
  static const channelName = 'mknoon/dropped_push_recovery';
  static const currentBindingMethod = 'currentBinding';
  static const pendingRecoveryMethod = 'pendingRecovery';
  static const pendingGenerationMethod = 'pendingGeneration';
  static const acknowledgeRecoveryMethod = 'acknowledgeRecovery';
  static const acknowledgeGenerationMethod = 'acknowledgeGeneration';
  static const recoveryPendingMethod = 'recoveryPending';
  static const setCurrentBindingMethod = 'setCurrentBinding';

  final MethodChannel _channel;

  DroppedPushRecoveryBridge({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  Future<String?> currentBinding() async {
    try {
      final value = await _channel.invokeMethod<Object?>(currentBindingMethod);
      final binding = (value as String?)?.trim();
      return binding == null || binding.isEmpty ? null : binding;
    } on MissingPluginException {
      return null;
    }
  }

  Future<DroppedPushRecoveryMarker?> pendingRecovery() async {
    try {
      final value = await _channel.invokeMethod<Object?>(pendingRecoveryMethod);
      if (value is! Map) return null;
      final generation = _positiveGeneration(value['generation']);
      final binding = (value['binding'] as String?)?.trim();
      if (generation == null || binding == null || binding.isEmpty) return null;
      return DroppedPushRecoveryMarker(
        generation: generation,
        binding: binding,
      );
    } on MissingPluginException {
      return null;
    }
  }

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

  Future<bool> acknowledgeRecovery(DroppedPushRecoveryMarker marker) async {
    if (marker.generation <= 0 || marker.binding.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            acknowledgeRecoveryMethod,
            <String, Object?>{
              'generation': marker.generation,
              'binding': marker.binding,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> setCurrentBinding(
    String? binding, {
    required bool activateRecoveryWork,
  }) async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        setCurrentBindingMethod,
        <String, Object?>{
          'binding': binding,
          'activateRecoveryWork': activateRecoveryWork,
        },
      );
      return value is Map && value['committed'] == true;
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
