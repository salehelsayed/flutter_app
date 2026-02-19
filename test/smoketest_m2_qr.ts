/**
 * M2 QR Generation Smoketest
 *
 * Tests the complete QR generation flow:
 *   1. JS signPayload() signs data with Ed25519
 *   2. Dart-equivalent buildQRPayload logic (tested via Dart script)
 *   3. Flow events fire in expected sequence
 *   4. Payload contains all required fields with sorted keys
 *
 * Run: npx ts-node --esm test/smoketest_m2_qr.ts
 */

import * as ed from '@noble/ed25519';

// ── Flow event capture ──────────────────────────────────────────────

const flowEvents: string[] = [];

function emitFlowEvent(p: { layer: string; event: string; details: Record<string, unknown> }) {
  flowEvents.push(p.event);
  console.log(`  [FLOW] ${p.layer} | ${p.event} | ${JSON.stringify(p.details)}`);
}

// ── signPayload (inline from core_lib_js) ───────────────────────────

async function signPayload(dataToSign: string, privateKeyBase64: string): Promise<string> {
  emitFlowEvent({ layer: 'JS', event: 'QR_JS_SIGN_PAYLOAD_START', details: { dataLength: dataToSign.length } });

  const privateKeyBytes = Buffer.from(privateKeyBase64, 'base64');
  const seed = privateKeyBytes.length === 64 ? privateKeyBytes.slice(0, 32) : privateKeyBytes;
  const messageBytes = new TextEncoder().encode(dataToSign);
  const signature = await ed.signAsync(messageBytes, seed);
  const signatureBase64 = Buffer.from(signature).toString('base64');

  emitFlowEvent({ layer: 'JS', event: 'QR_JS_SIGN_PAYLOAD_SUCCESS', details: { signatureLength: signatureBase64.length } });
  return signatureBase64;
}

// ── Bridge handler (inline from handlers.ts) ────────────────────────

async function handlePayloadSign(payload: { dataToSign: string; privateKey: string }): Promise<any> {
  emitFlowEvent({ layer: 'JS', event: 'QR_JS_BRIDGE_SIGN_RECEIVED', details: { dataLength: payload.dataToSign.length } });

  if (!payload.dataToSign || typeof payload.dataToSign !== 'string') {
    return { ok: false, errorCode: 'SIGNING_ERROR', errorMessage: 'Missing or invalid dataToSign' };
  }
  if (!payload.privateKey || typeof payload.privateKey !== 'string') {
    return { ok: false, errorCode: 'INVALID_PRIVATE_KEY', errorMessage: 'Missing or invalid privateKey' };
  }

  const signature = await signPayload(payload.dataToSign, payload.privateKey);
  emitFlowEvent({ layer: 'JS', event: 'QR_JS_BRIDGE_SIGN_SUCCESS', details: {} });
  return { ok: true, signature };
}

// ── buildQRPayload (Dart logic replicated) ──────────────────────────

const RENDEZVOUS_ADDRESS = '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

interface Identity {
  peerId: string;
  publicKey: string;
  privateKey: string;
}

