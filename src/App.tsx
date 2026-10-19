import { useEffect, useState, type ReactNode } from 'react';
import { needsKey, report, validateKey, type Event, type Machine } from './core';

export type Services = {
  inspect(): Promise<Machine>;
  onboard(machine: Machine, key: string, replace: boolean, event: (event: Event) => void): Promise<void>;
  copyReport(text: string): Promise<void>;
};
const ink = '#f0f5f1', muted = '#a0b1aa', green = '#c1edab';
const labels: Record<string, string> = { update: '설치 · 업데이트', logout: '계정 전환', connect: '네트워크 연결', ssh: '원격 접속 준비', verify: '최종 확인' };
function Button({ id, children, action, secondary = false }: { id: string; children: ReactNode; action(): void; secondary?: boolean }) {
  return <div testId={id} role="button" aria-label={typeof children === 'string' ? children : id} tabIndex={0}
    onClick={action} onKeyDown={e => { if (e.key === 'enter' || e.key === 'space') action(); }}
    style={{display: 'flex', flexDirection: 'column',  padding: 15, borderRadius: 12, cursor: 'pointer', backgroundColor: secondary ? '#283831' : green, hover: { backgroundColor: secondary ? '#34493e' : '#d3f5c5' } }}>
    <text style={{ color: secondary ? ink : '#18301e', fontSize: 15, fontWeight: 600 }}>{children}</text>
  </div>;
}

