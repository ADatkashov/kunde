import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { setDefaultResultOrder } from 'node:dns';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const poc = fileURLToPath(new URL('../poc/', import.meta.url));
const local = join(poc, '.local');
const origin = 'http://localhost:8180';
const realm = 'kunde-security-' + randomBytes(4).toString('hex');
const issuer = origin + '/realms/' + realm;
const consumerClient = 'kunde-consumer-poc';
const partnerClient = 'kunde-partner-drill';
const wrongAudienceClient = 'kunde-other-audience-drill';
const expiringClient = 'kunde-expiring-drill';
const apiPort = process.env.KUNDE_TEST_JAR ? 18086 : 18085;
const apiRoot = 'http://127.0.0.1:' + apiPort;
const api = apiRoot + '/api/v1/poc/whoami';
const password = randomBytes(24).toString('base64url') + '!aA2';
const consumer = 'synthetic-consumer';
const partner = 'synthetic-partner';
const accessSeconds = 30;
const sessionMaxSeconds = 80;
const state = new Map();
setDefaultResultOrder('ipv4first');

function report(check, facts) {
  console.log(JSON.stringify({ check, ...facts }));
}

function claim(token, part = 1) {
  return JSON.parse(Buffer.from(token.split('.')[part], 'base64url'));
}

async function waitFor(label, action, timeout = 30000) {
  const stop = Date.now() + timeout;
  do {
    const result = await action();
    if (result) return result;
    await delay(300);
  } while (Date.now() < stop);
  throw new Error(label + ' timed out');
}

async function request(url, options = {}) {
  try {
    return await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(35000), ...options });
  } catch (error) {
    throw new Error((options.method ?? 'GET') + ' ' + new URL(url).pathname + ': ' + (error.cause?.code ?? error.name));
  }
}

async function token(at, body) {
  const response = await request(at + '/protocol/openid-connect/token', {
    method: 'POST', body: new URLSearchParams(body),
  });
  const data = await response.json();
  return { status: response.status, data };
}

let adminToken;
let adminExpires = 0;
const adminEnv = Object.fromEntries(
  (await readFile(join(poc, 'keycloak/.env'), 'utf8')).split(/\r?\n/)
    .filter(line => /^KC_BOOTSTRAP_ADMIN_\w+=/.test(line))
    .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]),
);
async function admin(method, path = '', body, expected = 200) {
  if (Date.now() >= adminExpires) {
    const auth = await token(origin + '/realms/master', {
      grant_type: 'password', client_id: 'admin-cli',
      username: adminEnv.KC_BOOTSTRAP_ADMIN_USERNAME, password: adminEnv.KC_BOOTSTRAP_ADMIN_PASSWORD,
    });
    assert.equal(auth.status, 200, 'Local bootstrap admin sign-in');
    adminToken = auth.data.access_token;
    adminExpires = Date.now() + (auth.data.expires_in - 5) * 1000;
  }
  const response = await request(origin + '/admin/realms' + path, {
    method, headers: { Authorization: 'Bearer ' + adminToken, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body), signal: AbortSignal.timeout(method === 'POST' && !path ? 150000 : 35000),
  });
  assert.equal(response.status, expected, method + ' admin endpoint ' + path);
  if (expected === 200) return response.json();
}

