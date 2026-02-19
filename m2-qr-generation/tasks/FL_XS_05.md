# Task Prompt: FL_XS_05 - Wire QRDisplayScreen

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Wiring Requirements:
  - StatefulWidget that runs buildQRPayload on init
  - Handle all result states (loading, success, error)
  - Pass data to QRDisplayScreen layout widget
  - Inject dependencies for testability
  - Retry capability for recoverable errors

Existing Components:
  - QRDisplayScreen (FL_XS_04): Pure layout widget
  - buildQRPayload (FL_XS_03): Use case returning (BuildQRPayloadResult, String?)
  - IdentityRepository (M1): Repository interface
  - JsBridge (M1): Abstract bridge interface; callJsSignPayload is a top-level function

States to Handle:
  - Loading: Show progress indicator
  - Success: Show QRDisplayScreen with data
  - NoIdentity: Show error with message
  - SigningError: Show error with retry option
```

---

## Task Definition

```
[TASK FL_XS_05 – Wire QRDisplayScreen with use case]

Owner: Flutter

Goal:
  Connect QRDisplayScreen to buildQRPayload use case with state management.
  StatefulWidget that orchestrates the QR generation flow.

What to implement:
  - StatefulWidget: QRDisplayWired
  - Constructor parameters:
      - IdentityRepository repo
      - JsBridge bridgeClient
      - VoidCallback onClose

  - States:
      - _QRDisplayState.loading: Initial, while building payload
      - _QRDisplayState.success: QR payload ready
      - _QRDisplayState.noIdentity: No identity found
      - _QRDisplayState.error: Signing or other error

  - Behavior:
      - On init: Call _buildPayload() immediately
      - _buildPayload(): Call buildQRPayload use case
      - On success: Store qrData and peerId, show QRDisplayScreen
      - On error: Show appropriate error message with retry

Wiring:
  - Calls buildQRPayload with:
      - Real IdentityRepository (from constructor)
      - Real callJsSignPayload (top-level function, passing bridgeClient as bridge)

Inputs:
  - repo: IdentityRepository
  - bridgeClient: JsBridge
  - onClose: VoidCallback

Outputs:
  - Widget showing appropriate state (loading/success/error)
  - Calls use case and handles all outcomes

Flow_events:
  - On widget mount (initState):
      - layer: "FL", event: "QR_FL_SCREEN_INIT", details: {}
  - On entering loading state (_buildPayload start):
      - layer: "FL", event: "QR_FL_SCREEN_LOADING", details: {}
  - On success (QR displayed):
      - layer: "FL", event: "QR_FL_SCREEN_DISPLAY", details: {}
  - On error (any error path):
      - layer: "FL", event: "QR_FL_SCREEN_ERROR", details: { "reason": "<error_type>" }
  - On widget unmount (dispose):
      - layer: "FL", event: "QR_FL_SCREEN_CLOSE", details: {}

Constraints:
  - Use StatefulWidget for state management
  - Dependencies injected via constructor
  - Error messages user-friendly
  - Retry option for recoverable errors (signing errors)
  - No retry for noIdentity (user must create identity first)

Deliverable:
  - File: lib/features/qr_code/presentation/screens/qr_display_wired.dart
```

---

## Output Requirements

1. **File:** `lib/features/qr_code/presentation/screens/qr_display_wired.dart`

2. **Must include:**
   - StatefulWidget with state management
   - Loading indicator while building payload
   - Error handling with retry (for signing errors)
   - Integration with QRDisplayScreen (pure UI)
   - Flow event emissions: QR_FL_SCREEN_INIT, QR_FL_SCREEN_LOADING, QR_FL_SCREEN_DISPLAY, QR_FL_SCREEN_ERROR, QR_FL_SCREEN_CLOSE

3. **Implementation:**

```dart
import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_screen.dart';

/// Internal state enum for QRDisplayWired
enum _QRDisplayState {
  loading,
  success,
  noIdentity,
  error,
}

/// Wired widget that connects QRDisplayScreen to the buildQRPayload use case.
///
/// This is a StatefulWidget that:
/// - Runs buildQRPayload on init
/// - Handles loading/success/error states
/// - Provides retry capability for recoverable errors
/// - Emits flow events for QR_FL_SCREEN_INIT, QR_FL_SCREEN_CLOSE, etc.
class QRDisplayWired extends StatefulWidget {
  /// Repository for loading identity data.
  final IdentityRepository repo;

  /// Bridge for JS communication (used with callJsSignPayload top-level function).
  final JsBridge bridgeClient;

  /// Called when user closes the screen.
  final VoidCallback onClose;

  const QRDisplayWired({
    super.key,
    required this.repo,
    required this.bridgeClient,
    required this.onClose,
  });

  @override
  State<QRDisplayWired> createState() => _QRDisplayWiredState();
}