export function App({ services }: { services: Services }) {
  const [machine, setMachine] = useState<Machine | null>(null);
  const [key, setKey] = useState('');
  const [replace, setReplace] = useState(false);
  const [events, setEvents] = useState<Event[]>([]);
  const [phase, setPhase] = useState<'loading' | 'ready' | 'working' | 'done' | 'error'>('loading');
  const [message, setMessage] = useState('이 기기의 네트워크와 원격 접속 상태를 확인합니다.');
  const [motion, setMotion] = useState(true);
  const [pulse, setPulse] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const load = async () => {
    setPhase('loading');
    try { setMachine(await services.inspect()); setPhase('ready'); setMessage('관리자에게 받은 키로 이 기기를 준비합니다.'); }
    catch (e) { setPhase('error'); setMessage(e instanceof Error ? e.message : '상태 확인에 실패했습니다.'); }
  };
  useEffect(() => { void load(); }, []);
  useEffect(() => {
    if (phase !== 'working') return;
    const timer = setInterval(() => { setElapsed(v => v + 1); if (motion) setPulse(v => !v); }, 1000);
    return () => clearInterval(timer);
  }, [phase, motion]);
  const start = async () => {
    if (!machine || phase === 'working') return;
    let auth = '';
    try { if (needsKey(machine, replace)) auth = validateKey(key); }
    catch (e) { setMessage((e as Error).message); return; }
    setKey(''); setElapsed(0); setEvents([]); setPhase('working');
    setMessage('필요한 관리자 권한을 요청합니다. Windows 승인 창을 확인해 주세요.');
    try {
      await services.onboard(machine, auth, replace, e => { setEvents(v => [...v, e]); setMessage(e.message); });
      setPhase('done');
    } catch (e) { setPhase('error'); setMessage(e instanceof Error ? e.message : '작업이 중단되었습니다.'); }
    finally { auth = ''; }
  };
  const latest = events.at(-1);
  const copy = async () => {
    try { await services.copyReport(report(events.length ? events : [{ stage: phase, message }], machine?.user || '확인 전')); setMessage('지원 리포트를 복사했습니다. 인프라 관리자에게 전달해 주세요.'); }
    catch { setMessage('리포트 복사에 실패했습니다. 로그는 %LOCALAPPDATA%\\Kiloworks\\Onboarding\\install.log에 있습니다.'); }
  };
  return <div style={{display: 'flex',  width: '100%', height: '100%', backgroundColor: '#101b17', flexDirection: 'row', padding: 28, gap: 28 }}>
    <div style={{display: 'flex',  width: 210, padding: 18, flexDirection: 'column', gap: 24, borderRadius: 20, backgroundColor: '#192a22' }}>
      <text style={{ color: green, fontSize: 13, fontWeight: 700 }}>KILOWORKS</text>
      <text style={{ color: ink, fontSize: 29, fontWeight: 700 }}>Onboarding</text>
      <text style={{ color: muted, fontSize: 14 }}>연결부터 원격 지원까지</text>
      <div style={{display: 'flex', flexDirection: 'column',  height: 24 }} />
      {Object.entries(labels).map(([id, label], index) => <div key={id} style={{display: 'flex',  gap: 10, flexDirection: 'row', alignItems: 'center' }}>
        <div style={{display: 'flex', flexDirection: 'column',  width: 28, height: 28, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: latest?.stage === id ? green : '#30463a' }}>
          <text style={{ color: latest?.stage === id ? '#18301e' : muted, fontSize: 12 }}>{index + 1}</text>
        </div>
        <text style={{ color: latest?.stage === id ? ink : muted, fontSize: 14 }}>{label}</text>
      </div>)}
      <div style={{display: 'flex', flexDirection: 'column',  flexGrow: 1 }} />
      <text style={{ color: muted, fontSize: 12 }}>Windows · x64 / ARM64</text>
      <text style={{ color: muted, fontSize: 12 }}>v0.1.0 · 미서명 테스트 버전</text>
    </div>
    <div style={{display: 'flex',  flexGrow: 1, flexDirection: 'column', gap: 18, paddingTop: 16 }}>
      <text style={{ color: green, fontSize: 13 }}>{phase === 'working' ? '준비 중 · 창을 닫지 마세요' : phase === 'done' ? '준비 완료' : '기기 준비'}</text>
      <text testId="heading" role="heading" aria-level={1} style={{ color: ink, fontSize: 29, fontWeight: 700 }}>{phase === 'done' ? '원격 지원을 받을 준비가 됐어요.' : phase === 'working' ? '차근차근 준비하고 있어요.' : '이 기기를 안전하게 연결해요.'}</text>
      <text testId="status" role="status" style={{ color: muted, fontSize: 15 }}>{message}</text>
      {phase === 'ready' && machine && <>
        <div style={{display: 'flex', flexDirection: 'column',  backgroundColor: '#1b2d24', padding: 16, gap: 8, borderRadius: 12 }}>
          <text style={{ color: ink, fontSize: 14 }}>{`SSH 대상 계정: ${machine.user}`}</text>
          <text style={{ color: muted, fontSize: 13 }}>{machine.connected ? `현재 연결: ${machine.tailnet} · ${machine.ip}` : 'Tailscale 네트워크에 아직 연결되지 않았습니다.'}</text>
        </div>
        {machine.connected && <Button id="replace" secondary action={() => setReplace(v => !v)}>{replace ? '✓ 기존 계정 로그아웃 및 새 네트워크 연결에 동의함' : '현재 연결 유지 · 누르면 로그아웃 및 새 연결 선택'}</Button>}
        {needsKey(machine, replace) && <div style={{display: 'flex', flexDirection: 'column',  gap: 8 }}>
          <text style={{ color: ink, fontSize: 14 }}>관리자에게 받은 Tailscale 등록 키</text>
          <input testId="auth-key" role="textbox" aria-label="Tailscale 등록 키" value={key} onChange={e => setKey(e.value || '')} placeholder="tskey-auth-… 붙여넣기" style={{ backgroundColor: '#25392e', color: ink, padding: 14, height: 48, borderRadius: 10, fontSize: 14 }} />
          <text style={{ color: muted, fontSize: 12 }}>24시간 유효 · 일회용 · 입력한 키는 저장하지 않습니다.</text>
        </div>}
        <text style={{ color: muted, fontSize: 13 }}>Tailscale을 최신 상태로 업데이트하고 SSH 서버를 준비합니다.</text>
        <text style={{ color: '#efc38c', fontSize: 13 }}>두 관리자 공개키를 등록하고 모든 네트워크에서 SSH(22번)를 허용합니다.</text>
        <Button id="start" action={() => void start()}>{machine.connected && !replace ? '현재 연결을 유지하고 점검 · 복구' : '동의하고 기기 준비 시작'}</Button>
      </>}
      {phase === 'working' && <div style={{display: 'flex', flexDirection: 'column',  padding: 22, gap: 18, backgroundColor: '#1b2d24', borderRadius: 16 }}>
        <div style={{display: 'flex', flexDirection: 'column',  height: 8, borderRadius: 4, backgroundColor: '#30463a', overflow: 'hidden' }}>
          <div motion={{ animate: { opacity: pulse ? 0.35 : 1 }, transition: { duration: motion ? 0.8 : 0 } }} style={{display: 'flex', flexDirection: 'column',  width: '100%', height: 8, borderRadius: 4, backgroundColor: green }} />
        </div>
        <text style={{ color: ink, fontSize: 15 }}>{`경과 ${Math.floor(elapsed / 60)}분 ${elapsed % 60}초`}</text>
        <text style={{ color: muted, fontSize: 14 }}>Windows 기능 설치는 몇 분 걸릴 수 있어요. 실제 작업 상태를 계속 알려드릴게요.</text>
        <Button id="motion" secondary action={() => setMotion(v => !v)}>{motion ? '모션 줄이기' : '모션 켜기'}</Button>
      </div>}
      {(phase === 'done' || phase === 'error') && <>
        {latest?.report && <text testId="report" style={{ color: ink, fontSize: 14 }}>{latest.report}</text>}
        <Button id="copy-report" action={() => void copy()}>인프라 관리자에게 보낼 리포트 복사</Button>
        <Button id="refresh" secondary action={() => { setReplace(false); void load(); }}>현재 상태 확인 · 다시 준비</Button>
      </>}
      <div style={{display: 'flex', flexDirection: 'column',  flexGrow: 1 }} />
      <text style={{ color: muted, fontSize: 12 }}>네트워크 연결과 로컬 SSH 설정을 확인합니다. 관리자 측 실제 원격 접속은 별도 확인이 필요합니다.</text>
    </div>
  </div>;
}
