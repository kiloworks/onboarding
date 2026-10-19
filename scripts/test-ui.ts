import { createTestRoot } from '@gpuix/react/testing';
import { connectTest } from '@gpuix/react/automation';
import { createElement } from 'react';
import { App, type Services } from '../src/App';
import { AppFonts } from '../src/fonts';
import { strict as assert } from 'node:assert';
let consumed = '';
let copied = '';
let connected = false;
let calls = 0;
let replaced = false;
let complete!: () => void;
const services: Services = {
  async inspect() { return { installed: connected, connected, tailnet: 'test-network', ip: '100.64.0.1', user: 'TEST\\user', sid: 'S-1-5-21-1-2-3-1001', sshReady: false }; },
  async onboard(_machine, key, _replace, event) {
    consumed = key;
    calls++; replaced = _replace;
    event({ stage: 'connect', message: '네트워크에 연결하고 있어요.' });
    await new Promise<void>(resolve => { complete = resolve; });
    event({ stage: 'verify', message: '준비 완료', done: true, ok: true, report: '테스트 리포트\nSSH 계정: TEST\\user\nTailscale IP: 100.64.0.1\n공개키 파일: C:\\ProgramData\\ssh\\administrators_authorized_keys\n방화벽: 모든 네트워크 TCP 22\n관리자 측 원격 접속: 미검증' });
  },
  async copyReport(value) { copied = value; },
};
const root = createTestRoot({ width: 1000, height: 720 });
if (process.platform === 'win32') {
  // The 0.10.0 test wrapper predates the font API in our source-built renderer.
  const native = (root.renderer as unknown as { native: { registerFont(data: Buffer): void } }).native;
  Object.assign(root.renderer, { registerFont: native.registerFont.bind(native) });
}
const pump = setInterval(() => root.renderer.flush(), 16);
try {
  root.render(createElement(AppFonts, { children: createElement(App, { services }) }));
  const app = await connectTest(root.renderer);
  await new Promise(r => setTimeout(r, 100));
  root.renderer.flush();
  await app.getByTestId('begin').waitFor();
  await new Promise(r => setTimeout(r, 250));
  root.renderer.captureScreenshot('artifacts/ui-welcome.png');
  await app.getByTestId('begin').click();
  await app.getByTestId('next').click();
  assert.ok((await app.getByTestId('status').textContent()).includes('키'));
  assert.equal(consumed, '', 'invalid input must not start privileged work');
  await app.getByTestId('auth-key').fill('tskey-auth-test-only-not-a-real-key');
  await app.getByTestId('next').click();
  await app.getByTestId('start').waitFor();
  assert.equal(consumed, '', 'valid input must still wait for explicit confirmation');
  await new Promise(r => setTimeout(r, 250));
  root.renderer.captureScreenshot('artifacts/ui-review.png');
  await app.getByTestId('start').click();
  await app.getByTestId('motion').waitFor();
  await app.getByTestId('motion').click();
  assert.equal(await app.getByTestId('motion').textContent(), '모션 켜기');
  await new Promise(r => setTimeout(r, 250));
  root.renderer.captureScreenshot('artifacts/ui-working.png');
  complete();
  await app.getByTestId('copy-report').waitFor();
  await app.getByTestId('copy-report').click();
  assert.equal(consumed, 'tskey-auth-test-only-not-a-real-key');
  assert.ok(copied.includes('테스트 리포트'));
  assert.ok(!copied.includes(consumed));
  // Capture only the non-secret completion screen, never the key entry.
  await new Promise(r => setTimeout(r, 250));
  root.renderer.captureScreenshot('artifacts/ui-complete.png');
  const button = root.renderer.findByTestId('copy-report')!;
  const bounds = root.renderer.getElementBounds(button.id)!;
  assert.ok(bounds.y + bounds.height <= 680, 'completion actions must remain inside the wizard');
  connected = true;
  await app.getByTestId('refresh').click();
  await app.getByTestId('begin').waitFor();
  await app.getByTestId('begin').click();
  assert.equal(root.renderer.findByTestId('auth-key'), undefined, 'keeping the current connection needs no new key');
  await app.getByTestId('next').click();
  await app.getByTestId('back').click();
  await app.getByTestId('replace').click();
  await app.getByTestId('auth-key').waitFor();
  await app.getByTestId('next').click();
  assert.equal(calls, 1, 'switching accounts must require a fresh key and final confirmation');
  await app.getByTestId('auth-key').fill('tskey-auth-second-test-only-key');
  await app.getByTestId('next').click();
  await app.getByTestId('start').click();
  await app.getByTestId('motion').waitFor();
  assert.equal(replaced, true);
  complete();
  await app.getByTestId('copy-report').waitFor();
  console.log('GPUIX native wizard, confirmation, reduced motion and redacted report: PASS');
} finally { clearInterval(pump); root.unmount(); }