async function openBrowser() {
  const profile = await mkdtemp(join(local, 'keycloak-edge-'));
  const edge = process.env.KUNDE_TEST_BROWSER
    ?? join(process.env['ProgramFiles(x86)'] ?? '', 'Microsoft/Edge/Application/msedge.exe');
  const browser = spawn(edge, [
    '--headless=new', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0',
    '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
    '--user-data-dir=' + profile, 'about:blank',
  ], { stdio: 'ignore', windowsHide: true });
  let socket;
  try {
    const port = await waitFor('Browser debug port', async () =>
      (await readFile(join(profile, 'DevToolsActivePort'), 'utf8').catch(() => '')).split(/\r?\n/)[0]);
    const targets = await (await request('http://127.0.0.1:' + port + '/json/list')).json();
    socket = new WebSocket(targets.find(target => target.type === 'page').webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', () => reject(new Error('Browser debug connection failed')), { once: true });
    });
    let sequence = 0;
    const pending = new Map();
    socket.addEventListener('message', ({ data }) => {
      const message = JSON.parse(data);
      const operation = pending.get(message.id);
      if (!operation) return;
      pending.delete(message.id);
      clearTimeout(operation.timeout);
      if (message.error) operation.reject(new Error('Browser debug command failed'));
      else operation.resolve(message.result);
    });
    const send = (method, params = {}) => new Promise((resolve, reject) => {
      const id = ++sequence;
      const timeout = setTimeout(() => {
        pending.delete(id);
        reject(new Error('Browser debug command timed out: ' + method));
      }, 60000);
      pending.set(id, { resolve, reject, timeout });
      socket.send(JSON.stringify({ id, method, params }));
    });
    await send('Page.enable');
    await send('Network.enable');
    return {
      navigate: url => send('Page.navigate', { url }),
      evaluate: async expression => (await send('Runtime.evaluate', { expression, returnByValue: true })).result?.value,
      clearCookies: () => send('Network.clearBrowserCookies'),
      close: () => { socket.close(); browser.kill(); },
    };
  } catch (error) {
    socket?.close();
    browser.kill();
    throw error;
  }
}

async function seedRealm(name, redirect) {
  const base = JSON.parse(await readFile(join(poc, 'keycloak/realm-kunde-dev.json'), 'utf8'));
  const primary = base.clients.find(client => client.clientId === consumerClient);
  const drillClient = (clientId, scopes, attributes = {}) => ({
    ...primary, clientId, name: clientId, redirectUris: [redirect],
    attributes: { ...primary.attributes, 'post.logout.redirect.uris': redirect, ...attributes },
    defaultClientScopes: scopes, optionalClientScopes: [],
  });
  const common = primary.defaultClientScopes.filter(scope => scope !== 'kunde.poc');
  const partnerScope = { name: 'kunde.partner.poc', protocol: 'openid-connect',
    attributes: { 'include.in.token.scope': 'true' } };
  await admin('POST', '', {
    ...base, realm: name, displayName: 'KUNDE synthetic security drill',
    accessTokenLifespan: accessSeconds, ssoSessionIdleTimeout: 60, ssoSessionMaxLifespan: sessionMaxSeconds,
    clientScopes: [...base.clientScopes, partnerScope],
    clients: [
      ...base.clients.filter(client => client !== primary),
      drillClient(consumerClient, primary.defaultClientScopes),
      drillClient(partnerClient, [...common, partnerScope.name]),
      drillClient(wrongAudienceClient, primary.defaultClientScopes.filter(scope => scope !== 'kunde-api-audience')),
      drillClient(expiringClient, primary.defaultClientScopes, {
        'client.session.idle.timeout': '18', 'client.session.max.lifespan': '24',
      }),
    ],
    users: [[consumer, 'consumer-poc'], [partner, 'operator-poc']].map(([username, role]) => ({
      username, enabled: true, email: username + '@example.test', emailVerified: true,
      firstName: 'Synthetic', lastName: 'Account', realmRoles: [role],
      credentials: [{ type: 'password', value: password, temporary: false }],
    })),
  }, 201);
  const prefix = '/' + name;
  const scopes = await admin('GET', prefix + '/client-scopes');
  const role = await admin('GET', prefix + '/roles/consumer-poc');
  const scope = scopes.find(item => item.name === 'kunde.poc');
  await admin('POST', prefix + '/client-scopes/' + scope.id + '/scope-mappings/realm', [role], 204);
}

