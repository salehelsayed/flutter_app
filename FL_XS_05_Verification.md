

### FL_XS_05 - Wire QRDisplayScreen

- [ ] **Widget exists:** `QRDisplayWired` or integrated into navigation
- [ ] **Calls buildQRPayload:** On initialization
- [ ] **Handles all states:**
  - [ ] Loading: Shows CircularProgressIndicator
  - [ ] Success: Shows QRDisplayScreen with data
  - [ ] noIdentity: Shows error message "No identity found"
  - [ ] signingError: Shows error message with retry button
- [ ] **Dependencies injected:** Repository and bridge function
- [ ] **Navigation integrated:**
  - [ ] Can navigate to QR screen from appropriate entry point
  - [ ] Back button returns to previous screen
- [ ] **Flow events:**
  - [ ] Emits `QR_FL_SCREEN_INIT`
  - [ ] Emits `QR_FL_SCREEN_LOADING`
  - [ ] Emits `QR_FL_SCREEN_DISPLAY` on success
  - [ ] Emits `QR_FL_SCREEN_ERROR` on error

---