async function buildQRPayload(
  identity: Identity | null,
  callJsSign: (data: string, key: string) => Promise<any>,
): Promise<{ result: string; qrString: string | null }> {
  emitFlowEvent({ layer: 'FL', event: 'QR_FL_SCREEN_INIT', details: {} });
  emitFlowEvent({ layer: 'FL', event: 'QR_FL_SCREEN_LOADING', details: {} });
  emitFlowEvent({ layer: 'FL', event: 'QR_FL_BUILD_PAYLOAD_START', details: {} });

  if (!identity) {
    emitFlowEvent({ layer: 'FL', event: 'QR_FL_BUILD_PAYLOAD_NO_IDENTITY', details: {} });
    emitFlowEvent({ layer: 'FL', event: 'QR_FL_SCREEN_ERROR', details: { reason: 'noIdentity' } });
    return { result: 'noIdentity', qrString: null };
  }

  emitFlowEvent({ layer: 'FL', event: 'QR_FL_BUILD_PAYLOAD_IDENTITY_LOADED', details: { peerId: identity.peerId.substring(0, 12) } });

  // Build unsigned payload with sorted keys
  const ts = new Date().toISOString();
  const unsignedPayload: Record<string, string> = {
    ns: identity.peerId,
    pk: identity.publicKey,
    rv: RENDEZVOUS_ADDRESS,
    ts,
  };

  // Canonical JSON (sorted keys)
  const sortedKeys = Object.keys(unsignedPayload).sort();
  const sorted: Record<string, string> = {};
  for (const k of sortedKeys) sorted[k] = unsignedPayload[k];
  const dataToSign = JSON.stringify(sorted);

  emitFlowEvent({ layer: 'FL', event: 'QR_FL_BUILD_PAYLOAD_SIGNING', details: {} });
  emitFlowEvent({ layer: 'FL', event: 'QR_FL_BRIDGE_SIGN_REQUEST', details: { dataLength: dataToSign.length } });

  const signResponse = await callJsSign(dataToSign, identity.privateKey);

  emitFlowEvent({ layer: 'FL', event: 'QR_FL_BRIDGE_SIGN_RESPONSE', details: { ok: signResponse.ok } });

  if (!signResponse.ok) {
    emitFlowEvent({ layer: 'FL', event: 'QR_FL_BUILD_PAYLOAD_ERROR', details: { errorCode: signResponse.errorCode } });
    emitFlowEvent({ layer: 'FL', event: 'QR_FL_SCREEN_ERROR', details: { reason: 'signingError' } });
    return { result: 'signingError', qrString: null };
  }

  const signedPayload = { ...sorted, sig: signResponse.signature };
  const signedSorted: Record<string, string> = {};
  for (const k of Object.keys(signedPayload).sort()) signedSorted[k] = signedPayload[k];
  const finalJson = JSON.stringify(signedSorted);

  emitFlowEvent({ layer: 'FL', event: 'QR_FL_BUILD_PAYLOAD_SUCCESS', details: {} });
  emitFlowEvent({ layer: 'FL', event: 'QR_FL_SCREEN_DISPLAY', details: {} });

  return { result: 'success', qrString: finalJson };
}

// ── Assertions ──────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function assert(condition: boolean, msg: string) {
  if (condition) {
    console.log(`  ✓ ${msg}`);
    passed++;
  } else {
    console.log(`  ✗ FAIL: ${msg}`);
    failed++;
  }
}

// ── Main ────────────────────────────────────────────────────────────

