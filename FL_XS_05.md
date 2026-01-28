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
  - JsBridgeClient (M1 + FL_XS_02): Bridge with callJsSignPayload

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
      - JsBridgeClient bridgeClient
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
      - Real callJsSignPayload (from bridgeClient)

Inputs:
  - repo: IdentityRepository
  - bridgeClient: JsBridgeClient
  - onClose: VoidCallback

Outputs:
  - Widget showing appropriate state (loading/success/error)
  - Calls use case and handles all outcomes

Flow_events:
  - On widget mount (initState):
      - layer: "UI", event: "QR_UI_DISPLAY_OPEN", details: {}
  - On widget unmount (dispose):
      - layer: "UI", event: "QR_UI_DISPLAY_CLOSE", details: {}

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
   - Flow event emissions: QR_UI_DISPLAY_OPEN and QR_UI_DISPLAY_CLOSE

3. **Implementation:**

```dart
import 'package:flutter/material.dart';

import 'package:your_app/core/bridge/js_bridge_client.dart';
import 'package:your_app/core/utils/flow_event_emitter.dart';
import 'package:your_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:your_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:your_app/features/qr_code/presentation/screens/qr_display_screen.dart';

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
/// - Emits flow events for QR_UI_DISPLAY_OPEN and QR_UI_DISPLAY_CLOSE
class QRDisplayWired extends StatefulWidget {
  /// Repository for loading identity data.
  final IdentityRepository repo;

  /// Bridge client for JS communication (callJsSignPayload).
  final JsBridgeClient bridgeClient;

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
    // Flow event: QR_UI_DISPLAY_OPEN on mount
    emitFlowEvent(
      layer: 'UI',
      event: 'QR_UI_DISPLAY_OPEN',
      details: {},
    );
    // Run buildQRPayload immediately on init
    _buildPayload();
  }

  @override
  void dispose() {
    // Flow event: QR_UI_DISPLAY_CLOSE on unmount
    emitFlowEvent(
      layer: 'UI',
      event: 'QR_UI_DISPLAY_CLOSE',
      details: {},
    );
    super.dispose();
  }

  Future<void> _buildPayload() async {
    setState(() {
      _state = _QRDisplayState.loading;
      _errorMessage = null;
    });

    try {
      // First load identity to get peerId for display
      final identity = await widget.repo.loadIdentity();

      if (identity == null) {
        setState(() {
          _state = _QRDisplayState.noIdentity;
          _errorMessage = 'No identity found. Please create one first.';
        });
        return;
      }

      // Build the QR payload using the use case
      // Wiring: real repo + real callJsSignPayload from bridgeClient
      final (result, qrString) = await buildQRPayload(
        repo: widget.repo,
        callJsSign: ({required dataToSign, required privateKey}) =>
            widget.bridgeClient.callJsSignPayload(
              dataToSign: dataToSign,
              privateKey: privateKey,
            ),
      );

      switch (result) {
        case BuildQRPayloadResult.success:
          setState(() {
            _state = _QRDisplayState.success;
            _qrData = qrString;
            _peerId = identity.peerId;
          });
          break;

        case BuildQRPayloadResult.noIdentity:
          setState(() {
            _state = _QRDisplayState.noIdentity;
            _errorMessage = 'No identity found. Please create one first.';
          });
          break;

        case BuildQRPayloadResult.signingError:
          setState(() {
            _state = _QRDisplayState.error;
            _errorMessage = 'Failed to sign QR code. Please try again.';
          });
          break;
      }
    } catch (e) {
      setState(() {
        _state = _QRDisplayState.error;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
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
          showRetry: false, // No retry - user must create identity first
        );

      case _QRDisplayState.error:
        return _buildErrorScreen(
          icon: Icons.error_outline,
          title: 'Error',
          message: _errorMessage!,
          showRetry: true, // Retry available for signing errors
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
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (showRetry) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _buildPayload, // Retry
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
    // TODO: Implement share functionality
    // Could use share_plus package:
    // Share.share('Scan my QR code to connect with me!');

    // For now, show a snackbar
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
      bridgeClient: jsBridgeClient,     // Real JsBridgeClient with callJsSignPayload
      onClose: () => Navigator.of(context).pop(),
    ),
  ),
);

// Or with named routes and dependency injection
MaterialApp(
  routes: {
    '/qr': (context) => QRDisplayWired(
      repo: getIt<IdentityRepository>(),
      bridgeClient: getIt<JsBridgeClient>(),
      onClose: () => Navigator.of(context).pop(),
    ),
  },
);
```

---

## Flow Events Summary

| Event | Layer | When | Details |
|-------|-------|------|---------|
| QR_UI_DISPLAY_OPEN | UI | initState (widget mount) | {} |
| QR_UI_DISPLAY_CLOSE | UI | dispose (widget unmount) | {} |

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
2. `JsBridgeClient` from M1 with `callJsSignPayload` added in FL_XS_02
3. `buildQRPayload` from FL_XS_03
4. `QRDisplayScreen` from FL_XS_04

---

## Begin Implementation

Output the complete Dart file with the QRDisplayWired StatefulWidget that:
- Runs buildQRPayload on init
- Handles loading/success/error states with retry
- Wires real repo and callJsSignPayload
- Emits QR_UI_DISPLAY_OPEN and QR_UI_DISPLAY_CLOSE flow events