class _QRDisplayWiredState extends State<QRDisplayWired> {
  _QRDisplayState _state = _QRDisplayState.loading;
  String? _qrData;
  String? _peerId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_SCREEN_INIT',
      details: {},
    );
    _buildPayload();
  }

  @override
  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_SCREEN_CLOSE',
      details: {},
    );
    super.dispose();
  }

  Future<void> _buildPayload() async {
    setState(() {
      _state = _QRDisplayState.loading;
      _errorMessage = null;
    });

    emitFlowEvent(
      layer: 'FL',
      event: 'QR_FL_SCREEN_LOADING',
      details: {},
    );

    try {
      final identity = await widget.repo.loadIdentity();

      if (identity == null) {
        setState(() {
          _state = _QRDisplayState.noIdentity;
          _errorMessage = 'No identity found. Please create one first.';
        });
        return;
      }

      // Wiring: wrap callJsSignPayload top-level function with bridgeClient
      Future<Map<String, dynamic>> jsSign(String dataToSign, String privateKey) {
        return callJsSignPayload(
          bridge: widget.bridgeClient,
          dataToSign: dataToSign,
          privateKey: privateKey,
        );
      }

      final (result, qrString) = await buildQRPayload(
        repo: widget.repo,
        callJsSign: jsSign,
      );

      switch (result) {
        case BuildQRPayloadResult.success:
          setState(() {
            _state = _QRDisplayState.success;
            _qrData = qrString;
            _peerId = identity.peerId;
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_DISPLAY',
            details: {},
          );
          break;

        case BuildQRPayloadResult.noIdentity:
          setState(() {
            _state = _QRDisplayState.noIdentity;
            _errorMessage = 'No identity found. Please create one first.';
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_ERROR',
            details: {'reason': 'noIdentity'},
          );
          break;

        case BuildQRPayloadResult.signingError:
          setState(() {
            _state = _QRDisplayState.error;
            _errorMessage = 'Failed to sign QR code. Please try again.';
          });
          emitFlowEvent(
            layer: 'FL',
            event: 'QR_FL_SCREEN_ERROR',
            details: {'reason': 'signingError'},
          );
          break;
      }
    } catch (e) {
      setState(() {
        _state = _QRDisplayState.error;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
      emitFlowEvent(
        layer: 'FL',
        event: 'QR_FL_SCREEN_ERROR',
        details: {'reason': 'exception', 'error': e.toString()},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _QRDisplayState.loading:
        return _buildLoadingScreen();

      case _QRDisplayState.success:
        return QRDisplayScreen(
          qrData: _qrData!,
          peerId: _peerId!,
          onClose: widget.onClose,
          onShare: _handleShare,
        );

      case _QRDisplayState.noIdentity:
        return _buildErrorScreen(
          icon: Icons.person_off,
          title: 'No Identity',
          message: _errorMessage!,
          showRetry: false,
        );

      case _QRDisplayState.error:
        return _buildErrorScreen(
          icon: Icons.error_outline,
          title: 'Error',
          message: _errorMessage!,
          showRetry: true,
        );
    }
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        title: const Text('My QR Code'),
        centerTitle: true,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Generating QR code...'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen({
    required IconData icon,
    required String title,
    required String message,
    required bool showRetry,
  }) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        title: const Text('My QR Code'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (showRetry) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _buildPayload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share functionality coming soon!')),
    );
  }
}
```

---

## Usage Example

```dart
// Navigate to QR display (wired with real dependencies)
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (context) => QRDisplayWired(
      repo: identityRepository,         // Real IdentityRepository
      bridgeClient: jsBridge,           // Real JsBridge instance
      onClose: () => Navigator.of(context).pop(),
    ),
  ),
);

// Or with named routes and dependency injection
MaterialApp(
  routes: {
    '/qr': (context) => QRDisplayWired(
      repo: getIt<IdentityRepository>(),
      bridgeClient: getIt<JsBridge>(),
      onClose: () => Navigator.of(context).pop(),
    ),
  },
);
```

---

## Flow Events Summary

| Event | Layer | When | Details |
|-------|-------|------|---------|
| QR_FL_SCREEN_INIT | FL | initState (widget mount) | {} |
| QR_FL_SCREEN_LOADING | FL | _buildPayload start | {} |
| QR_FL_SCREEN_DISPLAY | FL | success (QR ready) | {} |
| QR_FL_SCREEN_ERROR | FL | any error path | { "reason": "<type>" } |
| QR_FL_SCREEN_CLOSE | FL | dispose (widget unmount) | {} |

---

## State Diagram

```
┌──────────┐
│ loading  │──────────────────┐
└────┬─────┘                  │
     │ buildQRPayload()       │
     ▼                        │
┌──────────────────────┐      │
│ Check result         │      │
└──────────┬───────────┘      │
           │                  │
     ┌─────┴─────┬────────────┤
     │           │            │
     ▼           ▼            ▼
┌─────────┐ ┌──────────┐ ┌─────────┐
│ success │ │noIdentity│ │  error  │
└─────────┘ └──────────┘ └────┬────┘
                              │
                              │ retry
                              │
                              ▼
                         ┌──────────┐
                         │ loading  │
                         └──────────┘
```

---

## Integration Points

This widget requires:
1. `IdentityRepository` from M1
2. `JsBridge` from M1 + `callJsSignPayload` top-level function from FL_XS_02
3. `buildQRPayload` from FL_XS_03
4. `QRDisplayScreen` from FL_XS_04

---

## Begin Implementation

Output the complete Dart file with the QRDisplayWired StatefulWidget that:
- Runs buildQRPayload on init
- Handles loading/success/error states with retry
- Wires real repo and callJsSignPayload
- Emits QR_FL_SCREEN_INIT, QR_FL_SCREEN_LOADING, QR_FL_SCREEN_DISPLAY, QR_FL_SCREEN_ERROR, QR_FL_SCREEN_CLOSE flow events
