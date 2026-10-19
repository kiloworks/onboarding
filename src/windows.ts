import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { createInterface } from 'node:readline';
import { mkdir, mkdtemp, writeFile, rm, appendFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import bootstrap from './windows.ps1' with { type: 'text' };
import publicKeys from '../config/administrators_authorized_keys' with { type: 'text' };
import { redact, type Event, type Machine } from './core';

export const powershell = process.platform === 'win32'
  ? join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  : 'powershell.exe';
const encode = (script: string) => Buffer.from(script, 'utf16le').toString('base64');

async function psJson(script: string): Promise<Machine> {
  const child = spawn(powershell, ['-NoProfile', '-NonInteractive', '-EncodedCommand', encode(script)], { windowsHide: true });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk.toString(); });
  child.stderr.resume();
  return await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error('기기 상태 확인 시간이 초과되었습니다.')); }, 30_000);
    child.on('error', () => { clearTimeout(timer); reject(new Error('Windows PowerShell을 시작할 수 없습니다.')); });
    child.on('exit', code => {
      clearTimeout(timer);
      try { if (code !== 0) throw new Error(); resolve(JSON.parse(output.replace(/^\uFEFF/, '').trim())); }
      catch { reject(new Error('기기 상태를 확인할 수 없습니다. 다시 시도해 주세요.')); }
    });
  });
}

export async function inspect(): Promise<Machine> {
  if (process.platform !== 'win32') throw new Error('현재 릴리스는 Windows 전용입니다. macOS·Linux는 준비 중입니다.');
  return psJson(`
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$ts = Join-Path $env:ProgramFiles 'Tailscale\\tailscale.exe'
$s = $null
if (Test-Path $ts) { try { $s = (& $ts status --json 2>$null | Out-String) | ConvertFrom-Json } catch {} }
$ssh = Get-Service sshd -ErrorAction SilentlyContinue
@{ installed = (Test-Path $ts); connected = ($null -ne $s -and $s.BackendState -eq 'Running'); tailnet = [string]$s.CurrentTailnet.Name; ip = [string]($s.TailscaleIPs | Select-Object -First 1); user = $id.Name; sid = $id.User.Value; sshReady = ($null -ne $ssh -and $ssh.Status -eq 'Running') } | ConvertTo-Json -Compress
`);
}

export async function copyReport(text: string): Promise<void> {
  const child = spawn(powershell, ['-NoProfile', '-NonInteractive', '-Command', '[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false); [Console]::In.ReadToEnd() | Set-Clipboard'], { windowsHide: true });
  child.stdin.end(redact(text)); child.stdout.resume(); child.stderr.resume();
  await new Promise<void>((resolve, reject) => {
    child.on('error', reject); child.on('exit', code => code === 0 ? resolve() : reject(new Error('복사하지 못했습니다. 리포트 텍스트를 선택해 복사해 주세요.')));
  });
}

export async function onboard(machine: Machine, key: string, replace: boolean, onEvent: (event: Event) => void): Promise<void> {
  const nonce = randomBytes(32).toString('hex');
  const session = randomBytes(16).toString('hex');
  const logDir = join(process.env.LOCALAPPDATA || '.', 'Kiloworks', 'Onboarding');
  await mkdir(logDir, { recursive: true });
  let finish!: () => void, fail!: (error: Error) => void;
  const completion = new Promise<void>((resolve, reject) => { finish = resolve; fail = reject; });
  let authenticated = false;
  let finished = false;
  let timer: ReturnType<typeof setTimeout>;
  const server = createServer(socket => {
    if (authenticated) { socket.destroy(); return; }
    let first = true;
    const reader = createInterface({ input: socket });
    socket.setTimeout(120_000, () => socket.destroy());
    reader.on('line', line => {
      if (line.length > 65_536) { socket.destroy(); return; }
      if (first) {
        first = false;
        const received = Buffer.from(line);
        const expected = Buffer.from(nonce);
        if (received.length !== expected.length || !timingSafeEqual(received, expected) || authenticated) { socket.destroy(); return; }
        authenticated = true; clearTimeout(timer); socket.setTimeout(0);
        socket.write(JSON.stringify({ key, replace, sid: machine.sid, keys: publicKeys.trim().split(/\r?\n/), session }) + '\n');
        key = '';
        return;
      }
      if (!authenticated) return;
      try {
        const event = JSON.parse(line) as Event;
        event.message = redact(String(event.message || ''));
        if (event.report) event.report = redact(event.report);
        onEvent(event);
        void appendFile(join(logDir, 'install.log'), `${new Date().toISOString()} ${event.stage}: ${event.message}\n`).catch(() => {});
        if (event.done) { finished = true; event.ok ? finish() : fail(new Error(event.message)); socket.end(); }
      } catch { /* Ignore non-protocol output; never log raw input. */ }
    });
    socket.on('error', () => { if (authenticated && !finished) fail(new Error('관리자 작업 연결이 종료되었습니다. 상태를 확인하고 다시 시도해 주세요.')); });
    socket.on('close', () => { if (authenticated && !finished) fail(new Error('관리자 작업 연결이 종료되었습니다.')); });
  });
  await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('작업 연결을 만들 수 없습니다.');
  // The on-disk helper contains no secret; elevated code verifies its exact bytes before execution.
  const helperDir = await mkdtemp(join(tmpdir(), 'onboarding-'));
  const helperPath = join(helperDir, 'bootstrap.ps1');
  await writeFile(helperPath, bootstrap, { mode: 0o600 });
  const hash = createHash('sha256').update(bootstrap).digest('hex');
  const elevated = `$bytes = [IO.File]::ReadAllBytes('${helperPath.replaceAll("'", "''")}'); $sha = [Security.Cryptography.SHA256]::Create(); $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant(); if ($hash -ne '${hash}') { exit 1 }; $Port=${address.port}; $Nonce='${nonce}'; & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($bytes)))`;
  const helper = encode(elevated);
  const launcher = `try { $p = Start-Process -FilePath '${powershell.replaceAll("'", "''")}' -ArgumentList '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${helper}' -Verb RunAs -WindowStyle Hidden -Wait -PassThru; exit $p.ExitCode } catch { exit 1223 }`;
  const child = spawn(powershell, ['-NoProfile', '-NonInteractive', '-EncodedCommand', encode(launcher)], { windowsHide: true });
  child.stdout.resume(); child.stderr.resume();
  child.once('error', () => fail(new Error('관리자 작업을 시작하지 못했습니다.')));
  child.once('exit', code => { if (!finished) fail(new Error(code === 1223 ? '관리자 권한 요청이 취소되었습니다. 변경을 시작하지 않았습니다.' : '관리자 작업이 종료되었습니다. 상태를 확인하고 다시 시도해 주세요.')); });
  timer = setTimeout(() => fail(new Error('관리자 권한 승인을 기다리는 시간이 초과되었습니다.')), 120_000);
  const deadline = setTimeout(() => fail(new Error('설치 시간이 초과되었습니다. 리포트를 관리자에게 전달해 주세요.')), 45 * 60_000);
  try { await completion; }
  finally { clearTimeout(timer); clearTimeout(deadline); key = ''; server.close(); await rm(helperDir, { recursive: true, force: true }); }
}
