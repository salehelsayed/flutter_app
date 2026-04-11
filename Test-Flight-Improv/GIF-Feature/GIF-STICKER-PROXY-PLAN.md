# GIF & Sticker Proxy — Implementation Plan

## Context

mknoon is a P2P messaging app (Flutter + Go libp2p relay). Users currently can only send GIFs by picking them from their device's photo library. This plan adds:
- **Part A**: A standalone Go HTTP proxy on EC2 that fronts Giphy/Tenor search & media — users' IPs never touch third-party CDNs
- **Part B**: A GIF/Sticker picker in the Flutter app that feeds into the existing media send pipeline

The proxy is a **separate Go binary** (not bolted onto the relay server) to isolate bursty GIF traffic from message delivery.

---

## Part A — Go GIF Proxy Service

### A.1 Project Location

New directory: `flutter_app/go-gif-proxy/` — separate Go module (`github.com/mknoon/gif-proxy`), same flat `package main` pattern as the relay server.

### A.2 Files To Create

| File | Purpose |
|------|---------|
| `main.go` | Entry point: load config, wire deps, start HTTP on `GIF_PROXY_PORT` (default 8090), Prometheus on `:2113/metrics`, graceful shutdown on SIGINT/SIGTERM |
| `config.go` | `ProxyConfig` struct + `loadConfigFromEnv()` using `envStrOrDefault`/`envIntOrDefault` (same pattern as relay `server_config.go`) |
| `router.go` | `NewRouter(cfg, deps)` → `http.ServeMux` with all route registrations |
| `giphy_client.go` | `GiphyClient.Search(ctx, query, limit, offset)` and `.Trending(ctx, limit)` → normalized `[]GifResult` |
| `tenor_client.go` | `TenorClient.Search(ctx, query, limit, offset)` and `.Featured(ctx, limit)` → same `[]GifResult` |
| `gif_result.go` | Shared types: `GifResult`, `SearchResponse`. URL rewriting: CDN URLs → `https://gif.mknoun.xyz/media/<sha256>?src=<base64url>` |
| `search_handler.go` | `GET /api/v1/search?q=&provider=&limit=&offset=` and `GET /api/v1/trending` — checks search cache, fans out to providers, rewrites URLs, caches response |
| `media_handler.go` | `GET /media/<hash>?src=<encoded-url>` — serves from disk cache or fetches upstream, streams via `io.TeeReader` |
| `search_cache.go` | In-memory TTL cache for search results (key: `provider:query:limit:offset`, TTL: 1 hour, sweep every 5min) |
| `media_cache.go` | Disk LRU cache. Files at `<cache_dir>/<hash[0:2]>/<hash>.bin` + `.meta` sidecar. Configurable max size (default 15GB). `Rebuild()` on startup to reconstruct index from disk |
| `sticker_handler.go` | `GET /api/v1/stickers/packs`, `GET /api/v1/stickers/packs/<id>`, `GET /api/v1/stickers/packs/<id>/assets/<file>` |
| `sticker_store.go` | Reads sticker pack directories from `STICKER_PACKS_DIR`. Each pack = subdirectory with `manifest.json` + image files |
| `metrics.go` | Prometheus metrics: `gifproxy_search_requests_total{provider,cache_hit}`, `gifproxy_media_requests_total{cache_hit}`, `gifproxy_media_bytes_served_total`, `gifproxy_cache_disk_bytes`, `gifproxy_upstream_latency_seconds{provider}` |
| `go.mod` | Module `github.com/mknoon/gif-proxy`, Go 1.25.0 |
| `Makefile` | `build`, `build-linux` (cross-compile), `run`, `tidy`, `clean` |

### A.3 Environment Variables

| Var | Default | Purpose |
|-----|---------|---------|
| `GIF_PROXY_PORT` | `8090` | HTTP listen port |
| `GIF_PROXY_METRICS_PORT` | `2113` | Prometheus metrics port |
| `GIPHY_API_KEY` | (required) | Giphy API key |
| `TENOR_API_KEY` | (required) | Tenor API key |
| `CACHE_DIR` | `/data/gif-cache` | Disk cache directory |
| `CACHE_MAX_BYTES` | `16106127360` (15GB) | Max disk cache size |
| `SEARCH_CACHE_TTL` | `3600` | Search result TTL in seconds |
| `STICKER_PACKS_DIR` | `/data/sticker-packs` | Sticker packs root |
| `PROXY_BASE_URL` | `https://gif.mknoun.xyz` | Base URL for rewritten media URLs |

