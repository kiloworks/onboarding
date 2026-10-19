import { join, dirname } from 'node:path';
// The matching renderer ships beside the app, with no system Node/Bun dependency.
process.env.NAPI_RS_NATIVE_LIBRARY_PATH = join(dirname(process.execPath), 'gpuix-native.node');
await import('./main');
