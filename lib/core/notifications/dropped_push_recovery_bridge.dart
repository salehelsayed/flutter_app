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

/// Atomic native authority used only by the production headless owner.
///
/// Every field is read under the native store lock. Dart never combines
/// separate preference reads into an authority decision, and the final ACK
/// uses the corresponding revision-qualified atomic compare-and-consume.
final class DroppedPushRecoveryAuthority {
  const DroppedPushRecoveryAuthority({
    required this.currentBinding,
    required this.recoveryWorkEnabled,
    required this.pendingMarker,
    required this.authorityRevision,
    required this.authorityMutationInProgress,
  });

  final String? currentBinding;
  final bool recoveryWorkEnabled;
  final DroppedPushRecoveryMarker? pendingMarker;
  final int authorityRevision;
  final bool authorityMutationInProgress;
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
/// Unsupported/default callers keep [activateRecoveryWork] false; the one
/// registered production recovery graph may publish true with exact read-back.
abstract interface class DroppedPushRecoveryBindingPublisher {
  Future<DroppedPushRecoveryBindingPublication> setCurrentBinding(
    String? binding, {
    required bool activateRecoveryWork,
    bool recoverStaleAuthorityMutations = false,
  });
}

abstract interface class DroppedPushRecoveryAuthorityMutationPublisher {
  Future<DroppedPushRecoveryAuthorityMutationPublication>
  beginRecoveryAuthorityMutation();

  Future<DroppedPushRecoveryAuthorityMutationPublication>
  finishRecoveryAuthorityMutation(String token);
}

final class DroppedPushRecoveryAuthorityMutationPublication {
  const DroppedPushRecoveryAuthorityMutationPublication({
    required this.changed,
    required this.committed,
    required this.token,
    required this.currentBinding,
    required this.recoveryWorkEnabled,
    required this.authorityRevision,
    required this.authorityMutationInProgress,
  });

  const DroppedPushRecoveryAuthorityMutationPublication.rejected()
    : changed = false,
      committed = false,
      token = null,
      currentBinding = null,
      recoveryWorkEnabled = false,
      authorityRevision = -1,
      authorityMutationInProgress = true;

  final bool changed;
  final bool committed;
  final String? token;
  final String? currentBinding;
  final bool recoveryWorkEnabled;
  final int authorityRevision;
  final bool authorityMutationInProgress;

  bool get isCommittedBegin =>
      committed &&
      changed &&
      token != null &&
      token!.isNotEmpty &&
      authorityRevision >= 0 &&
      authorityMutationInProgress &&
      !recoveryWorkEnabled;

  bool get isCommittedFinish =>
      committed && changed && token == null && authorityRevision >= 0;
}

final class DroppedPushRecoveryBindingPublication {
  const DroppedPushRecoveryBindingPublication({
    required this.changed,
    required this.committed,
    required this.currentBinding,
    required this.recoveryWorkEnabled,
  });

  const DroppedPushRecoveryBindingPublication.rejected()
    : changed = false,
      committed = false,
      currentBinding = null,
      recoveryWorkEnabled = false;

  final bool changed;
  final bool committed;
  final String? currentBinding;
  final bool recoveryWorkEnabled;

