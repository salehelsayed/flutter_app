# Signal theme UI/UX audit

## Intent

Evaluate the currently shipped `Signal` background on the live Android app and define a light appearance that feels calm, warm, and dimensional instead of pale.

- Device: Pixel 6, Android 16, 1080 × 2400, font scale 1.0
- App: `com.mknoon.app`, debug build with existing local test data
- Capture date: 2026-07-09
- Signal was selected through the production path: Orbit center avatar → Settings → Background → Signal

## Capture set

The audit contains 23 Signal surfaces/states plus three before-selection references. Contact identifiers and the QR payload are redacted. The mnemonic/recovery phrase was deliberately not opened.

- [Shell contact sheet](contact-sheet-1-shell.png), ordered left-to-right/top-to-bottom: dark Orbit baseline, dark Settings, dark chooser, Signal Settings, Signal Orbit, All Chats, Intros, Archived, chat search, Orbit find, Feed.
- [Conversation contact sheet](contact-sheet-2-conversations.png): conversation, overflow, attachment sheet, redacted profile, create menu, new-group picker, empty conversation, introduction picker.
- [Settings contact sheet](contact-sheet-3-settings.png): redacted My QR, Android camera permission, scanner, quality sheet, move-account route, selected Signal chooser, lower Settings diagnostics.

Not captured: recovery phrase (secret), onboarding (would require deleting or replacing the current identity), group conversation/info (no group existed in the device data), and destructive completion states.

## Findings

### P0 — Signal is not a real light theme

The app-level `MaterialApp` is still fixed to `AppTheme.darkTheme` and `ThemeMode.dark`. Signal only replaces custom extensions inside `AmbientBackground`. That causes pushed routes and modal controls to fall back to dark styling.

Visible evidence:

- Contact Profile stays completely dark.
- Conversation overflow and attachment sheets stay dark.
- Some native/default controls derive from the dark Material color scheme.
- Lower Settings diagnostics use hard-coded translucent white and become nearly invisible on white.

This is the core consistency and accessibility problem. A background choice is currently carrying responsibilities that belong to an application theme.

### P0 — There are live contrast failures

- The Orbit find field renders near-white text on a near-white translucent field.
- Debug Introductions and Transport Diagnostics are effectively white-on-white.
- Some disabled and placeholder states become too faint to distinguish.

These are not subjective palette concerns; they block reading and orientation.

### P1 — The canvas has almost no tonal hierarchy

Signal is pure white through 62% of the radial gradient, then reaches only `#F0F1F4` at the edge. Its violet and blue washes are fully transparent. The implemented result therefore has neither the promised “electric-violet star” nor visible ambient color.

The light surface stack is also very compressed:

- canvas/ground: `#FFFFFF`
- base surface: `#F4F6FA` — about 1.08:1 against white
- input/subtle surface: `#F7F8FB` — about 1.06:1 against white
- raised surface: `#FFFFFF`

Cards, inputs, sheets, and the canvas visually merge. Thin violet borders then have to do all of the structural work, producing a clinical, outlined look rather than a comforting one.

### P1 — Screen-specific issues

- **Orbit:** strong central concept and obvious create action, but the large white field feels unfinished; saturated contact nodes have no environmental color to settle into.
- **All Chats:** readable names, but oversized repeated outlined cards make scanning slow and visually heavy.
- **Intros/Archived:** clear labels, yet empty states sit in a large white void with little warmth or guidance.
- **Feed:** repeated `Connected / tap to say hi` rows have weak identity and hierarchy; the floating navigation overlaps content near the bottom.
- **Conversation:** the intro banner dominates, message bubbles barely separate from the canvas, and the middle of the screen becomes a large dead zone.
- **Search:** All Chats search is understandable; Orbit find contains a severe text/background contrast failure.
- **Creation pickers:** clean and usable, but search fields and selection controls are too faint.
- **My QR:** the best-composed Signal surface because the green glow and grouped action create depth. It is a useful direction for the rest of the light theme.
- **Move account:** strong task focus and CTA, but a hard horizontal background seam and a large empty lower half make it feel unfinished.
- **Scanner:** dark is appropriate as a functional camera exception; it should not be forced light.
- **Background chooser:** no swatches or preview, inaccurate Signal description, and immediate dismissal make comparisons unnecessarily tedious.

## Refinement

### 1. Separate appearance from wallpaper

Add a true `Appearance` preference: `System`, `Light`, and `Dark`. Let `Background` remain a decorative choice. Signal can default to Light, but every route, sheet, dialog, popup, switch, text field, and system overlay must receive the same semantic `ColorScheme`.

This removes the current “light islands inside a dark app” behavior.

### 2. Replace paper white with a warm mineral canvas

Recommended starting palette:

| Role | Color | Purpose |
|---|---:|---|
| Canvas | `#ECE8E1` | warm mineral/linen ground; never pure white |
| Raised card | `#FAF8F3` | soft ivory surface |
| Nested/subtle surface | `#E1DCE5` | lavender-grey depth for inputs and grouped areas |
| Primary text | `#25222B` | warm charcoal |
| Secondary text | `#56515E` | 6.29:1 against the proposed canvas |
| Muted text | `#716B78` | use for larger/supporting text; darken for small text |
| Accent | `#6045B6` | calmer violet; white text is 6.94:1 |
| Success | `#2F7755` | muted forest green; white text is 5.40:1 |
| Interactive border | `#8D83A8` | 3.33:1 against the raised card |
| Subtle divider | `#B3ACBD` | grouping only, not the sole control boundary |

Keep pure white for small highlights and selected segments, not for the entire canvas.

### 3. Give Signal real ambient color

Use two broad, low-opacity blooms rather than invisible animation:

- muted violet `#7C69C8` at roughly 8–10%
- sage/teal `#58A989` at roughly 6–8%

Anchor one bloom near the primary content and one at the opposite edge. Keep motion extremely slow or static under reduced-motion settings. Remove the 18-second repaint loop if washes remain transparent.

### 4. Use filled hierarchy instead of outlining everything

- Canvas → section surface → input/selected surface should be visibly distinct.
- Reserve the stronger violet outline for focus, selection, and active controls.
- Use one soft elevation recipe for raised elements: low-opacity warm shadow plus a subtle border.
- Conversation bubbles: incoming `#FAF8F3`, outgoing a restrained violet tint such as `#DED6F4`.
- Empty states should occupy a compact warm panel instead of floating in a full-screen white void.

### 5. Fix the highest-impact screens first

1. Introduce a real light `ThemeData`/`ColorScheme` and switch the root `MaterialApp` by appearance.
2. Replace hard-coded white debug/diagnostic colors with semantic tokens.
3. Make Contact Profile, overflow menus, and attachment sheets inherit light appearance; keep Scanner explicitly dark.
4. Fix Orbit find text/input contrast.
5. Rebalance canvas, card, input, border, and accent colors.
6. Add thumbnail previews and Apply/Cancel behavior to the background chooser.
7. Reduce repetitive card height and border density in All Chats and Feed.

## Validation

Before release, validate every captured state again in Light and Dark at text scales 1.0 and 1.3, plus one narrow Android device. Add screenshot/golden coverage for pushed routes and modal sheets because those are where the current theme extension is lost. Enforce at least 4.5:1 for normal text and 3:1 for large text, icons, focus rings, and control boundaries.
