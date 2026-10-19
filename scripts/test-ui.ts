import { createTestRoot } from '@gpuix/react/testing';
import { connectTest } from '@gpuix/react/automation';
import { createElement } from 'react';
import { App, type Services } from '../src/App';
import { strict as assert } from 'node:assert';
let consumed = '';
let copied = '';
const services: Services = {
  async inspect() { return { installed: false, connected: false, tailnet: '', ip: '', user: 'TEST\\user', sid: 'S-1-5-21-1-2-3-1001', sshReady: false }; },
  async onboard(_machine, key, _replace, event) { consumed = key; event({ stage: 'verify', message: '준비 완료', done: true, ok: true, report: '테스트 리포트' }); },
  async copyReport(value) { copied = value; },
};
const root = createTestRoot({ width: 1000, height: 720 });
const pump = setInterval(() => root.renderer.flush(), 16);
try {
  root.render(createElement(App, { services }));
  const app = await connectTest(root.renderer);
  await new Promise(r => setTimeout(r, 100));
  root.renderer.flush();
  await app.getByTestId('start').waitFor();
  await app.getByTestId('start').click();
  assert.equal(consumed, '', 'invalid input must not start privileged work');
  await app.getByTestId('auth-key').fill('tskey-auth-test-only-not-a-real-key');
  await app.getByTestId('start').click();
  await app.getByTestId('copy-report').waitFor();
  await app.getByTestId('copy-report').click();
  assert.equal(consumed, 'tskey-auth-test-only-not-a-real-key');
  assert.ok(copied.includes('테스트 리포트'));
  assert.ok(!copied.includes(consumed));
  // Capture only the non-secret completion screen, never the key entry.
  root.renderer.captureScreenshot('artifacts/ui-complete.png');
  console.log('GPUIX native input → progress → report: PASS');
} finally { clearInterval(pump); root.unmount(); }
