# Task Prompt: FL_XS_16 - Implement Real JS Bridge Connection (WebView)

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

Problem:
  The current ProductionJsBridge in main.dart is a STUB that returns fake/demo data.
  The real JS code in core_lib_js/ that generates actual BIP39 mnemonics is never called.

  Current stub returns:
    'mnemonic12': 'demo seed phrase twelve words here for testing the app behavior okay now'

  This must be replaced with a real bridge that executes the JS code.

Solution:
  Use WebView-based bridge to run JavaScript with full browser crypto APIs.
  This enables real libp2p library calls:
    - import { generateKeyPair } from '@libp2p/crypto/keys';
    - import { peerIdFromPrivateKey } from '@libp2p/peer-id';

Tech Stack:
  - Flutter: webview_flutter package for JavaScript runtime
  - JS Bundle: esbuild-compiled bundle from core_lib_js/ for browser platform
  - Message Protocol: JSON-based request/response via JavaScript channels

JS Bridge Contract (from GLOBAL_CONTEXT.md):
  Request format:
    { "cmd": "identity.generate", "payload": {}, "requestId": "req_1" }
    { "cmd": "identity.restore", "payload": { "mnemonic12": "..." }, "requestId": "req_2" }

  Response format:
    { "ok": true, "requestId": "req_1", "identity": { ... } }
    { "ok": false, "requestId": "req_1", "errorCode": "...", "errorMessage": "..." }
```

---

## Task Definition

```
[TASK FL_XS_16 – Implement Real JS Bridge Connection via WebView]

Owner: FL

Goal:
  Replace the stub ProductionJsBridge with a WebView-based implementation that:
  1. Loads and executes actual JavaScript code from core_lib_js
  2. Uses real libp2p libraries for Ed25519 keypair and peer ID generation
  3. Returns real BIP39 mnemonics

What to implement:

  Part 1 - Bundle JS Code for Browser:
    - Update package.json with esbuild and libp2p dependencies
    - Bundle core_lib_js into a single JS file for browser platform
    - Output bundle to assets/js/core_lib.js
    - Create bridge.html that loads the bundle

  Part 2 - WebView JsBridge Implementation:
    - Use webview_flutter package
    - Create WebViewController that loads bridge.html with inline JS
    - Implement JavaScript channel for bidirectional communication
    - Handle async request/response with requestId correlation

  Part 3 - Update main.dart:
    - Initialize the WebView bridge asynchronously
    - Replace ProductionJsBridge with WebViewJsBridge

Inputs:
  - JSON request string with cmd, payload, and requestId

Outputs:
  - JSON response string with ok, requestId, identity/error fields
  - Real BIP39 mnemonics (not fake data)
  - Real Ed25519 keys and libp2p peer IDs

Flow_events:
  - At bridge initialization:
      - layer: "FL"
      - event: "ID_BRIDGE_INIT_START"
      - details: { "type": "webview" }
  - On successful initialization:
      - layer: "FL"
      - event: "ID_BRIDGE_INIT_SUCCESS"
      - details: { "type": "webview" }
  - On initialization error:
      - layer: "FL"
      - event: "ID_BRIDGE_INIT_ERROR"
      - details: { "error": "<error_message>" }

Constraints:
  - Must work on iOS, Android (WebView available on both)
  - WebView must be initialized before any bridge calls
  - Handle WebView errors gracefully
  - Bundle must include all libp2p dependencies

Deliverables:
  1. core_lib_js/package.json (updated with build script)
  2. core_lib_js/src/bridge/entry.ts (WebView bridge entry point)
  3. assets/js/bridge.html
  4. assets/js/core_lib.js (generated bundle)
  5. lib/core/bridge/webview_js_bridge.dart
  6. Updated lib/main.dart
  7. Updated pubspec.yaml
