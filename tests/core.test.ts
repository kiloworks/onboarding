import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { needsKey, redact, report, validateKey, type Machine } from '../src/core';
const key = 'tskey-auth-test-only-not-a-real-key';
const machine: Machine = { installed: true, connected: true, tailnet: 'test', ip: '100.64.0.1', user: 'PC\\user', sid: 'S-1-5-21-1-2-3-1001', sshReady: false };
describe('registration boundary', () => {
  test('trims keys and rejects command injection and OAuth/API credentials', () => {
    expect(validateKey(`  ${key}\n`)).toBe(key);
    for (const input of ['', 'tskey-client-secret', 'tskey-api-secret', `${key}; whoami`, `${key}\n${key}`, key + ' '.repeat(600) + '!'])
      expect(() => validateKey(input)).toThrow();
  });
  test('a connected machine repairs without reusing a consumed key', () => {
    expect(needsKey(machine, false)).toBe(false);
    expect(needsKey(machine, true)).toBe(true);
    expect(needsKey({ ...machine, connected: false }, false)).toBe(true);
  });
  test('support reports redact credentials and tokens', () => {
    const jwt = 'eyJhbGciOi.testpayload.testsignature';
    expect(redact(`${key} tskey-api-secret ${jwt}`)).not.toContain('tskey-');
    const text = report([{ stage: 'connect', message: key, report: jwt }], machine.user);
    expect(text).not.toContain(key); expect(text).not.toContain(jwt);
  });
  test('public defaults contain exactly the approved public keys', () => {
    const keys = readFileSync(new URL('../config/administrators_authorized_keys', import.meta.url), 'utf8').trim().split('\n');
    expect(keys).toHaveLength(2);
    expect(new Set(keys).size).toBe(2);
    expect(keys.every(k => k.startsWith('sk-ecdsa-sha2-nistp256@openssh.com '))).toBe(true);
  });
});
