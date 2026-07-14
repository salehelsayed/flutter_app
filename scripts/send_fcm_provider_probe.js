#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const https = require('https');

const EXIT_OAUTH = 70;
const EXIT_PROVIDER_SEND = 71;
const EXIT_REQUEST_PREPARE = 72;
const RESULT_SCHEMA = 'mknoon.fcm-provider-result.v1';

const RPC_STATUS_ALLOWLIST = new Set([
  'OK',
  'CANCELLED',
  'UNKNOWN',
  'INVALID_ARGUMENT',
  'DEADLINE_EXCEEDED',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'PERMISSION_DENIED',
  'RESOURCE_EXHAUSTED',
  'FAILED_PRECONDITION',
  'ABORTED',
  'OUT_OF_RANGE',
  'UNIMPLEMENTED',
  'INTERNAL',
  'UNAVAILABLE',
  'DATA_LOSS',
  'UNAUTHENTICATED',
]);

const PROVIDER_REASON_ALLOWLIST = new Set([
  'UNSPECIFIED_ERROR',
  'INVALID_ARGUMENT',
  'UNREGISTERED',
  'SENDER_ID_MISMATCH',
  'QUOTA_EXCEEDED',
  'UNAVAILABLE',
  'INTERNAL',
  'THIRD_PARTY_AUTH_ERROR',
  'APNS_AUTH_ERROR',
  'INVALID_GRANT',
  'INVALID_CLIENT',
  'UNAUTHORIZED_CLIENT',
  'INVALID_SCOPE',
  'TEMPORARILY_UNAVAILABLE',
  'SERVER_ERROR',
  'NETWORK_ERROR',
  'MALFORMED_RESPONSE',
  'RESPONSE_TOO_LARGE',
  'BAD_REQUEST_PAYLOAD',
  'UNKNOWN',
]);

const REQUEST_ID_HEADER_ALLOWLIST = [
  'x-request-id',
  'x-google-request-id',
  'x-guploader-uploadid',
  'x-cloud-trace-context',
];
const MAX_RESPONSE_BYTES = 64 * 1024;

class ProviderPhaseFailure extends Error {
  constructor(phase, diagnostic) {
    super(phase);
    this.phase = phase;
    this.diagnostic = diagnostic;
  }
}

class ProviderHttpFailure extends Error {
  constructor(diagnostic) {
    super('provider_http_failure');
    this.diagnostic = diagnostic;
  }
}

function usage() {
  console.error(`Usage:
  FIREBASE_SERVICE_ACCOUNT=/path/service-account.json \\
    node scripts/send_fcm_provider_probe.js --token <fcm-token> [--project <project-id>] [--probe-id <id>] [--mode visible|data-only] [--kind group|chat] [--validate-only]

  node scripts/send_fcm_provider_probe.js --request-file <private-json> \\
    --service-account <service-account.json> --mode data-only \\
    --kind reaction|chat|group|announcement [--validate-only]

Calls Firebase Cloud Messaging v1 for one token. --validate-only asks FCM to
validate the request without delivering it. Output is a finite redacted receipt.
`);
  process.exit(2);
}

function arg(name, fallback = null) {
  const index = process.argv.indexOf(`--${name}`);
  if (index < 0) return fallback;
  return process.argv[index + 1] || usage();
}

function base64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function normalizedAllowlisted(value, allowlist) {
  const normalized = typeof value === 'string'
    ? value.trim().replace(/-/g, '_').toUpperCase()
    : '';
  return allowlist.has(normalized) ? normalized : null;
}

function requestIdHash(headers) {
  for (const name of REQUEST_ID_HEADER_ALLOWLIST) {
    const raw = headers && headers[name];
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (typeof value === 'string' && value.trim()) {
      return crypto.createHash('sha256').update(value.trim()).digest('hex');
    }
  }
  return null;
}

function httpClass(statusCode) {
  return Number.isInteger(statusCode) && statusCode >= 100 && statusCode <= 599
    ? `${Math.floor(statusCode / 100)}xx`
    : 'unknown';
}

function googleError(body) {
  return body && typeof body === 'object' &&
    body.error && typeof body.error === 'object' &&
    !Array.isArray(body.error)
    ? body.error
    : null;
}

