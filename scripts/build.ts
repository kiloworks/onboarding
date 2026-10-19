import { mkdir, copyFile } from 'node:fs/promises';
import { resolve } from 'node:path';
if (process.platform !== 'win32') throw new Error('Build on the matching Windows runner.');
await mkdir('dist', { recursive: true });
const native = process.arch === 'arm64'
  ? resolve('node_modules/@gpuix/native/gpuix-native.win32-arm64-msvc.node')
  : require.resolve('@gpuix/native-win32-x64-msvc/gpuix-native.win32-x64-msvc.node');
await copyFile(native, 'dist/gpuix-native.node');
const result = await Bun.build({
  entrypoints: ['./src/entry.ts'],
  compile: { outfile: 'dist/onboarding.exe', windows: { hideConsole: true, title: 'Kiloworks Onboarding', publisher: 'kiloworks', version: '0.1.0', description: 'Tailscale and SSH onboarding' } },
  minify: true,
});
if (!result.success) throw new Error(result.logs.map(String).join('\n'));
console.log(`Built native Windows ${process.arch} app with matching GPUIX renderer.`);
