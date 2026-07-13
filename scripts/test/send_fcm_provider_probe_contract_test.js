#!/usr/bin/env node

const assert = require('assert/strict');
const crypto = require('crypto');
const fs = require('fs');
const test = require('node:test');

const {
  RESULT_SCHEMA,
  RPC_STATUS_ALLOWLIST,
  PROVIDER_REASON_ALLOWLIST,
  providerDiagnostic,
} = require('../send_fcm_provider_probe.js');

const expectedKeys = [
  'httpClass',
  'httpStatus',
  'ok',
  'operation',
  'reason',
  'requestIdSha256',
  'rpcStatus',
  'schema',
  'stage',
  'validateOnly',
  'validationResult',
];

function fcmError(status, reason, code = 400) {
  return providerDiagnostic({
    stage: 'fcm',
    statusCode: code,
    validateOnly: true,
    body: {
      error: {
        status,
        message: 'PRIVATE_MESSAGE_CANARY',
        details: [{
          '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
          errorCode: reason,
          token: 'PRIVATE_TOKEN_CANARY',
        }],
      },
    },
  });
}

test('result schema has one exact finite redacted keyset', () => {
  const receipt = providerDiagnostic({
    stage: 'fcm',
    statusCode: 200,
    validateOnly: true,
    headers: {
      'x-request-id': 'PRIVATE_REQUEST_ID_CANARY',
      authorization: 'PRIVATE_JWT_CANARY',
      location: 'https://private.example/messages/secret',
    },
    body: {
      name: 'projects/PRIVATE_PROJECT_CANARY/messages/PRIVATE_MESSAGE_ID',
      payload: 'PRIVATE_PAYLOAD_CANARY',
    },
  });
  assert.equal(receipt.schema, RESULT_SCHEMA);
  assert.deepEqual(Object.keys(receipt).sort(), expectedKeys);
  assert.equal(receipt.ok, true);
  assert.equal(receipt.operation, 'validate_only');
  assert.equal(receipt.validationResult, 'accepted');
  assert.equal(receipt.httpClass, '2xx');
  assert.equal(receipt.httpStatus, 200);
  assert.equal(receipt.rpcStatus, 'OK');
  assert.equal(receipt.reason, null);
  assert.equal(
    receipt.requestIdSha256,
    crypto.createHash('sha256')
      .update('PRIVATE_REQUEST_ID_CANARY')
      .digest('hex'),
  );
  const encoded = JSON.stringify(receipt);
  for (const canary of [
    'PRIVATE_REQUEST_ID_CANARY',
    'PRIVATE_JWT_CANARY',
    'private.example',
    'PRIVATE_PROJECT_CANARY',
    'PRIVATE_MESSAGE_ID',
    'PRIVATE_PAYLOAD_CANARY',
  ]) {
    assert.equal(encoded.includes(canary), false, canary);
  }
});

test('FCM error matrix preserves only allowlisted status and reason', () => {
  const matrix = [
    [400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT'],
    [404, 'NOT_FOUND', 'UNREGISTERED'],
    [403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH'],
    [401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR'],
    [429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'],
    [500, 'INTERNAL', 'INTERNAL'],
    [503, 'UNAVAILABLE', 'UNAVAILABLE'],
  ];
  for (const [code, status, reason] of matrix) {
    const receipt = fcmError(status, reason, code);
    assert.equal(receipt.ok, false);
    assert.equal(receipt.httpClass, `${Math.floor(code / 100)}xx`);
    assert.equal(receipt.httpStatus, code);
    assert.equal(receipt.rpcStatus, status);
    assert.equal(receipt.reason, reason);
    assert.equal(PROVIDER_REASON_ALLOWLIST.has(receipt.reason), true);
    assert.equal(RPC_STATUS_ALLOWLIST.has(receipt.rpcStatus), true);
    const encoded = JSON.stringify(receipt);
    assert.equal(encoded.includes('PRIVATE_MESSAGE_CANARY'), false);
    assert.equal(encoded.includes('PRIVATE_TOKEN_CANARY'), false);
  }
});

test('BadRequest payload and bare target ambiguity remain distinct', () => {
  const payload = providerDiagnostic({
    stage: 'fcm',
    statusCode: 400,
    validateOnly: true,
    body: {
      error: {
        status: 'INVALID_ARGUMENT',
        details: [{
          '@type': 'type.googleapis.com/google.rpc.BadRequest',
          fieldViolations: [{
            field: 'PRIVATE_PAYLOAD_FIELD_CANARY',
            description: 'PRIVATE_DESCRIPTION_CANARY',
          }],
        }],
      },
    },
  });
  assert.equal(payload.reason, 'BAD_REQUEST_PAYLOAD');
  const bare = providerDiagnostic({
    stage: 'fcm',
    statusCode: 400,
    validateOnly: true,
    body: {error: {status: 'INVALID_ARGUMENT'}},
  });
  assert.equal(bare.reason, 'UNKNOWN');
  assert.equal(JSON.stringify(payload).includes('PRIVATE_PAYLOAD_FIELD_CANARY'), false);
  assert.equal(JSON.stringify(payload).includes('PRIVATE_DESCRIPTION_CANARY'), false);
});

test('OAuth and transport failures remain stage-specific and finite', () => {
  const oauth = providerDiagnostic({
    stage: 'oauth',
    statusCode: 400,
    validateOnly: true,
    body: {
      error: 'invalid_grant',
      error_description: 'PRIVATE_KEY_OR_JWT_CANARY',
    },
  });
  assert.equal(oauth.stage, 'oauth');
  assert.equal(oauth.rpcStatus, null);
  assert.equal(oauth.reason, 'INVALID_GRANT');
  assert.equal(JSON.stringify(oauth).includes('PRIVATE_KEY_OR_JWT_CANARY'), false);

  const network = providerDiagnostic({
    stage: 'fcm',
    validateOnly: true,
    networkError: true,
  });
  assert.equal(network.httpClass, 'network');
  assert.equal(network.httpStatus, null);
  assert.equal(network.reason, 'NETWORK_ERROR');

  const malformed = providerDiagnostic({
    stage: 'fcm',
    statusCode: 200,
    validateOnly: true,
    malformedResponse: true,
  });
  assert.equal(malformed.ok, false);
  assert.equal(malformed.reason, 'MALFORMED_RESPONSE');

  const oversized = providerDiagnostic({
    stage: 'fcm',
    statusCode: 500,
    validateOnly: true,
    responseTooLarge: true,
  });
  assert.equal(oversized.reason, 'RESPONSE_TOO_LARGE');
});

test('source sends exact validate_only boolean and never logs raw errors', () => {
  const source = fs.readFileSync(
    'scripts/send_fcm_provider_probe.js',
    'utf8',
  );
  assert.match(source, /\{message, validate_only: validateOnly\}/);
  assert.match(source, /process\.argv\.includes\('--validate-only'\)/);
  assert.doesNotMatch(source, /console\.error\(error\.message\)/);
  assert.doesNotMatch(source, /raw: text/);
  assert.doesNotMatch(source, /console\.log\(JSON\.stringify\(result\.body/);
  assert.doesNotMatch(source, /name:\s*result/);
});