function fcmReason(body) {
  const error = googleError(body);
  const details = error && Array.isArray(error.details) ? error.details : [];
  for (const detail of details) {
    if (!detail || typeof detail !== 'object' || Array.isArray(detail)) continue;
    if (detail['@type'] !==
        'type.googleapis.com/google.firebase.fcm.v1.FcmError') continue;
    const reason = normalizedAllowlisted(
      detail.errorCode || detail.error_code,
      PROVIDER_REASON_ALLOWLIST,
    );
    if (reason) return reason;
  }
  const badRequest = details.some((detail) =>
    detail && detail['@type'] === 'type.googleapis.com/google.rpc.BadRequest'
  );
  if (badRequest) return 'BAD_REQUEST_PAYLOAD';
  return 'UNKNOWN';
}

function oauthReason(body) {
  const candidate = body && typeof body === 'object' &&
    typeof body.error === 'string'
    ? body.error
    : null;
  return normalizedAllowlisted(candidate, PROVIDER_REASON_ALLOWLIST) || 'UNKNOWN';
}

function providerDiagnostic({
  stage,
  statusCode = null,
  headers = {},
  body = {},
  validateOnly = false,
  networkError = false,
  malformedResponse = false,
  responseTooLarge = false,
}) {
  const safeStage = ['oauth', 'fcm', 'request_prepare'].includes(stage)
    ? stage
    : 'request_prepare';
  const httpSuccess = Number.isInteger(statusCode) &&
    statusCode >= 200 && statusCode < 300;
  const success = httpSuccess && !malformedResponse && !responseTooLarge;
  const error = googleError(body);
  const rpcStatus = safeStage === 'fcm'
    ? (success
        ? 'OK'
        : normalizedAllowlisted(error && error.status, RPC_STATUS_ALLOWLIST))
    : null;
  let reason = null;
  if (!success) {
    reason = networkError
      ? 'NETWORK_ERROR'
      : responseTooLarge
        ? 'RESPONSE_TOO_LARGE'
        : malformedResponse
          ? 'MALFORMED_RESPONSE'
          : safeStage === 'oauth'
            ? oauthReason(body)
            : safeStage === 'fcm'
              ? fcmReason(body)
              : 'UNKNOWN';
    if (!PROVIDER_REASON_ALLOWLIST.has(reason)) reason = 'UNKNOWN';
  }
  return {
    schema: RESULT_SCHEMA,
    ok: success,
    stage: safeStage,
    operation: validateOnly ? 'validate_only' : 'deliver',
    validateOnly,
    validationResult: validateOnly
      ? (success ? 'accepted' : 'rejected')
      : 'not_run',
    httpClass: networkError ? 'network' : httpClass(statusCode),
    httpStatus: Number.isInteger(statusCode) ? statusCode : null,
    rpcStatus,
    reason,
    requestIdSha256: requestIdHash(headers),
  };
}

function request(url, options, body, {stage, validateOnly}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      const chunks = [];
      var byteLength = 0;
      var responseTooLarge = false;
      res.on('data', (chunk) => {
        byteLength += chunk.length;
        if (byteLength <= MAX_RESPONSE_BYTES) {
          chunks.push(chunk);
        } else {
          responseTooLarge = true;
        }
      });
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let parsed = {};
        let malformedResponse = false;
        if (!responseTooLarge) {
          try {
            parsed = text.length ? JSON.parse(text) : {};
          } catch (_) {
            malformedResponse = true;
          }
        }
        const diagnostic = providerDiagnostic({
          stage,
          statusCode: res.statusCode,
          headers: res.headers,
          body: parsed,
          validateOnly,
          malformedResponse,
          responseTooLarge,
        });
        if (!diagnostic.ok) {
          reject(new ProviderHttpFailure(diagnostic));
          return;
        }
        resolve({body: parsed, diagnostic});
      });
    });
    req.on('error', () => reject(new ProviderHttpFailure(providerDiagnostic({
      stage,
      validateOnly,
      networkError: true,
    }))));
    req.write(body);
    req.end();
  });
}

function postForm(url, fields, {validateOnly = false} = {}) {
  const body = new URLSearchParams(fields).toString();
  return request(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'content-length': Buffer.byteLength(body),
    },
  }, body, {stage: 'oauth', validateOnly});
}

