/**
 * @fileoverview Bridge entry point for Flutter WebView.
 *
 * This file exposes bridge functions that Flutter's WebView can call
 * via JavaScript channels. Uses real libp2p libraries for crypto.
 */

import * as ed from '@noble/ed25519';
import { sha512 } from '@noble/hashes/sha2.js';
import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';
import { signPayload } from '../signing/sign_payload';
import { generateMlKemKeyPair } from '../crypto/keygen_mlkem';
import { encryptMessage } from '../crypto/encrypt_message';
import { decryptMessage } from '../crypto/decrypt_message';

// Polyfill SHA-512 for environments without crypto.subtle (e.g. Flutter WebView)
ed.hashes.sha512 = (msg: Uint8Array) => sha512(msg);
ed.hashes.sha512Async = async (msg: Uint8Array) => sha512(msg);

interface BridgeResponse {
  ok: boolean;
  requestId?: string;
  identity?: {
    peerId: string;
    publicKey: string;
    privateKey: string;
    mnemonic12: string;
    mlKemPublicKey?: string;
    mlKemSecretKey?: string;
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

    if (cmd === 'payload.sign') {
      const { dataToSign, privateKey } = payload;
      if (!dataToSign || typeof dataToSign !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'SIGNING_ERROR',
          errorMessage: 'Missing or invalid dataToSign',
        });
        return;
      }
      if (!privateKey || typeof privateKey !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'INVALID_PRIVATE_KEY',
          errorMessage: 'Missing or invalid privateKey',
        });
        return;
      }
      const signature = await signPayload(dataToSign, privateKey);
      sendToFlutter({ ok: true, requestId, signature } as any);
      return;
    }

    if (cmd === 'mlkem.keygen') {
      const keyPair = generateMlKemKeyPair();
      sendToFlutter({
        ok: true,
        requestId,
        ...keyPair,
      } as any);
      return;
    }

    if (cmd === 'message.encrypt') {
      const { recipientMlKemPublicKey, plaintext } = payload;
      if (!recipientMlKemPublicKey || typeof recipientMlKemPublicKey !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'ENCRYPT_ERROR',
          errorMessage: 'Missing or invalid recipientMlKemPublicKey',
        });
        return;
      }
      if (!plaintext || typeof plaintext !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'ENCRYPT_ERROR',
          errorMessage: 'Missing or invalid plaintext',
        });
        return;
      }
      const result = await encryptMessage(recipientMlKemPublicKey, plaintext);
      sendToFlutter({
        ok: true,
        requestId,
        ...result,
      } as any);
      return;
    }

    if (cmd === 'message.decrypt') {
      const { ownMlKemSecretKey, kem, ciphertext, nonce } = payload;
      if (!ownMlKemSecretKey || typeof ownMlKemSecretKey !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'DECRYPT_ERROR',
          errorMessage: 'Missing or invalid ownMlKemSecretKey',
        });
        return;
      }
      if (!kem || typeof kem !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'DECRYPT_ERROR',
          errorMessage: 'Missing or invalid kem',
        });
        return;
      }
      if (!ciphertext || typeof ciphertext !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'DECRYPT_ERROR',
          errorMessage: 'Missing or invalid ciphertext',
        });
        return;
      }
      if (!nonce || typeof nonce !== 'string') {
        sendToFlutter({
          ok: false,
          requestId,
          errorCode: 'DECRYPT_ERROR',
          errorMessage: 'Missing or invalid nonce',
        });
        return;
      }
      const plaintext = await decryptMessage(ownMlKemSecretKey, kem, ciphertext, nonce);
      sendToFlutter({
        ok: true,
        requestId,
        plaintext,
      } as any);
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
