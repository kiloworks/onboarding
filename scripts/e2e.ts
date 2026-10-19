import { launch } from '@gpuix/react/automation';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { strict as assert } from 'node:assert';
import { redact } from '../src/core';
const mask = (value: string) => console.log(`::add-mask::${value.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A')}`);
async function json(url: string, init: RequestInit) {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error(`Request failed: ${new URL(url).pathname} HTTP ${response.status}`);
  return response.json() as Promise<Record<string, any>>;
}
const ts = join(process.env.ProgramFiles || 'C:\\Program Files', 'Tailscale', 'tailscale.exe');
let app: Awaited<ReturnType<typeof launch>> | undefined;
let access = '', keyId = '';
try {
  const clientId = process.env.TS_WIF_CLIENT_ID, audience = process.env.TS_WIF_AUDIENCE;
  if (!clientId || !audience) throw new Error('Configure TS_WIF_CLIENT_ID and TS_WIF_AUDIENCE repository variables first.');
  const endpoint = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  const requestToken = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
  if (!endpoint || !requestToken) throw new Error('GitHub id-token: write permission is required.');
  const identity = await json(endpoint + '&audience=' + encodeURIComponent(audience), { headers: { Authorization: `Bearer ${requestToken}` } });
  mask(identity.value);
  const token = await json('https://api.tailscale.com/api/v2/oauth/token-exchange', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: clientId, jwt: identity.value }),
  });
  access = token.access_token;
  if (!access) throw new Error('Tailscale token exchange returned no token.');
  mask(access);
  const auth = await json('https://api.tailscale.com/api/v2/tailnet/-/keys', {
    method: 'POST', headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ capabilities: { devices: { create: { reusable: false, ephemeral: true, preauthorized: true, tags: ['tag:gha'] } } }, expirySeconds: 86400, description: `onboarding-${process.env.GITHUB_RUN_ID}-${process.env.RUNNER_NAME}` }),
  });
  if (!auth.key) throw new Error('Tailscale returned no auth key.');
  mask(auth.key); keyId = auth.id;
  const executable = process.env.ONBOARDING_EXE;
  if (!executable) throw new Error('ONBOARDING_EXE is required.');
  app = await launch({ command: executable, args: [], env: { ...process.env, GPUIX_BACKGROUND: '1' } });
  await app.getByTestId('start').waitFor({ timeoutMs: 60_000 });
  await app.getByTestId('auth-key').fill(auth.key);
  auth.key = '';
  await app.getByTestId('start').click();
  await app.getByTestId('copy-report').waitFor({ timeoutMs: 30 * 60_000 });
  const heading = await app.getByTestId('heading').textContent();
  const detail = await app.getByTestId('status').textContent();
  assert.ok(heading.includes('준비가 됐어요'), `Onboarding did not complete: ${redact(detail)}`);
  const status = spawnSync(ts, ['status', '--json'], { encoding: 'utf8', windowsHide: true });
  assert.equal(status.status, 0);
  const state = JSON.parse(status.stdout);
  assert.equal(state.BackendState, 'Running');
  assert.ok(state.Self.Tags.includes('tag:gha'));
  const ssh = spawnSync('pwsh', ['-NoProfile', '-File', 'scripts/check-ssh.ps1'], { encoding: 'utf8', windowsHide: true, timeout: 120_000 });
  if (ssh.status !== 0) throw new Error(redact(ssh.stderr || 'SSH authentication check failed'));
  console.log(redact(ssh.stdout));
  console.log('Real packaged GUI → OIDC-minted one-off key → Tailscale + SSH setup: PASS');
} catch (e) {
  // Do not let automation diagnostics print the filled key or the native tree.
  console.error(redact(e instanceof Error ? e.message : 'E2E failed'));
  process.exitCode = 1;
} finally {
  if (app) await app.close().catch(() => {});
  const logout = spawnSync(ts, ['logout'], { encoding: 'utf8', windowsHide: true, timeout: 30_000 });
  if (logout.status !== 0 && !logout.error?.message.includes('ENOENT')) {
    console.error('Tailscale logout failed; verify ephemeral node cleanup in the console.'); process.exitCode = 1;
  }
  if (access && keyId) {
    const revoke = await fetch(`https://api.tailscale.com/api/v2/tailnet/-/keys/${encodeURIComponent(keyId)}`, {
      method: 'DELETE', headers: { Authorization: `Bearer ${access}` }, signal: AbortSignal.timeout(30_000),
    }).catch(() => null);
    if (revoke && ![200, 204, 404].includes(revoke.status)) { console.error('Unused auth key cleanup failed.'); process.exitCode = 1; }
  }
  access = '';
}
