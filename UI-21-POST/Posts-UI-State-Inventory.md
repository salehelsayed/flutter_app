# Posts UI State Inventory

Status: Proposed v1 implementation baseline  
Baseline date: 2026-03-15  
Approval record: `UI-21-POST/Phase-0-Approval.md`  
Reference pack:
- `UI-21-POST/screenshots/*`
- `../kitchen/landing-screen-claude/neighbourhood_spec.md`

This document maps the current screenshot pack to the required Posts UI states and records the non-screenshot fallback rules for states that still rely on the written spec.

## Screenshot-Mapped States

### Feed

#### Default feed

- Screenshot: `screenshots/01-default-feed.png`
- Required visible elements:
  - `Posts` header
  - compose prompt
  - pinned collapsed row
  - time-grouped feed section header
  - pass-along attribution example
  - nearby distance label example
  - standard post action row

#### Direct-friend text card

- Screenshot: `screenshots/02-friend-text-post.png`
- Required visible elements:
  - author header
  - direct-friend badge or scope handling per spec
  - text-focused body
  - action row
  - expiry footer

#### Nearby card with distance

- Screenshot: `screenshots/03-nearby-post-distance.png`
- Required visible elements:
  - nearby scope label
  - distance label
  - no extra privacy panel

#### Passed-along card

- Screenshot: `screenshots/04-passed-along-post.png`
- Required visible elements:
  - `passed this along` attribution line
  - original author as main card author
  - no mutual-friends badge

#### Pinned collapsed

- Screenshot: `screenshots/05-pinned-collapsed.png`
- Required visible elements:
  - pinned header
  - count
  - avatar stack
  - collapsed summary state

#### Pinned expanded

- Screenshot: `screenshots/06-pinned-expanded.png`
- Required visible elements:
  - expanded pinned cards
  - sender or receiver card actions as appropriate
  - `Message [name]` button on compact pinned cards

#### Caught-up / empty state

- Screenshot: `screenshots/14-caught-up.png`
- Required visible elements:
  - end-of-feed acknowledgment
  - no privacy panel

### Compose

#### Compose default

- Screenshot: `screenshots/07-compose-default.png`
- Required visible elements:
  - text input
  - `Media` attachment entry
  - `Voice` attachment entry
  - audience chooser
  - keep-available toggle

#### Compose nearby stale-blocked

- Screenshot: `screenshots/08-compose-nearby-stale.png`
- Required visible elements:
  - `People Nearby` selected
  - radius chooser
  - blocked nearby status card
  - `Refresh nearby before posting`
  - `Refresh nearby`
  - disabled submit state

#### Compose nearby ready

- Screenshot: `screenshots/09-compose-nearby-ready.png`
- Required visible elements:
  - selected radius
  - nearby ready state
  - enabled submit state

#### Compose media attached

- Screenshot: `screenshots/10-compose-media.png`
- Required visible elements:
  - attached media preview
  - audience chooser still visible
  - keep-available toggle still visible

#### Compose voice recording

- Screenshot: `screenshots/11-compose-voice-recording.png`
- Required visible elements:
  - inline recording chrome
  - elapsed time
  - live waveform
  - active pins banner if the author already has active pins

#### Compose voice draft

- Screenshot: `screenshots/12-compose-voice-draft.png`
- Required visible elements:
  - recorded voice draft preview
  - discard affordance
  - no automatic send on record stop

### Comments

#### Comments sheet

- Screenshot: `screenshots/13-comments.png`
- Required visible elements:
  - drag handle
  - post summary row
  - comment count
  - chronological comments
  - heart button per comment
  - compose field pinned at bottom

## Cross-Feature Voice References

These are not Posts mock states, but they are approved reuse references for recorder and playback language:

### Existing 1:1 voice-recording reference

- Screenshot: `screenshots/15-voice-recording.png`
- Use for:
  - recorder chrome proportions
  - waveform density
  - elapsed-time placement
  - cancel or stop affordance treatment

### Existing posted voice-message reference

- Screenshot: `screenshots/16-voice-message.png`
- Use for:
  - posted voice-player layout
  - waveform playback framing
  - duration placement

## States Without Current Screenshot Coverage

The following v1 states currently rely on the written spec rather than a screenshot:

- image carousel with swipe in motion
- video card playing state
- permission missing nearby compose state
- location services off nearby compose state
- nearby sharing off in Settings compose state
- sender-side own-post edit menu state
- full-screen pinned `See all` view

For these states, implementation follows:
- `neighbourhood_spec.md`
- `Posts-Feed-Rules.md`
- `Posts-Nearby-Privacy-Contract.md`

## UI Acceptance Notes

- Feed-level privacy panel must not appear.
- `People Nearby` status is compose-only.
- Reshared trust context is the attribution line only.
- Carousel interaction is horizontal swipe inside the card, with dots and counter badge.
- Voice posts reuse existing recorder and playback language instead of inventing a second system.
- Sender-side pinned-post controls are author-only.
- The sender-visible destructive pin control is a single `Remove` action in v1. Do not show separate `Unpin` and `Delete` affordances.

## Acceptance Summary

This state inventory is correct only if:
- every screenshot-backed state above is visually recognizable in implementation
- the non-screenshot states still follow the written contract docs
- the screenshot pack is treated as a layout reference, not as the only source of behavior
