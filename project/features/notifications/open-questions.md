# Notification open questions

## Open

- **OQ-05 — mute behavior:** determine whether a mute feature exists and what it
  currently suppresses. Do not create a mute subsystem from the PRD wording.

## Adopted

- **OQ-01:** when a new message arrives in the exact chat you are already
  viewing, the chat updates visually and the phone stays quiet. There is no OS
  notification, notification sound, vibration or app haptic. There is no
  in-chat cue setting or special cue for mentions. A retained physical-device
  run is still needed as proof, but the intended behavior is decided.
- **OQ-02:** exact-conversation activation cleanup is independent from read and
  cancels only the captured notification generation.
- **OQ-03:** local read requires resumed lifecycle plus the exact tracked
  conversation; unknown, absent or mismatched state is false.
- **OQ-04:** read, badge, cleanup and completed outcomes are installation-local;
  sibling-device clearing requires a separately approved protocol.