function postJson(url, bearerToken, payload, {validateOnly = false} = {}) {
  const body = JSON.stringify(payload);
  return request(url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${bearerToken}`,
      'content-type': 'application/json; charset=utf-8',
      'content-length': Buffer.byteLength(body),
    },
  }, body, {stage: 'fcm', validateOnly});
}

function signJwt(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = {alg: 'RS256', typ: 'JWT'};
  const claims = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign(serviceAccount.private_key);
  return `${unsigned}.${base64url(signature)}`;
}

function buildData({probeId, kind, suppliedData}) {
  if (suppliedData) {
    const expectedType = kind === 'reaction'
      ? 'message_reaction'
      : kind === 'chat'
        ? 'new_message'
        : 'group_message';
    if (suppliedData.type !== expectedType) usage();
    if (Object.values(suppliedData).some((value) =>
      value === null || !['string', 'number', 'boolean'].includes(typeof value)
    )) usage();
    return Object.fromEntries(
      Object.entries(suppliedData).map(([key, value]) => [key, String(value)]),
    );
  }
  if (kind === 'reaction' || kind === 'announcement') usage();
  const now = Date.now().toString();
  if (kind === 'chat') {
    return {
      type: 'new_message',
      sender_id: `apns-provider-probe-peer-${probeId}`,
      message_id: `apns-provider-probe-message-${now}`,
      probe_id: probeId,
      title: 'Mknoon APNs Probe',
      body: `Provider push ${probeId}`,
    };
  }
  return {
    type: 'group_message',
    groupId: `apns-provider-probe-group-${probeId}`,
    message_id: `apns-provider-probe-message-${now}`,
    probe_id: probeId,
    title: 'Mknoon APNs Probe',
    body: `Provider group push ${probeId}`,
  };
}

function validatePrivateTransportContract(privateRequest, kind) {
  if (!privateRequest) return;
  const contract = privateRequest.transportContract;
  if (!contract || typeof contract !== 'object' || Array.isArray(contract)) usage();
  if (typeof contract.caseId !== 'string' || !contract.caseId.trim()) usage();
  if (!['display', 'suppress'].includes(contract.expectedOutcome)) usage();
  if (kind !== 'group' && kind !== 'announcement') return;

  const data = privateRequest.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) usage();
  if (Object.prototype.hasOwnProperty.call(data, 'sender_id')) usage();
  const hasTransport = Object.prototype.hasOwnProperty.call(
    data,
    'sender_transport_peer_id',
  );
  const transport = data.sender_transport_peer_id;
  if (contract.expectedOutcome === 'display') {
    if (!hasTransport || typeof transport !== 'string' || !transport.trim()) usage();
    return;
  }

  const reason = contract.rejectionReason;
  if (![
    'missing_transport',
    'unknown_transport',
    'non_admin_announcement',
  ].includes(reason)) usage();
  if (reason === 'missing_transport' && hasTransport) usage();
  if (reason !== 'missing_transport' &&
      (!hasTransport || typeof transport !== 'string' || !transport.trim())) usage();
  if (reason === 'non_admin_announcement' && kind !== 'announcement') usage();
}

function buildMessage({token, probeId, mode, kind, suppliedData}) {
  const data = buildData({probeId, kind, suppliedData});
  const visible = mode === 'visible';
  const aps = visible
    ? {
        alert: {
          title: 'Mknoon APNs Probe',
          body: `Provider ${kind} push ${probeId}`,
        },
        sound: 'default',
        'content-available': 1,
        'mutable-content': 1,
        'thread-id': kind === 'group' ? data.groupId : data.sender_id,
      }
    : {
        'content-available': 1,
      };

  return {
    token,
    data,
    ...(visible
      ? {
          notification: {
            title: 'Mknoon APNs Probe',
            body: `Provider ${kind} push ${probeId}`,
          },
        }
      : {}),
    apns: {
      headers: {
        'apns-push-type': visible ? 'alert' : 'background',
        'apns-priority': visible ? '10' : '5',
      },
      payload: {aps},
    },
    android: {
      priority: 'high',
    },
  };
}

function validateServiceAccountMode(serviceAccountPath, {validateOnly = false} = {}) {
  const mode = fs.statSync(serviceAccountPath).mode & 0o777;
  if (mode !== 0o600) {
    throw new ProviderPhaseFailure(
      'request_prepare',
      providerDiagnostic({stage: 'request_prepare', validateOnly}),
    );
  }
}

async function main() {
  const requestFile = arg('request-file');
  const privateRequest = requestFile
    ? JSON.parse(fs.readFileSync(requestFile, 'utf8'))
    : null;
  const token = arg('token', privateRequest && privateRequest.token);
  if (typeof token !== 'string' || !token.trim()) usage();
  const serviceAccountPath =
    arg('service-account', process.env.FIREBASE_SERVICE_ACCOUNT) || usage();
  const mode = arg('mode', 'visible');
  const kind = arg('kind', 'group');
  const probeId = arg('probe-id', new Date().toISOString().replace(/[^0-9TZ]/g, ''));
  const validateOnly = process.argv.includes('--validate-only');
  if (!['visible', 'data-only'].includes(mode)) usage();
  if (!['group', 'chat', 'reaction', 'announcement'].includes(kind)) usage();
  if (privateRequest && mode !== 'data-only') usage();
  if ((kind === 'reaction' || kind === 'announcement') && mode !== 'data-only') usage();
  validatePrivateTransportContract(privateRequest, kind);
  validateServiceAccountMode(serviceAccountPath, {validateOnly});

  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  const project = arg('project', serviceAccount.project_id);
  if (!project) usage();

  let oauth;
  try {
    const jwt = signJwt(serviceAccount);
    oauth = await postForm('https://oauth2.googleapis.com/token', {
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }, {validateOnly});
    if (!oauth.body || typeof oauth.body.access_token !== 'string' ||
        !oauth.body.access_token.trim()) {
      throw new ProviderPhaseFailure('oauth', providerDiagnostic({
        stage: 'oauth',
        statusCode: oauth.diagnostic.httpStatus,
        validateOnly,
        malformedResponse: true,
      }));
    }
  } catch (error) {
    if (error instanceof ProviderPhaseFailure) throw error;
    throw new ProviderPhaseFailure(
      'oauth',
      error instanceof ProviderHttpFailure
        ? error.diagnostic
        : providerDiagnostic({stage: 'oauth', validateOnly}),
    );
  }

  const message = buildMessage({
    token,
    probeId,
    mode,
    kind,
    suppliedData: privateRequest && privateRequest.data,
  });
  let result;
  try {
    result = await postJson(
      `https://fcm.googleapis.com/v1/projects/${project}/messages:send`,
      oauth.body.access_token,
      {message, validate_only: validateOnly},
      {validateOnly},
    );
    if (!result.body || typeof result.body.name !== 'string' ||
        !result.body.name.trim()) {
      throw new ProviderPhaseFailure('fcm', providerDiagnostic({
        stage: 'fcm',
        statusCode: result.diagnostic.httpStatus,
        validateOnly,
        malformedResponse: true,
      }));
    }
  } catch (error) {
    if (error instanceof ProviderPhaseFailure) throw error;
    throw new ProviderPhaseFailure(
      'fcm',
      error instanceof ProviderHttpFailure
        ? error.diagnostic
        : providerDiagnostic({stage: 'fcm', validateOnly}),
    );
  }

  console.log(JSON.stringify(result.diagnostic));
}

function safeFailureDiagnostic(error, {validateOnly = false} = {}) {
  const phase = error instanceof ProviderPhaseFailure
    ? error.phase
    : 'request_prepare';
  const diagnostic = error instanceof ProviderPhaseFailure && error.diagnostic
    ? error.diagnostic
    : providerDiagnostic({stage: phase, validateOnly});
  return {phase, diagnostic: {...diagnostic, ok: false}};
}

async function runCli() {
  try {
    await main();
  } catch (error) {
    const failure = safeFailureDiagnostic(error, {
      validateOnly: process.argv.includes('--validate-only'),
    });
    console.error(JSON.stringify(failure.diagnostic));
    process.exitCode = failure.phase === 'oauth'
      ? EXIT_OAUTH
      : failure.phase === 'fcm'
        ? EXIT_PROVIDER_SEND
        : EXIT_REQUEST_PREPARE;
  }
}

if (require.main === module) {
  runCli();
}

module.exports = {
  RESULT_SCHEMA,
  RPC_STATUS_ALLOWLIST,
  PROVIDER_REASON_ALLOWLIST,
  ProviderPhaseFailure,
  ProviderHttpFailure,
  providerDiagnostic,
  safeFailureDiagnostic,
};
