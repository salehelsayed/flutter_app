// core_lib_js/src/bridge/handlers.ts

import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';
import { signPayload } from '../signing/sign_payload';
import { emitFlowEvent } from '../utils/flow_events';

// Handler registry
const handlers = new Map<string, (payload: any, requestId?: string) => Promise<any>>();

// ============================================
// M1 HANDLERS (existing)
// ============================================

handlers.set('identity.generate', async (_payload, requestId) => {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_GENERATE_START',
    details: { requestId },
  });

  try {
    const identity = await generateIdentity();

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_GENERATE_SUCCESS',
      details: { requestId },
    });

    return {
      ok: true,
      requestId,
      identity,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_GENERATE_ERROR',
      details: { error: errorMessage, requestId },
    });

    return {
      ok: false,
      requestId,
      errorCode: 'INTERNAL_ERROR',
      errorMessage,
    };
  }
});

handlers.set('identity.restore', async (payload, requestId) => {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_RESTORE_START',
    details: { requestId },
  });

  try {
    if (!payload.mnemonic || typeof payload.mnemonic !== 'string') {
      return {
        ok: false,
        requestId,
        errorCode: 'INVALID_MNEMONIC',
        errorMessage: 'Missing or invalid mnemonic',
      };
    }

    const identity = await restoreIdentityFromMnemonic(payload.mnemonic);

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_RESTORE_SUCCESS',
      details: { requestId },
    });

    return {
      ok: true,
      requestId,
      identity,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_RESTORE_ERROR',
      details: { error: errorMessage, requestId },
    });

    return {
      ok: false,
      requestId,
      errorCode: 'INTERNAL_ERROR',
      errorMessage,
    };
  }
});

// ============================================
// M2 HANDLERS (new)
// ============================================

handlers.set('payload.sign', async (payload: {
  dataToSign?: string;
  privateKey?: string;
}, requestId?: string) => {
  emitFlowEvent({
    layer: 'JS',
    event: 'QR_JS_BRIDGE_SIGN_RECEIVED',
    details: { dataLength: payload.dataToSign?.length ?? 0, requestId },
  });

  try {
    // Validate required fields
    if (!payload.dataToSign || typeof payload.dataToSign !== 'string') {
      return {
        ok: false,
        requestId,
        errorCode: 'SIGNING_ERROR',
        errorMessage: 'Missing or invalid dataToSign',
      };
    }
    if (!payload.privateKey || typeof payload.privateKey !== 'string') {
      return {
        ok: false,
        requestId,
        errorCode: 'INVALID_PRIVATE_KEY',
        errorMessage: 'Missing or invalid privateKey',
      };
    }

    // Call signing function
    const signature = await signPayload(payload.dataToSign, payload.privateKey);

    emitFlowEvent({
      layer: 'JS',
      event: 'QR_JS_BRIDGE_SIGN_SUCCESS',
      details: { requestId },
    });

    return {
      ok: true,
      requestId,
      signature,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);

    // Map error to appropriate error code
    let errorCode = 'INTERNAL_ERROR';
    if (errorMessage.includes('private key') || errorMessage.includes('key')) {
      errorCode = 'INVALID_PRIVATE_KEY';
    } else if (errorMessage.includes('sign')) {
      errorCode = 'SIGNING_ERROR';
    }

    emitFlowEvent({
      layer: 'JS',
      event: 'QR_JS_BRIDGE_SIGN_ERROR',
      details: { errorCode, error: errorMessage, requestId },
    });

    return {
      ok: false,
      requestId,
      errorCode,
      errorMessage,
    };
  }
});

// ============================================
// DISPATCHER (existing)
// ============================================

export async function handleBridgeMessage(message: {
  cmd: string;
  requestId?: string;
  payload: any;
}): Promise<any> {
  const handler = handlers.get(message.cmd);
  if (!handler) {
    return {
      ok: false,
      requestId: message.requestId,
      errorCode: 'UNKNOWN_COMMAND',
      errorMessage: `Unknown command: ${message.cmd}`,
    };
  }
  return handler(message.payload, message.requestId);
}

export { handlers };