async function main() {
  console.log('══════════════════════════════════════════════════════════');
  console.log('M2 QR Generation Smoketest');
  console.log('══════════════════════════════════════════════════════════\n');

  // Generate a real Ed25519 key pair for testing
  const privateKey = ed.utils.randomSecretKey();
  const publicKey = await ed.getPublicKeyAsync(privateKey);
  const privateKeyBase64 = Buffer.from(privateKey).toString('base64');
  const publicKeyBase64 = Buffer.from(publicKey).toString('base64');
  const peerId = '12D3KooWTestSmokeTestPeerIdValue1234567890';

  const identity: Identity = {
    peerId,
    publicKey: publicKeyBase64,
    privateKey: privateKeyBase64,
  };

  // ── Test 1: Happy path ──────────────────────────────────────────

  console.log('── Test 1: Happy Path (end-to-end) ──\n');
  flowEvents.length = 0;

  const { result, qrString } = await buildQRPayload(identity, (data, key) => handlePayloadSign({ dataToSign: data, privateKey: key }));

  console.log('');
  assert(result === 'success', 'Result is success');
  assert(qrString !== null, 'QR string is not null');

  const payload = JSON.parse(qrString!);
  assert(payload.pk === publicKeyBase64, `pk matches (${payload.pk.substring(0, 20)}...)`);
  assert(payload.ns === peerId, `ns matches peerId`);
  assert(payload.rv === RENDEZVOUS_ADDRESS, `rv is rendezvous address`);
  assert(typeof payload.ts === 'string' && payload.ts.length > 0, `ts is non-empty ISO string`);
  assert(typeof payload.sig === 'string' && payload.sig.length > 0, `sig is non-empty base64`);

  // Verify sorted keys
  const keys = Object.keys(payload);
  const expectedKeys = ['ns', 'pk', 'rv', 'sig', 'ts'];
  assert(JSON.stringify(keys) === JSON.stringify(expectedKeys), `Keys sorted: ${keys.join(', ')}`);

  // Verify signature is valid Ed25519
  const sigBytes = Buffer.from(payload.sig, 'base64');
  const dataWithoutSig = { ...payload };
  delete dataWithoutSig.sig;
  const dataBytes = new TextEncoder().encode(JSON.stringify(dataWithoutSig));
  const valid = await ed.verifyAsync(sigBytes, dataBytes, publicKey);
  assert(valid === true, 'Ed25519 signature is cryptographically valid');

  // ── Test 2: Flow event sequence ─────────────────────────────────

  console.log('\n── Test 2: Flow Event Sequence ──\n');

  const expectedEvents = [
    'QR_FL_SCREEN_INIT',
    'QR_FL_SCREEN_LOADING',
    'QR_FL_BUILD_PAYLOAD_START',
    'QR_FL_BUILD_PAYLOAD_IDENTITY_LOADED',
    'QR_FL_BUILD_PAYLOAD_SIGNING',
    'QR_FL_BRIDGE_SIGN_REQUEST',
    'QR_JS_BRIDGE_SIGN_RECEIVED',
    'QR_JS_SIGN_PAYLOAD_START',
    'QR_JS_SIGN_PAYLOAD_SUCCESS',
    'QR_JS_BRIDGE_SIGN_SUCCESS',
    'QR_FL_BRIDGE_SIGN_RESPONSE',
    'QR_FL_BUILD_PAYLOAD_SUCCESS',
    'QR_FL_SCREEN_DISPLAY',
  ];

  assert(flowEvents.length === expectedEvents.length, `Event count: ${flowEvents.length} === ${expectedEvents.length}`);

  for (let i = 0; i < expectedEvents.length; i++) {
    const actual = flowEvents[i] ?? '(missing)';
    const expected = expectedEvents[i];
    assert(actual === expected, `Event[${i}]: ${actual}`);
  }

  // ── Test 3: No identity path ────────────────────────────────────

  console.log('\n── Test 3: No Identity Path ──\n');
  flowEvents.length = 0;

  const noIdResult = await buildQRPayload(null, (data, key) => handlePayloadSign({ dataToSign: data, privateKey: key }));

  console.log('');
  assert(noIdResult.result === 'noIdentity', 'Result is noIdentity');
  assert(noIdResult.qrString === null, 'QR string is null');
  assert(flowEvents.includes('QR_FL_BUILD_PAYLOAD_NO_IDENTITY'), 'NO_IDENTITY event emitted');
  assert(flowEvents.includes('QR_FL_SCREEN_ERROR'), 'SCREEN_ERROR event emitted');

  // ── Test 4: Re-generation produces new timestamp ────────────────

  console.log('\n── Test 4: Re-generation ──\n');

  const { qrString: qr1 } = await buildQRPayload(identity, (data, key) => handlePayloadSign({ dataToSign: data, privateKey: key }));
  await new Promise(r => setTimeout(r, 50)); // small delay
  const { qrString: qr2 } = await buildQRPayload(identity, (data, key) => handlePayloadSign({ dataToSign: data, privateKey: key }));

  const p1 = JSON.parse(qr1!);
  const p2 = JSON.parse(qr2!);

  assert(p1.pk === p2.pk, 'pk unchanged across generations');
  assert(p1.ns === p2.ns, 'ns unchanged across generations');
  assert(p1.rv === p2.rv, 'rv unchanged across generations');
  assert(p1.ts !== p2.ts, `ts differs: ${p1.ts} vs ${p2.ts}`);
  assert(p1.sig !== p2.sig, 'sig differs (data changed)');

  // ── Summary ─────────────────────────────────────────────────────

  console.log('\n══════════════════════════════════════════════════════════');
  console.log(`Results: ${passed} passed, ${failed} failed`);
  console.log('══════════════════════════════════════════════════════════');

  if (failed > 0) {
    process.exit(1);
  }
}

main().catch(err => {
  console.error('Smoketest crashed:', err);
  process.exit(1);
});