  bool exactlyMatches({
    required String? binding,
    required bool recoveryWorkEnabled,
  }) =>
      committed &&
      currentBinding == binding &&
      this.recoveryWorkEnabled == recoveryWorkEnabled;
}

class DroppedPushRecoveryBridge
    implements
        DroppedPushRecoveryGateway,
        DroppedPushRecoveryBindingPublisher,
        DroppedPushRecoveryAuthorityMutationPublisher {
  static const channelName = 'mknoon/dropped_push_recovery';
  static const currentBindingMethod = 'currentBinding';
  static const pendingRecoveryMethod = 'pendingRecovery';
  static const pendingGenerationMethod = 'pendingGeneration';
  static const acknowledgeRecoveryMethod = 'acknowledgeRecovery';
  static const acknowledgeGenerationMethod = 'acknowledgeGeneration';
  static const recoveryPendingMethod = 'recoveryPending';
  static const setCurrentBindingMethod = 'setCurrentBinding';
  static const recoveryAuthorityMethod = 'recoveryAuthority';
  static const headlessAcknowledgeRecoveryMethod =
      'headlessAcknowledgeRecovery';
  static const beginRecoveryAuthorityMutationMethod =
      'beginRecoveryAuthorityMutation';
  static const finishRecoveryAuthorityMutationMethod =
      'finishRecoveryAuthorityMutation';

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

  /// Reads binding, readiness and the pending marker as one native snapshot.
  /// Any malformed shape is rejected rather than partially trusted.
  Future<DroppedPushRecoveryAuthority?> recoveryAuthority() async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        recoveryAuthorityMethod,
      );
      if (value is! Map ||
          value['recoveryWorkEnabled'] is! bool ||
          value['authorityRevision'] is! int ||
          value['authorityMutationInProgress'] is! bool) {
        return null;
      }
      final rawBinding = value['currentBinding'];
      final rawGeneration = value['pendingGeneration'];
      final rawPendingBinding = value['pendingBinding'];
      if ((rawBinding != null && rawBinding is! String) ||
          (rawGeneration != null && rawGeneration is! int) ||
          (rawPendingBinding != null && rawPendingBinding is! String)) {
        return null;
      }
      final authorityRevision = value['authorityRevision'] as int;
      final mutationInProgress = value['authorityMutationInProgress'] as bool;
      if (authorityRevision < 0 ||
          (mutationInProgress && value['recoveryWorkEnabled'] == true)) {
        return null;
      }
      final binding = (rawBinding as String?)?.trim();
      final pendingBinding = (rawPendingBinding as String?)?.trim();
      if ((binding != null && (binding.isEmpty || binding != rawBinding)) ||
          (pendingBinding != null &&
              (pendingBinding.isEmpty ||
                  pendingBinding != rawPendingBinding))) {
        return null;
      }
      DroppedPushRecoveryMarker? marker;
      if (rawGeneration == null && pendingBinding == null) {
        marker = null;
      } else if (rawGeneration is int &&
          rawGeneration > 0 &&
          pendingBinding != null) {
        marker = DroppedPushRecoveryMarker(
          generation: rawGeneration,
          binding: pendingBinding,
        );
      } else {
        return null;
      }
      return DroppedPushRecoveryAuthority(
        currentBinding: binding,
        recoveryWorkEnabled: value['recoveryWorkEnabled'] as bool,
        pendingMarker: marker,
        authorityRevision: authorityRevision,
        authorityMutationInProgress: mutationInProgress,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Headless-only ACK. Native atomically requires readiness plus the exact
  /// current binding, authority revision and pending generation before clearing
  /// the marker.
  Future<bool> acknowledgeHeadlessRecovery(
    DroppedPushRecoveryMarker marker, {
    required int authorityRevision,
  }) async {
    if (marker.generation <= 0 ||
        marker.binding.trim() != marker.binding ||
        marker.binding.isEmpty ||
        authorityRevision < 0) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>(
            headlessAcknowledgeRecoveryMethod,
            <String, Object?>{
              'generation': marker.generation,
              'binding': marker.binding,
              'authorityRevision': authorityRevision,
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
  Future<DroppedPushRecoveryBindingPublication> setCurrentBinding(
    String? binding, {
    required bool activateRecoveryWork,
    bool recoverStaleAuthorityMutations = false,
  }) async {
    try {
      final value = await _channel
          .invokeMethod<Object?>(setCurrentBindingMethod, <String, Object?>{
            'binding': binding,
            'activateRecoveryWork': activateRecoveryWork,
            'recoverStaleAuthorityMutations': recoverStaleAuthorityMutations,
          });
      if (value is! Map ||
          value['changed'] is! bool ||
          value['committed'] is! bool ||
          value['recoveryWorkEnabled'] is! bool) {
        return const DroppedPushRecoveryBindingPublication.rejected();
      }
      final rawBinding = value['currentBinding'];
      if (rawBinding != null && rawBinding is! String) {
        return const DroppedPushRecoveryBindingPublication.rejected();
      }
      final currentBinding = (rawBinding as String?)?.trim();
      if (currentBinding != null &&
          (currentBinding.isEmpty || currentBinding != rawBinding)) {
        return const DroppedPushRecoveryBindingPublication.rejected();
      }
      return DroppedPushRecoveryBindingPublication(
        changed: value['changed'] as bool,
        committed: value['committed'] as bool,
        currentBinding: currentBinding,
        recoveryWorkEnabled: value['recoveryWorkEnabled'] as bool,
      );
    } on MissingPluginException {
      return const DroppedPushRecoveryBindingPublication.rejected();
    } on PlatformException {
      return const DroppedPushRecoveryBindingPublication.rejected();
    }
  }

  @override
  Future<DroppedPushRecoveryAuthorityMutationPublication>
  beginRecoveryAuthorityMutation() =>
      _authorityMutationCall(beginRecoveryAuthorityMutationMethod);

  @override
  Future<DroppedPushRecoveryAuthorityMutationPublication>
  finishRecoveryAuthorityMutation(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty || normalized != token) {
      return const DroppedPushRecoveryAuthorityMutationPublication.rejected();
    }
    return _authorityMutationCall(
      finishRecoveryAuthorityMutationMethod,
      arguments: <String, Object?>{'token': normalized},
    );
  }

  Future<DroppedPushRecoveryAuthorityMutationPublication>
  _authorityMutationCall(
    String method, {
    Map<String, Object?>? arguments,
  }) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method, arguments);
      if (value is! Map) {
        return const DroppedPushRecoveryAuthorityMutationPublication.rejected();
      }
      final changed = value['changed'];
      final committed = value['committed'];
      final rawToken = value['token'];
      final rawBinding = value['currentBinding'];
      final enabled = value['recoveryWorkEnabled'];
      final revision = value['authorityRevision'];
      final inProgress = value['authorityMutationInProgress'];
      if (changed is! bool ||
          committed is! bool ||
          (rawToken != null && rawToken is! String) ||
          (rawBinding != null && rawBinding is! String) ||
          enabled is! bool ||
          revision is! int ||
          inProgress is! bool ||
          revision < 0) {
        return const DroppedPushRecoveryAuthorityMutationPublication.rejected();
      }
      final token = (rawToken as String?)?.trim();
      final binding = (rawBinding as String?)?.trim();
      if ((token != null && (token.isEmpty || token != rawToken)) ||
          (binding != null && (binding.isEmpty || binding != rawBinding)) ||
          (inProgress && enabled)) {
        return const DroppedPushRecoveryAuthorityMutationPublication.rejected();
      }
      return DroppedPushRecoveryAuthorityMutationPublication(
        changed: changed,
        committed: committed,
        token: token,
        currentBinding: binding,
        recoveryWorkEnabled: enabled,
        authorityRevision: revision,
        authorityMutationInProgress: inProgress,
      );
    } on MissingPluginException {
      return const DroppedPushRecoveryAuthorityMutationPublication.rejected();
    } on PlatformException {
      return const DroppedPushRecoveryAuthorityMutationPublication.rejected();
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
