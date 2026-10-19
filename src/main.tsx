import { render } from '@gpuix/react';
import { App } from './App';
import * as windows from './windows';
import { redact } from './core';

// No credentials in startup diagnostics, including renderer error output.
process.on('uncaughtException', e => console.error(redact(e.message)));
render(<App services={windows} />, {
  title: 'Kiloworks Onboarding', width: 1000, height: 720,
  focus: process.env.GPUIX_BACKGROUND !== '1',
});
if (process.argv.includes('--smoke-gui')) setTimeout(() => process.exit(0), 5000);
