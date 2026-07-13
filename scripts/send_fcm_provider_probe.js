#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const https = require('https');

function usage() {
  console.error(`Usage:
  FIREBASE_SERVICE_ACCOUNT=/path/service-account.json \\
    node scripts/send_fcm_provider_probe.js --token <fcm-token> [--project <project-id>] [--probe-id <id>] [--mode visible|data-only] [--kind group|chat]

Sends one Firebase Cloud Messaging v1 APNs provider probe to a single token.
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

function postForm(url, fields) {
  const body = new URLSearchParams(fields).toString();
  return request(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      'content-length': Buffer.byteLength(body),
    },
  }, body);
}

function postJson(url, bearerToken, payload) {
  const body = JSON.stringify(payload);
  return request(url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${bearerToken}`,
      'content-type': 'application/json; charset=utf-8',
      'content-length': Buffer.byteLength(body),
    },
  }, body);
}

function request(url, options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let parsed = null;
        try {
          parsed = text.length ? JSON.parse(text) : {};
        } catch (_) {
          parsed = {raw: text};
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`HTTP ${res.statusCode}: ${text}`));
          return;
        }
        resolve(parsed);
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
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
  if (!['visible', 'data-only'].includes(mode)) usage();
  if (!['group', 'chat', 'reaction', 'announcement'].includes(kind)) usage();
  if (privateRequest && mode !== 'data-only') usage();
  if ((kind === 'reaction' || kind === 'announcement') && mode !== 'data-only') usage();
  validatePrivateTransportContract(privateRequest, kind);
  validateServiceAccountMode(serviceAccountPath, {validateOnly});

  const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  const project = arg('project', serviceAccount.project_id);
  if (!project) usage();

  const jwt = signJwt(serviceAccount);
  const oauth = await postForm('https://oauth2.googleapis.com/token', {
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: jwt,
  });

  const message = buildMessage({token, probeId, mode, kind});
  const result = await postJson(
    `https://fcm.googleapis.com/v1/projects/${project}/messages:send`,
    oauth.access_token,
    {message},
  );

  console.log(JSON.stringify({
    ok: true,
    project,
    mode,
    kind,
    probeId,
    name: result.name,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