### A.4 API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/search?q=&provider=&limit=&offset=` | Search GIFs (provider: `giphy`, `tenor`, or omit for both) |
| GET | `/api/v1/trending?provider=&limit=` | Trending GIFs for initial picker view |
| GET | `/media/<hash>?src=<base64url>` | Proxied media file (cache or upstream fetch) |
| GET | `/api/v1/stickers/packs` | List all sticker packs |
| GET | `/api/v1/stickers/packs/<id>` | Single pack manifest + sticker list |
| GET | `/api/v1/stickers/packs/<id>/assets/<file>` | Serve sticker image |
| GET | `/healthz` | Health check (200 OK) |

### A.5 Caching Strategy

**Search results** (in-memory):
- Key: `sha256(provider:query:limit:offset)`
- Value: pre-serialized JSON (already URL-rewritten)
- TTL: 1 hour. Background sweep every 5 min.

**Media files** (disk LRU):
- Key: SHA-256 of original CDN URL
- Layout: `<cache_dir>/<hash[0:2]>/<hash>.bin` + `.meta` (content-type, size, last-access)
- Eviction: oldest-access-first when `currentBytes > maxBytes`, down to 90%
- Startup: `Rebuild()` walks directory, reads `.meta`, reconstructs index

### A.6 Sticker Pack Format

```
/data/sticker-packs/<pack-id>/
  manifest.json
  cover.webp          (96×96 thumbnail)
  salam.webp          (max 512×512, <100KB)
  shukran.webp
  ...
```

`manifest.json`:
```json
{
  "id": "arabic-greetings",
  "name": "Arabic Greetings",
  "author": "mknoon",
  "version": 1,
  "cover": "cover.webp",
  "stickers": [
    { "filename": "salam.webp", "emoji": "👋", "tags": ["hello", "salam"] }
  ]
}
```

### A.7 Architecture Diagram

```
┌──────────┐       ┌──────────────────────────────────────┐       ┌─────────────┐
│  mknoon  │──────▶│  gif.mknoun.xyz (nginx :443 TLS)     │       │ Giphy API   │
│   app    │◀──────│    ↓ proxy_pass                       │       └──────▲──────┘
└──────────┘       │  gif-proxy (:8090)                    │──────────────┤
                   │    ├── search cache (in-memory, 1hr)  │              │
                   │    └── media cache (disk LRU, 15GB)   │       ┌──────┴──────┐
                   └──────────────────────────────────────┘       │ Tenor API   │
                                                                   └─────────────┘
```

### A.8 EC2 Deployment Steps

1. Cross-compile: `GOOS=linux GOARCH=amd64 go build -o gif-proxy .`
2. Upload: `scp -i se.pem gif-proxy ubuntu@13.60.15.36:/tmp/`
3. Install binary: `sudo cp /tmp/gif-proxy /usr/local/bin/gif-proxy`
4. Create env file: `/etc/mknoon/gif-proxy.env`
5. Create dirs: `sudo mkdir -p /data/gif-cache /data/sticker-packs`
6. Create systemd unit: `/etc/systemd/system/gif-proxy.service`
   ```ini
   [Unit]
   Description=GIF Proxy Service
   After=network.target

   [Service]
   EnvironmentFile=/etc/mknoon/gif-proxy.env
   ExecStart=/usr/local/bin/gif-proxy
   Restart=on-failure
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
7. nginx server block: `/etc/nginx/sites-available/gif.mknoun.xyz`
   ```nginx
   server {
       listen 443 ssl http2;
       server_name gif.mknoun.xyz;
       ssl_certificate /etc/letsencrypt/live/mknoun.xyz/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/mknoun.xyz/privkey.pem;
       client_max_body_size 50m;
       location / {
           proxy_pass http://127.0.0.1:8090;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_buffering off;
           proxy_read_timeout 60s;
       }
   }
   ```
8. Cloudflare DNS: A record `gif.mknoun.xyz` → `13.60.15.36`
9. Prometheus: add `gif-proxy` job scraping `localhost:2113` to `/etc/prometheus/prometheus.yml`
10. Verify: `curl https://gif.mknoun.xyz/healthz`

---

## Part B — Flutter App Integration

### B.1 New Files To Create

| File | Purpose |
|------|---------|
| `lib/core/gif_proxy/gif_proxy_client.dart` | HTTP client for the proxy. `search()`, `trending()`, `fetchStickerPacks()`, `downloadGifToTemp(url)` → local `File`. Base URL: `https://gif.mknoun.xyz` |
| `lib/core/gif_proxy/gif_result.dart` | `GifResult` model (id, title, previewUrl, fullUrl, width, height, sizeBytes, provider). `SearchResponse` model. `fromJson` factories |
| `lib/core/gif_proxy/sticker_pack.dart` | `StickerPack` and `Sticker` models with `fromJson` |
| `lib/features/conversation/presentation/widgets/gif_picker_panel.dart` | Modal bottom sheet: search bar + tab row (Trending / Stickers) + results grid. Calls `GifProxyClient`. Returns selected `GifResult` or `Sticker` |
| `lib/features/conversation/presentation/widgets/sticker_pack_browser.dart` | Horizontal pack list + sticker grid per pack |
| `lib/features/conversation/presentation/widgets/gif_grid_item.dart` | Single cell: animated preview via `Image.network`, GIF badge overlay, file size |

