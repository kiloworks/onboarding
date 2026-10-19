export type Machine = {
  installed: boolean; connected: boolean; tailnet: string; ip: string;
  user: string; sid: string; sshReady: boolean;
};
export type Event = { stage: string; message: string; done?: boolean; ok?: boolean; report?: string };
export const steps = ['update', 'logout', 'connect', 'ssh', 'verify'] as const;

export function validateKey(value: string): string {
  const key = value.trim();
  if (!/^tskey-auth-[A-Za-z0-9_-]{10,}$/.test(key) || key.length > 512)
    throw new Error('관리자에게 전달받은 Tailscale 등록 키(tskey-auth-…)를 확인해 주세요.');
  return key;
}

export function redact(value: string): string {
  return value.replace(/tskey-[A-Za-z0-9_-]+/g, '[비밀 삭제]')
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[토큰 삭제]');
}

export function needsKey(machine: Machine, replaceConnection: boolean): boolean {
  return !machine.connected || replaceConnection;
}

export function report(events: Event[], user: string): string {
  return redact([
    'Onboarding 0.1.0 — 지원 리포트', new Date().toISOString(),
    `SSH 대상 계정: ${user}`, 'SSH 방화벽: 모든 네트워크의 TCP 22',
    '관리자 측 원격 접속: 이 앱에서는 검증하지 않음',
    ...events.map(e => `[${e.stage}] ${e.message}`),
    ...events.filter(e => e.report).map(e => e.report!),
  ].join('\n'));
}
