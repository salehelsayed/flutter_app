/**
 * @fileoverview Bridge entry point for Flutter WebView.
 *
 * This file exposes bridge functions that Flutter's WebView can call
 * via JavaScript channels. Uses real libp2p libraries for crypto.
 */

import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';

interface BridgeResponse {
  ok: boolean;
  requestId?: string;
  identity?: {
    peerId: string;
    publicKey: string;
    privateKey: string;
    mnemonic12: string;
    createdAt: string;
    updatedAt: string;
  };
  errorCode?: string;
  errorMessage?: string;
}

/**
 * Send response back to Flutter via the JavaScript channel.
 */
function sendToFlutter(response: BridgeResponse): void {
  const json = JSON.stringify(response);
  // FlutterChannel is injected by Flutter's WebView
  if ((window as any).FlutterChannel) {
    (window as any).FlutterChannel.postMessage(json);
  } else {
    console.log('[bridge] FlutterChannel not available, response:', json);
  }
}

/**
 * Handle incoming request from Flutter.
 */
async function handleRequest(requestJson: string): Promise<void> {
  let requestId: string | undefined;

  try {
    const request = JSON.parse(requestJson);
    const cmd = request.cmd as string;
    const payload = request.payload || {};
    requestId = request.requestId;

    console.log('[bridge] Received command:', cmd);

    if (cmd === 'identity.generate') {
      const identity = await generateIdentity();
      sendToFlutter({ ok: true, requestId, identity });
      return;
    }

    if (cmd === 'identity.restore') {
      const mnemonic = payload.mnemonic12 as string;
      if (!mnemonic || typeof mnemonic !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'INVALID_MNEMONIC',
          errorMessage: 'Missing or invalid mnemonic12',
        });
        return;
      }
      const identity = await restoreIdentityFromMnemonic(mnemonic);
      sendToFlutter({ ok: true, requestId, identity });
      return;
    }

    sendToFlutter({
      ok: false,
      requestId,
      errorCode: 'UNKNOWN_COMMAND',
      errorMessage: `Unknown command: ${cmd}`,
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const isInvalidMnemonic =
      errorMessage.toLowerCase().includes('mnemonic') ||
      errorMessage.toLowerCase().includes('invalid') ||
      errorMessage.toLowerCase().includes('checksum');

    sendToFlutter({
      ok: false,
      requestId,
      errorCode: isInvalidMnemonic ? 'INVALID_MNEMONIC' : 'INTERNAL_ERROR',
      errorMessage,
    });
  }
}

// Expose to global scope for Flutter WebView to call
(window as any).handleRequest = handleRequest;

// Signal that the bridge is ready
console.log('[core_lib_js] Bridge initialized');
if ((window as any).FlutterChannel) {
  (window as any).FlutterChannel.postMessage(JSON.stringify({ ready: true }));
}
