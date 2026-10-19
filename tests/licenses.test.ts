import { test, expect } from 'bun:test';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { dedupeLicenses } from '../scripts/dedupe-licenses';

test('identical license notices share exact bytes while component attribution survives repeated runs', async () => {
  const root = await mkdtemp(join(tmpdir(), 'onboarding-licenses-'));
  try {
    await mkdir(join(root, 'native'));
    await writeFile(join(root, 'A-LICENSE'), 'Original license and copyright\n');
    await writeFile(join(root, 'native/B-LICENSE'), 'Original license and copyright\n');
    await writeFile(join(root, 'C-LICENSE'), 'Different copyright\n');
    await dedupeLicenses(root);
    await writeFile(join(root, '0-LICENSE'), 'Original license and copyright\n');
    await dedupeLicenses(root);
    const index = JSON.parse(await readFile(join(root, 'LICENSE-INDEX.json'), 'utf8'));
    expect(await readFile(join(root, index['native/B-LICENSE']), 'utf8')).toBe('Original license and copyright\n');
    expect(await readFile(join(root, 'C-LICENSE'), 'utf8')).toBe('Different copyright\n');
  } finally { await rm(root, { recursive: true, force: true }); }
});