async function authorize(browser, redirect, {
  client = consumerClient, user = consumer, at = issuer, silent = false, scope = 'openid',
} = {}) {
  if (!silent) await browser.clearCookies();
  const nonce = randomBytes(16).toString('hex');
  const verifier = randomBytes(48).toString('base64url');
  const params = new URLSearchParams({
    client_id: client, redirect_uri: redirect, response_type: 'code', scope, state: nonce,
    code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256',
  });
  if (silent) params.set('prompt', 'none');
  await browser.navigate(at + '/protocol/openid-connect/auth?' + params);
  if (!silent) {
    await waitFor('Interactive Keycloak form', () => browser.evaluate('!!document.querySelector("#kc-login")'));
    await browser.evaluate(`(() => {
      document.querySelector('#username').value = ${JSON.stringify(user)};
      document.querySelector('#password').value = ${JSON.stringify(password)};
      document.querySelector('#kc-login').click();
    })()`);
  }
  const callback = await waitFor('OIDC browser callback with matching state', () => state.get(nonce));
  state.delete(nonce);
  if (silent) return callback;
  assert.ok(callback.get('code'), 'Expected provider authorization code');
  const exchange = {
    grant_type: 'authorization_code', client_id: client, redirect_uri: redirect,
    code_verifier: verifier, code: callback.get('code'),
  };
  const issued = await token(at, exchange);
  assert.equal(issued.status, 200, 'PKCE code exchange');
  return { ...issued.data, exchange };
}

async function status(bearer) {
  return (await request(api, { headers: bearer ? { Authorization: 'Bearer ' + bearer } : {} })).status;
}
const refresh = (refreshToken, client = consumerClient) =>
  token(issuer, { grant_type: 'refresh_token', client_id: client, refresh_token: refreshToken });

async function expiryWindow(label, access, event) {
  const expires = claim(access).exp;
  let lastAccepted;
  for (let attempt = 0; attempt < 60; attempt++) {
    const response = await status(access);
    const now = Date.now();
    if (response === 401) {
      assert.ok(lastAccepted, label + ' should accept access JWT during residual window');
      report(label, {
        lastAcceptedAfterEventSeconds: Math.round((lastAccepted - event) / 1000),
        firstRejectedAfterEventSeconds: Math.round((now - event) / 1000),
        lastAcceptedRelativeToExpSeconds: Math.round(lastAccepted / 1000 - expires),
        firstRejectedRelativeToExpSeconds: Math.round(now / 1000 - expires), status: response,
      });
      return;
    }
    assert.equal(response, 200, label + ' unexpected API status');
    lastAccepted = now;
    await delay(2000);
  }
  throw new Error(label + ' failed to expire within the bounded observation window');
}