### B.2 Existing Files To Modify

**`conversation_wired.dart`** (1:1 chat):
- In `_onAttach()` (~line 2082): add fourth `ListTile` — "GIF & Stickers" with `Icons.gif_box`
- New method `_onPickGif()`:
  1. Show `GifPickerPanel` as modal bottom sheet
  2. On selection: `await gifProxyClient.downloadGifToTemp(result.fullUrl)` → temp file
  3. Create `PendingComposerMedia(file: tempFile, budgetBytes: size)`
  4. Call `_attemptAddPendingMedia([media])` — **reuses entire existing send pipeline**

**`group_conversation_wired.dart`** (group chat):
- Same `_onAttach()` addition (line ~1634) and same `_onPickGif()` method

**`pubspec.yaml`**:
- Add `http: ^1.2.0` dependency

### B.3 How It Hooks Into Existing Pipeline

The key insight: a GIF from the picker is just a local file by the time it enters the pipeline.

```
GIF Picker → download to temp → PendingComposerMedia → _attemptAddPendingMedia()
                                                          ↓
                                              (existing flow from here)
                                                          ↓
                                              AttachmentPreviewStrip shows GIF badge ✓
                                              _onSend() → uploadMedia() ✓
                                              Relay stores blob ✓
                                              Receiver downloads & plays animated ✓
```

No new upload path, no new message type, no relay server changes needed. The existing `MediaAttachment.isAnimated` check, GIF badge rendering, and animation playback all work as-is because the file has `image/gif` MIME.

### B.4 GIF Picker Widget Tree

```
showModalBottomSheet (maxHeight: 60%)
  └── GifPickerPanel
        ├── pill handle (40×4, grey[600])
        ├── TextField (search, debounced 300ms, glassmorphic input style)
        ├── Tab row: "Trending" | "Stickers" (teal accent for active tab)
        └── Expanded
              ├── if Trending/Search: GridView.builder (3 columns, 4px spacing)
              │     └── GifGridItem (animated preview, GIF badge, tap → select)
              │     └── ScrollController for infinite pagination
              └── if Stickers: StickerPackBrowser
                    ├── horizontal scroll of pack covers
                    └── grid of stickers for selected pack
```

Style: `Colors.grey[900]` background (matching existing attach sheet), glassmorphic search input, teal `#4ECDC4` accent for active tab.

---

## Build Sequence

### Phase 1: Go Proxy Service
1. Create `go-gif-proxy/` with `go.mod`, `config.go`, `main.go`
2. Implement `giphy_client.go`, `tenor_client.go`, `gif_result.go`
3. Implement `search_cache.go`, `media_cache.go`
4. Implement `search_handler.go`, `media_handler.go`
5. Implement `sticker_store.go`, `sticker_handler.go`
6. Implement `metrics.go`, `router.go`
7. Add `Makefile`
8. Test locally with real API keys
9. Cross-compile and deploy to EC2
10. Configure nginx, DNS, Prometheus

### Phase 2: Flutter Integration
1. Add `http` to `pubspec.yaml`
2. Create `gif_proxy_client.dart`, models
3. Create `gif_picker_panel.dart`, `gif_grid_item.dart`, `sticker_pack_browser.dart`
4. Modify `conversation_wired.dart` — add GIF option to `_onAttach()`, add `_onPickGif()`
5. Modify `group_conversation_wired.dart` — same changes
6. Test on device

---

## Verification Checklist

- [ ] `curl https://gif.mknoun.xyz/healthz` → 200
- [ ] `curl "https://gif.mknoun.xyz/api/v1/trending?limit=5"` → JSON with rewritten URLs pointing to `gif.mknoun.xyz/media/...`
- [ ] `curl -O "https://gif.mknoun.xyz/media/<hash>?src=<encoded>"` → GIF file downloads
- [ ] Second fetch of same media → served from disk cache (check `gifproxy_media_requests_total{cache_hit="true"}`)
- [ ] In app: `+` → "GIF & Stickers" → trending GIFs load
- [ ] Search "hello" → results appear after debounce
- [ ] Tap GIF → appears in attachment preview strip with GIF badge
- [ ] Send → recipient sees animated GIF in chat
- [ ] Stickers tab → packs load → tap sticker → sends as image
- [ ] Prometheus metrics visible in Grafana