```

---

## Output Requirements

### 1. core_lib_js/package.json

```json
{
  "name": "core_lib_js",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "esbuild src/bridge/entry.ts --bundle --outfile=../assets/js/core_lib.js --format=iife --platform=browser --target=es2020 --define:global=globalThis"
  },
  "dependencies": {
    "bip39": "^3.1.0",
    "@libp2p/crypto": "^5.0.0",
    "@libp2p/peer-id": "^5.0.0"
  },
  "devDependencies": {
    "esbuild": "^0.20.0",
    "typescript": "^5.0.0"
  }
}
```

### 2. core_lib_js/src/bridge/entry.ts

```typescript
import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';

// Handle incoming request from Flutter
async function handleRequest(requestJson: string): Promise<void> {
  let requestId: string | undefined;
  try {
    const request = JSON.parse(requestJson);
    const cmd = request.cmd;
    const payload = request.payload || {};
    requestId = request.requestId;

    if (cmd === 'identity.generate') {
      const identity = await generateIdentity();
      sendToFlutter({ ok: true, requestId, identity });
      return;
    }

    if (cmd === 'identity.restore') {
      const identity = await restoreIdentityFromMnemonic(payload.mnemonic12);
      sendToFlutter({ ok: true, requestId, identity });
      return;
    }

    sendToFlutter({ ok: false, requestId, errorCode: 'UNKNOWN_COMMAND', errorMessage: `Unknown: ${cmd}` });
  } catch (error) {
    sendToFlutter({ ok: false, requestId, errorCode: 'INTERNAL_ERROR', errorMessage: String(error) });
  }
}

function sendToFlutter(response: object): void {
  if ((window as any).FlutterChannel) {
    (window as any).FlutterChannel.postMessage(JSON.stringify(response));
  }
}

(window as any).handleRequest = handleRequest;
```

### 3. pubspec.yaml additions

```yaml
dependencies:
  webview_flutter: ^4.10.0

flutter:
  assets:
    - assets/js/
```

### 4. lib/core/bridge/webview_js_bridge.dart

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'js_bridge_client.dart';

class WebViewJsBridge extends JsBridge {
  WebViewController? _controller;
  bool _initialized = false;
  int _requestId = 0;
  final Map<String, Completer<String>> _pendingRequests = {};

  Future<void> initialize() async {
    final htmlContent = await rootBundle.loadString('assets/js/bridge.html');
    final jsCode = await rootBundle.loadString('assets/js/core_lib.js');
    final fullHtml = htmlContent.replaceFirst(
      '<script src="core_lib.js"></script>',
      '<script>$jsCode</script>',
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterChannel', onMessageReceived: _onMessage)
      ..loadHtmlString(fullHtml);

    _initialized = true;
  }

  void _onMessage(JavaScriptMessage message) {
    final data = jsonDecode(message.message);
    final requestId = data['requestId'] as String?;
    if (requestId != null && _pendingRequests.containsKey(requestId)) {
      _pendingRequests[requestId]!.complete(message.message);
      _pendingRequests.remove(requestId);
    }
  }

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message);
    final requestId = 'req_${++_requestId}';
    request['requestId'] = requestId;

    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;

    final escaped = jsonEncode(request).replaceAll("'", "\\'");
    await _controller!.runJavaScript("handleRequest('$escaped')");

    return completer.future.timeout(Duration(seconds: 30));
  }
}
```

### 5. Updated main.dart

```dart
import 'package:flutter_app/core/bridge/webview_js_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... database init ...

  final bridge = WebViewJsBridge();
  await bridge.initialize();

  runApp(MyApp(repository: repository, bridge: bridge));
}
```

---

## Build Steps

1. Install npm dependencies:
   ```bash
   cd core_lib_js && npm install
   ```

2. Build JS bundle:
   ```bash
   npm run build
   ```

3. Get Flutter dependencies:
   ```bash
   flutter pub get
   ```

4. Run the app:
   ```bash
   flutter run
   ```

---

## Verification

1. Generate new identity - mnemonic should be 12 real BIP39 words
2. Check database:
   ```bash
   sqlite3 identity.db "SELECT mnemonic12 FROM identity WHERE id=1;"
   ```
3. Peer ID should start with "12D3KooW" (libp2p Ed25519 format)

---

## Begin Implementation

All files have been implemented. Run the build steps above to test.