async function exercise(browser, redirect) {
  const issue = options => authorize(browser, redirect, options);
  const prefix = '/' + realm;
  const discovery = await (await request(issuer + '/.well-known/openid-configuration')).json();
  assert.equal(discovery.issuer, issuer);
  const keySet = async () => (await (await request(discovery.jwks_uri)).json()).keys;
  const missing = await status();
  assert.equal(missing, 401);

  const loggedOut = await issue();
  assert.equal(await status(loggedOut.access_token), 200);
  const logoutState = randomBytes(16).toString('hex');
  await browser.navigate(discovery.end_session_endpoint + '?' + new URLSearchParams({
    id_token_hint: loggedOut.id_token, post_logout_redirect_uri: redirect, state: logoutState,
  }));
  await waitFor('Browser logout callback', () => state.has(logoutState));
  state.delete(logoutState);
  const logoutTime = Date.now();
  const afterLogout = await status(loggedOut.access_token);
  const logoutRefresh = await refresh(loggedOut.refresh_token);
  const silent = await issue({ silent: true });
  assert.equal(afterLogout, 200);
  assert.equal(logoutRefresh.status, 400);
  assert.equal(silent.get('error'), 'login_required');
  report('browser-logout', { before: 200, after: afterLogout, refresh: logoutRefresh.status, promptNone: 'login_required' });

  const revoked = await issue();
  assert.equal(await status(revoked.access_token), 200);
  const sid = claim(revoked.access_token).sid;
  assert.ok(sid, 'Keycloak issued a session identifier');
  await admin('DELETE', prefix + '/sessions/' + encodeURIComponent(sid), undefined, 204);
  const revokeTime = Date.now();
  const afterRevoke = await status(revoked.access_token);
  const revokedRefresh = await refresh(revoked.refresh_token);
  assert.equal(afterRevoke, 200);
  assert.equal(revokedRefresh.status, 400);
  report('admin-session-revocation', { before: 200, after: afterRevoke, refresh: revokedRefresh.status });

  const expiryChecks = Promise.allSettled([
    expiryWindow('browser-logout-expiry-window', loggedOut.access_token, logoutTime),
    expiryWindow('admin-revocation-expiry-window', revoked.access_token, revokeTime),
  ]);
  const rotating = await issue();
  const next = await refresh(rotating.refresh_token);
  assert.equal(next.status, 200);
  assert.ok(next.data.refresh_token !== rotating.refresh_token, 'Expected a rotated token');
  const replay = await refresh(rotating.refresh_token);
  assert.equal(replay.status, 400);
  const successor = await refresh(next.data.refresh_token);
  const invalid = await refresh('invalid-synthetic-refresh');
  assert.equal(invalid.status, 400);
  report('refresh-rotation', { first: next.status, rotated: true, oldReplay: replay.status,
    successorAfterReplay: successor.status, invalid: invalid.status });

  const racing = await issue();
  const concurrent = await Promise.all([refresh(racing.refresh_token), refresh(racing.refresh_token)]);
  assert.ok(concurrent.some(result => result.status === 200), 'At least one concurrent refresh should succeed');
  const afterRace = await refresh(racing.refresh_token);
  assert.equal(afterRace.status, 400);
  report('concurrent-refresh', { simultaneous: concurrent.map(result => result.status).sort(), originalReplay: afterRace.status });

  const disposable = await issue();
  const revokeResponse = await request(discovery.revocation_endpoint, {
    method: 'POST', body: new URLSearchParams({ client_id: consumerClient, token_type_hint: 'refresh_token',
      token: disposable.refresh_token }),
  });
  const afterTokenRevoke = await refresh(disposable.refresh_token);
  assert.equal(revokeResponse.status, 200);
  assert.equal(afterTokenRevoke.status, 400);
  report('refresh-endpoint-revocation', {
    revoke: revokeResponse.status, refresh: afterTokenRevoke.status, issuedAccess: await status(disposable.access_token),
  });

  const expiring = await issue({ client: expiringClient });
  const refreshExp = claim(expiring.refresh_token).exp;
  assert.ok(refreshExp * 1000 - Date.now() < 30000, 'Short client refresh expiry must be active');
  const refreshExpiry = delay(Math.max(0, refreshExp * 1000 - Date.now()) + 2000).then(async () => {
    const result = await refresh(expiring.refresh_token, expiringClient);
    assert.equal(result.status, 400);
    report('refresh-expiry', { advertisedSeconds: expiring.refresh_expires_in, status: result.status });
  });
  const refreshExpiryResult = Promise.allSettled([refreshExpiry]);

  const codeReplay = await issue();
  const repeated = await token(issuer, codeReplay.exchange);
  assert.equal(repeated.status, 400);
  report('authorization-code-replay', { first: 200, repeated: repeated.status });

  const noRole = await issue({ user: partner });
  const otherApp = await issue({ client: partnerClient, user: partner });
  const otherAudience = await issue({ client: wrongAudienceClient });
  const authorization = {
    consumer: await status((await issue()).access_token), missingBearer: missing,
    missingConsumerRole: await status(noRole.access_token), otherAppScope: await status(otherApp.access_token),
    wrongAudience: await status(otherAudience.access_token),
  };
  assert.deepEqual(authorization, {
    consumer: 200, missingBearer: 401, missingConsumerRole: 403, otherAppScope: 403, wrongAudience: 401,
  });
  report('live-authorization', authorization);

  const before = await issue();
  const old = claim(before.access_token, 0).kid;
  const original = (await keySet()).map(key => key.kid);
  assert.ok(original.includes(old));
  assert.equal(await status(before.access_token), 200);
  const metadata = await admin('GET', prefix + '/keys');
  const oldProviderId = metadata.keys.find(key => key.kid === old).providerId;
  const realmId = (await admin('GET', prefix)).id;
  const newName = 'readiness-rs256-rotation';
  await admin('POST', prefix + '/components', {
    name: newName, parentId: realmId, providerId: 'rsa-generated', providerType: 'org.keycloak.keys.KeyProvider',
    config: { priority: ['200'], enabled: ['true'], active: ['true'], algorithm: ['RS256'], keySize: ['2048'] },
  }, 201);
  const oldPath = prefix + '/components/' + oldProviderId;
  const oldComponent = await admin('GET', oldPath);
  await admin('PUT', oldPath, { ...oldComponent, config: { ...oldComponent.config, active: ['false'] } }, 204);
  const cutover = Date.now();
  const after = await issue();
  const replacement = claim(after.access_token, 0).kid;
  const overlap = (await keySet()).map(key => key.kid);
  assert.notEqual(replacement, old);
  assert.ok(overlap.includes(old) && overlap.includes(replacement));
  const newStatus = await status(after.access_token);
  const overlapStatus = await status(before.access_token);
  assert.equal(newStatus, 200);
  assert.equal(overlapStatus, 200);
  report('key-overlap', { old, replacement, original, overlap, newStatus, overlapStatus });

  const expiries = await expiryChecks;
  for (const result of expiries) if (result.status === 'rejected') throw result.reason;
  for (const result of await refreshExpiryResult) if (result.status === 'rejected') throw result.reason;
  // Keep the passive key through the longest online token/session and the observed Spring skew.
  const retireAt = cutover + (Math.max(sessionMaxSeconds, accessSeconds) + 65) * 1000;
  await delay(Math.max(0, retireAt - Date.now()));
  assert.equal(await status(before.access_token), 401, 'Wait until old access JWT is rejected before removal');
  await admin('DELETE', oldPath, undefined, 204);
  const retained = (await keySet()).map(key => key.kid);
  assert.ok(!retained.includes(old) && retained.includes(replacement));
  assert.equal(await status((await issue()).access_token), 200);
  report('key-retirement', { retained, oldRemoved: true, expiredOld: 401, fresh: 200 });
}

