import { createHash } from 'node:crypto';
import { readFile, readdir, unlink, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

export async function dedupeLicenses(root: string) {
  root = resolve(root);
  const index = join(root, 'LICENSE-INDEX.json');
  const aliases: Record<string, string> = JSON.parse(await readFile(index, 'utf8').catch(error => {
    if (error.code === 'ENOENT') return '{}';
    throw error;
  }));
  const unique = new Map<string, string>();
  const entries = await readdir(root, { recursive: true, withFileTypes: true });
  for (const entry of entries.filter(entry => entry.isFile()).sort((a, b) => join(a.parentPath, a.name).localeCompare(join(b.parentPath, b.name)))) {
    const path = join(entry.parentPath, entry.name);
    if (path === index) continue;
    const name = path.slice(root.length + 1).replaceAll('\\', '/');
    const hash = createHash('sha256').update(await readFile(path)).digest('hex');
    const original = unique.get(hash);
    if (original) {
      aliases[name] = original;
      await unlink(path);
    } else { unique.set(hash, name); delete aliases[name]; }
  }
  for (const name of Object.keys(aliases)) {
    let target = aliases[name];
    const seen = new Set([name]);
    while (aliases[target]) {
      if (seen.has(target)) throw new Error('Cyclic license index');
      seen.add(target); target = aliases[target];
    }
    if (![...unique.values()].includes(target)) throw new Error(`Missing license notice: ${target}`);
    aliases[name] = target;
  }
  await writeFile(index, JSON.stringify(aliases, null, 2) + '\n');
}

if (import.meta.main) await dedupeLicenses('dist/licenses');
