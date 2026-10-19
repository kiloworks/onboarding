import { readdir, mkdir, copyFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
await mkdir('dist/licenses', { recursive: true });
const bun = spawnSync(process.execPath, ['--print-license'], { encoding: 'utf8' });
if (bun.status !== 0) throw new Error('Cannot collect Bun third-party licenses');
await writeFile('dist/licenses/Bun.txt', bun.stdout);
for (const name of ['react', 'react-reconciler', '@gpuix/react', '@gpuix/native', 'zod', 'eventsource-parser']) {
  const path = join('node_modules', name);
  for (const file of await readdir(path)) {
    if (/^(license|notice|copying)/i.test(file)) await copyFile(join(path, file), join('dist/licenses', name.replaceAll('/', '-') + '-' + file));
  }
}
