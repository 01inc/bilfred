import { spawn } from 'node:child_process';
process.loadEnvFile('.env');
const child = spawn('uv', ['run', '--project', 'apps/api', '--directory', 'apps/api',
  'uvicorn', 'bilfred.app:app', '--host', '127.0.0.1', '--port', '8008', '--no-access-log'],
{ env: process.env, stdio: 'inherit' });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
child.on('exit', code => { process.exitCode = code; });
