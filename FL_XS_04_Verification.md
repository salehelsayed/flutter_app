### FL_XS_04 - QRDisplayScreen Layout

- [ ] **Widget exists:** `QRDisplayScreen`
- [ ] **Constructor parameters:**
  - [ ] `String qrData` (the JSON string)
  - [ ] `String peerId` (for display)
  - [ ] `VoidCallback onClose`
  - [ ] `VoidCallback? onShare` (optional)
- [ ] **UI elements:**
  - [ ] AppBar with back/close button
  - [ ] Title "My QR Code"
  - [ ] QR code widget (256x256 minimum)
  - [ ] Instruction text "Scan to connect with me"
  - [ ] Truncated peerId display (first 8 + last 4 chars)
  - [ ] Share button (if onShare provided)
- [ ] **No business logic:** Pure layout/presentation
- [ ] **Uses qr_flutter package:** `QrImageView` widget
- [ ] **Accessibility:** Semantic labels for QR code

```dart
// Quick test
QRDisplayScreen(
  qrData: '{"pk":"test"}',
  peerId: '12D3KooWAbcdef...',
  onClose: () {},
);
// Should render without errors
```
