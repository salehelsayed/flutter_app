# Media Display Spec

Extracted from UI-9 `spec-card-1on1.md` (image/video) + audio additions.

---

## Data Model

### MediaItem

```
type               'image' | 'video' | 'audio'
url                URL or local file path
thumbnailUrl       Optional. Pre-generated thumbnail for fast loading. (image/video only)
width              Original width in pixels (image/video only, null for audio)
height             Original height in pixels (image/video only, null for audio)
duration           Video/audio. Seconds or display string like "0:24".
blurhash           Optional. Placeholder blur hash while loading. (image/video only)
waveform           Optional. Array of 0.0–1.0 floats for audio waveform visualization. (audio only)
```

---

## Exchange Preview — Media Lines

| Scenario | What appears |
|---|---|
| Media-only message | `[icon] Photo` / `[icon] 3 photos` / `[icon] Video` / `[icon] Audio · 0:24` |
| Media + text | `[icon]` badge + caption text |

**Styling:**
- Quote-reply: `↩` arrow before "You:" when the sent message has a `quotedMessageId`.

---

## Message Bubbles — With Media

**With media:**
- Media grid renders inside the bubble, above text
- Text below media = caption
- Media-only: just grid + timestamp, no empty paragraph

---

## Media Messages

### Content Combinations

A message can be: text-only, media-only, or text + media. The `media` array can hold multiple items (batch send).

### Grid Layouts

| Count | Layout | Aspect |
|---|---|---|
| 1 | Full width | 4:3 |
| 2 | Side by side | 1:1 each |
| 3 | 1 top (full), 2 bottom (half) | Top: 2:1, Bottom: 1:1 |
| 4 | 2×2 grid | 1:1 each |
| 5+ | 2×2 for first 4, "+N" overlay on 4th | 1:1 each |

- Gap: 3px
- Container border-radius: 10px (clips children)
- Item border-radius: 4px
- `object-fit: cover`
- Grid placed inside bubble, above any text

### Video Thumbnail

- Semi-transparent dark overlay (~30% black)
- Centered play icon (filled triangle, white, ~28px)
- Duration badge below play icon (small, dark pill background)
- Tapping opens the video player

### Audio Player

Audio does not appear in the media grid. It renders as an inline player widget inside the bubble.

```
+--------------------------------------------+
|  [play/pause]  |||||||||||||||---  1:24     |
|                                   9:45 AM  |
+--------------------------------------------+
```

| Element | Details |
|---|---|
| Play/pause button | Circle, 32px, teal ~20% background, play/pause icon 14px teal |
| Waveform bar | Horizontal waveform visualization from `waveform` data. Played portion: teal. Unplayed portion: white ~15%. Height: 28px. Tappable to seek. |
| Duration | Right-aligned. While playing: shows elapsed / total (e.g. "0:47 / 1:24"). While paused: shows total only. 11px, muted. |
| Scrub | Tap or drag on waveform to seek to position |

**Sent audio:** Same layout, indented 24px left like sent bubbles, teal accent right border.

**Audio + caption:** Waveform player above caption text, same as image grid above caption.

**Audio in a mixed message (audio + images):** Audio player renders below the image grid, above caption text. Audio is never part of the grid itself.

### Media in Collapsed Preview

| Content | Preview |
|---|---|
| 1 image, no text | `[camera-icon] Photo` |
| 3 images, no text | `[camera-icon] 3 photos` |
| 1 video, no text | `[video-icon] Video` |
| 1 audio, no text | `[mic-icon] Audio · 0:24` |
| Image + caption | `[camera-icon]` + caption text |
| Mixed types | `[camera-icon] 2 photos · Video` |
| Audio + caption | `[mic-icon] Audio · 0:24` + caption text |

Icon: 11-13px, same muted color as the name label.

### Edge Cases

- **Image load failure**: Placeholder rectangle with muted icon. Same aspect ratio. Grid does not collapse.
- **No video thumbnail**: Dark rectangle with play icon + duration.
- **Mixed image + video in one message**: Same grid. Video items get overlay.
- **5+ items**: First 4 in grid, 4th gets "+N" dark overlay. Tap opens gallery.
- **Media-only message**: Bubble = grid + timestamp. No empty `<p>`.
- **Sending media**: Show local file immediately (optimistic). Loading indicator on thumbnail. Replace URL on upload complete.
- **Aspect ratio**: `object-fit: cover` means some cropping. Tap to view full resolution.
- **Audio load failure**: Waveform placeholder with muted mic icon. Duration shows "--:--". Tap shows retry.
- **Audio without waveform data**: Flat horizontal line in place of waveform. Seek still works.
- **Voice message vs file audio**: No distinction in rendering. Both use the same inline player.

---

## Visual Design Tokens — Media Grid

```
Grid:           gap 3px, radius 10px, overflow hidden
Items:          radius 4px, bg white ~3% (placeholder), object-fit cover
Video overlay:  bg black ~30%, play icon white ~90% 28px
Duration:       11px, weight 600, white ~80%, bg black ~40%, pad 2px 6px, radius 4px
```

## Visual Design Tokens — Audio Player

```
Container:      full bubble width, pad 10px 14px
Play/pause:     32px circle, bg teal ~20%, icon 14px teal
Waveform:       height 28px, bar-width 2px, gap 1px
  Played:       teal ~70%
  Unplayed:     white ~15%
  Scrub dot:    8px circle, teal, centered on current position
Duration:       11px, ~25%, right-aligned
  Playing:      "0:47 / 1:24"
  Paused:       "1:24"
```

## Visual Design Tokens — Exchange Preview (media icons)

```
Media icon:     11-13px, ~40% (received) or teal ~45% (sent)
```

---

## Quote-Reply — Media Edge Cases

- **Quoting media**: Quote bar shows "Photo", "Video", or "Audio · 0:24". If it had a caption, show the caption.
