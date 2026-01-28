# Task Prompt: FL_XS_04 - QRDisplayScreen Layout (Pure UI)

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

UI Design Requirements (Chat-App Style):
  ┌─────────────────────────────────────┐
  │  ←  My QR Code              [close] │
  ├─────────────────────────────────────┤
  │                                     │
  │         ┌─────────────────┐         │
  │         │                 │         │
  │         │    [QR CODE]    │         │
  │         │                 │         │
  │         │    256x256px    │         │
  │         │                 │         │
  │         └─────────────────┘         │
  │                                     │
  │     Scan to connect with me         │
  │                                     │
  │     ┌─────────────────────────┐     │
  │     │  12D3KooW...abc123      │     │
  │     │  (your peer ID)         │     │
  │     └─────────────────────────┘     │
  │                                     │
  │         [ Share QR Code ]           │
  │                                     │
  └─────────────────────────────────────┘

Key Elements:
  - Clean, centered layout
  - QR code is prominent (at least 256x256)
  - Instruction text below QR
  - Truncated peerID display
  - Optional share button

Package: qr_flutter (^4.1.0)
```

---

## Task Definition

```
[TASK FL_XS_04 – QRDisplayScreen layout (pure UI)]

Owner: Flutter

Goal:
  Create a pure layout widget for displaying the QR code.
  This is a StatelessWidget only - no state management, no business logic.

What to implement:
  - StatelessWidget: QRDisplayScreen
  - Constructor parameters:
      - String qrData (the JSON string to encode in QR)
      - String peerId (for display, will be truncated)
      - VoidCallback onClose
      - VoidCallback? onShare (optional)

  - UI elements:
      - AppBar with back button and title "My QR Code"
      - Centered QR code (256x256 minimum, white background)
      - Instruction text: "Scan to connect with me"
      - Card showing truncated peerID
      - Share button (if onShare provided)

Inputs:
  - qrData: String - The raw JSON string to encode
  - peerId: String - The user's peerID for display
  - onClose: VoidCallback - Called when close/back pressed
  - onShare: VoidCallback? - Called when share pressed (optional)

Outputs:
  - Widget tree with QR display
  - No side-effects (pure layout)

Flow_events:
  - None (pure layout widget - no flow events)

Constraints:
  - Pure UI widget - NO business logic
  - StatelessWidget ONLY - NO state management
  - NO API calls or async operations
  - All actions via callbacks
  - Use qr_flutter package (QrImageView) for QR rendering
  - QR code minimum size: 256x256 pixels

Deliverable:
  - File: lib/features/qr_code/presentation/screens/qr_display_screen.dart
```

---

## Output Requirements

1. **File:** `lib/features/qr_code/presentation/screens/qr_display_screen.dart`

2. **Must include:**
   - Pure StatelessWidget (no StatefulWidget)
   - QR code using qr_flutter (QrImageView)
   - Proper layout with centering
   - PeerID truncation helper
   - Responsive sizing (min 256x256 for QR)

3. **Implementation:**

```dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Screen that displays the user's QR code for identity sharing.
///
/// This is a pure layout widget with no business logic.
/// All actions are handled via callbacks.
///
/// Uses qr_flutter package for QR code rendering.
class QRDisplayScreen extends StatelessWidget {
  /// The JSON string to encode in the QR code.
  final String qrData;

  /// The user's peerID for display (will be truncated).
  final String peerId;

  /// Called when the user presses the back/close button.
  final VoidCallback onClose;

  /// Called when the user presses the share button.
  /// If null, the share button is not shown.
  final VoidCallback? onShare;

  const QRDisplayScreen({
    super.key,
    required this.qrData,
    required this.peerId,
    required this.onClose,
    this.onShare,
  });

  /// Truncates the peerID for display.
  /// Example: "12D3KooWAbcdefghijk..." → "12D3KooW...ghijk"
  String _truncatePeerId(String id) {
    if (id.length <= 20) return id;
    return '${id.substring(0, 10)}...${id.substring(id.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    // QR code size: responsive but minimum 256x256
    final qrSize = (screenWidth * 0.7).clamp(256.0, 300.0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onClose,
        ),
        title: const Text('My QR Code'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // QR Code Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  padding: const EdgeInsets.all(8),
                ),
              ),

              const SizedBox(height: 32),

              // Instruction Text
              Text(
                'Scan to connect with me',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // PeerID Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _truncatePeerId(peerId),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your Peer ID',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Share Button (conditional - only if onShare provided)
              if (onShare != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share),
                    label: const Text('Share QR Code'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## Package Dependency

Add to `pubspec.yaml`:

```yaml
dependencies:
  qr_flutter: ^4.1.0
```

Then run:
```bash
flutter pub get
```

---

## Usage Example

```dart
// Simple usage - pure UI, no state
QRDisplayScreen(
  qrData: '{"ns":"12D3KooW...","pk":"...","rv":"...","sig":"...","ts":"..."}',
  peerId: '12D3KooWAbcdefghijklmnop',
  onClose: () => Navigator.of(context).pop(),
);

// With share button
QRDisplayScreen(
  qrData: qrJsonString,
  peerId: identity.peerId,
  onClose: () => Navigator.of(context).pop(),
  onShare: () {
    Share.share('Scan my QR code to connect!');
  },
);
```

---

## Layout Requirements Summary

| Element | Requirement |
|---------|-------------|
| Widget Type | StatelessWidget only |
| QR Package | qr_flutter (QrImageView) |
| QR Size | Minimum 256x256 pixels |
| AppBar | Back button + "My QR Code" title |
| Instruction | "Scan to connect with me" |
| PeerID | Truncated display in card |
| Share Button | Optional (shown if onShare != null) |

---

## Begin Implementation

Output the complete Dart file with the QRDisplayScreen widget as a pure StatelessWidget.