await mkdir(local, { recursive: true });
const callbackServer = createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (url.pathname === '/callback' && url.searchParams.has('state')) state.set(url.searchParams.get('state'), url.searchParams);
  res.writeHead(200, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
  res.end('KUNDE synthetic callback received');
});
await new Promise((resolve, reject) => {
  callbackServer.once('error', reject);
  callbackServer.listen(0, '127.0.0.1', resolve);
});
const redirect = 'http://127.0.0.1:' + callbackServer.address().port + '/callback';
let browser;
let spring;
try {
  report('starting-realm', { realm });
  await seedRealm(realm, redirect);
  await writeFile(join(local, 'keycloak-readiness-runtime.json'), JSON.stringify({ issuer }));
  report('realm-created', { realm, issuer, rotation: true, maxReuse: 0, accessSeconds, sessionMaxSeconds });
  if (process.env.KUNDE_TEST_JAR) {
    const db = await readFile(join(poc, 'backend-db/.env'), 'utf8');
    const dbPassword = /^POC_DB_PASSWORD=(.+)$/m.exec(db)?.[1].trim();
    assert.ok(dbPassword, 'Local POC database password is required');
    spring = spawn('java', ['-jar', process.env.KUNDE_TEST_JAR], {
      windowsHide: true, stdio: 'ignore', env: { ...process.env,
        DB_URL: 'jdbc:postgresql://127.0.0.1:5544/kunde_identity_poc', DB_USERNAME: 'kunde_poc', DB_PASSWORD: dbPassword,
        SPRING_PROFILES_ACTIVE: 'identity-poc', POC_ALLOW_HTTP_ISSUER: 'true', OIDC_ISSUER_URI: issuer,
        OIDC_AUDIENCE: 'kunde-api', POC_ZITADEL_ORGANIZATION_ID: '', SERVER_ADDRESS: '127.0.0.1',
        SERVER_PORT: String(apiPort),
      },
    });
  }
  browser = await openBrowser();
  report('browser-ready', {});
  await waitFor('Spring executable JAR readiness', async () =>
    (await request(apiRoot + '/actuator/health').catch(() => null))?.status === 200, 360000);
  report('spring-ready', { port: apiPort });
  await exercise(browser, redirect);
} catch (error) {
  console.error('Drill stopped: ' + (error instanceof Error ? error.message : 'unknown error'));
  process.exitCode = 1;
} finally {
  browser?.close();
  spring?.kill();
  callbackServer.close();
}
