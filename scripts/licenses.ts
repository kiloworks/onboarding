import { readdir, mkdir, copyFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
await mkdir('dist/licenses', { recursive: true });
for (const file of await readdir('config/licenses')) {
  await copyFile(join('config/licenses', file), join('dist/licenses', file));
}
await copyFile('docs/runtime-rebuild.md', 'dist/licenses/REBUILDING.md');
for (const name of ['react', 'react-reconciler', '@gpuix/react', '@gpuix/native', 'zod', 'eventsource-parser']) {
  const path = join('node_modules', name);
  for (const file of await readdir(path)) {
    if (/^(license|notice|copying)/i.test(file)) await copyFile(join(path, file), join('dist/licenses', name.replaceAll('/', '-') + '-' + file));
  }
}
