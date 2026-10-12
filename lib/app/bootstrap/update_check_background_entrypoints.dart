import 'package:flutter_app/features/update_check/background/update_check_background_host.dart';

export 'package:flutter_app/features/update_check/background/update_check_minimal_entrypoint.dart'
    show runUpdateCheckMinimalEngine;

/// SE-41 T4a: the owner main.dart calls for the background update check.
///
/// Installs the main-engine host synchronously, before the app bootstrap: the
/// iOS BG task and the Android worker handoff must not wait for the Go bridge
/// or SQLCipher. It also schedules or cancels the native background work from
/// the kill switch.
void installUpdateCheckBackgroundHost() => UpdateCheckBackgroundHost().install();
