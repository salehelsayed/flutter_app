import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// O4 (beta 2026-10-08): Android 14+ needs "full-screen notifications" access
/// for an incoming call to turn the screen on. Without it the phone only rings
/// and shows a collapsed lock-screen notification. After such a call the app
/// asks the user once, and again at most once a week while access is missing.
@immutable
class FullScreenCallAccessState {
  const FullScreenCallAccessState({
    required this.supported,
    required this.allowed,
    this.deniedCallAt,
    this.dismissedAt,
  });

  static const unsupported = FullScreenCallAccessState(
    supported: false,
    allowed: true,
  );

  final bool supported;
  final bool allowed;

  /// Last incoming call that rang without full-screen access.
  final DateTime? deniedCallAt;

  /// Last time the user chose "Not now".
  final DateTime? dismissedAt;

  static FullScreenCallAccessState fromMap(Map<Object?, Object?> map) {
    DateTime? time(Object? value) => value is int
        ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
        : null;
    return FullScreenCallAccessState(
      supported: map['supported'] == true,
      allowed: map['allowed'] != false,
      deniedCallAt: time(map['deniedCallAtMs']),
      dismissedAt: time(map['dismissedAtMs']),
    );
  }
}

const fullScreenCallAccessPromptInterval = Duration(days: 7);

bool shouldShowFullScreenCallAccessPrompt(
  FullScreenCallAccessState state,
  DateTime now,
) {
  if (!state.supported || state.allowed || state.deniedCallAt == null) {
    return false;
  }
  final dismissedAt = state.dismissedAt;
  return dismissedAt == null ||
      now.difference(dismissedAt) >= fullScreenCallAccessPromptInterval;
}

abstract interface class FullScreenCallAccessGateway {
  Future<FullScreenCallAccessState> read();
  Future<bool> openSettings();
  Future<void> dismiss();
}

/// Android-only; every other platform reports "unsupported" without a channel
/// call. Shares the app's notification-settings channel.
final class PlatformFullScreenCallAccessGateway
    implements FullScreenCallAccessGateway {
  const PlatformFullScreenCallAccessGateway({bool? isAndroid})
    : _isAndroid = isAndroid;

  static const _channel = MethodChannel('mknoon/push_notification_settings');

  final bool? _isAndroid;

  bool get _android => _isAndroid ?? (!kIsWeb && Platform.isAndroid);

  @override
  Future<FullScreenCallAccessState> read() async {
    if (!_android) return FullScreenCallAccessState.unsupported;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'readFullScreenCallAccess',
      );
      return map == null
          ? FullScreenCallAccessState.unsupported
          : FullScreenCallAccessState.fromMap(map);
    } on Object {
      return FullScreenCallAccessState.unsupported;
    }
  }

  @override
  Future<bool> openSettings() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('openFullScreenCallSettings') ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> dismiss() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<bool>('dismissFullScreenCallPrompt');
    } on Object {
      // Not persisted: the card may show again on the next refresh.
    }
  }
}

/// `value` is whether the prompt card is visible.
class FullScreenCallAccessPromptController extends ValueNotifier<bool> {
  FullScreenCallAccessPromptController({
    required FullScreenCallAccessGateway gateway,
    DateTime Function()? clock,
  }) : _gateway = gateway,
       _clock = clock ?? DateTime.now,
       super(false);

  final FullScreenCallAccessGateway _gateway;
  final DateTime Function() _clock;
  bool _disposed = false;

  Future<void> refresh() async {
    final state = await _gateway.read();
    if (_disposed) return;
    final show = shouldShowFullScreenCallAccessPrompt(state, _clock().toUtc());
    if (show && !value) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_FULL_SCREEN_ACCESS_PROMPT_SHOWN',
        details: const {},
      );
    }
    value = show;
  }

  Future<void> openSettings() async {
    final opened = await _gateway.openSettings();
    emitFlowEvent(
      layer: 'FL',
      event: 'CALL_FULL_SCREEN_ACCESS_SETTINGS_OPENED',
      details: {'opened': opened},
    );
  }

  Future<void> dismiss() async {
    if (!_disposed) value = false;
    await _gateway.dismiss();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
