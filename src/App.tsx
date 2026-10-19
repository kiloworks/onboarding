import { useEffect, useState, type ReactNode } from 'react';
import { needsKey, report, validateKey, type Event, type Machine } from './core';

export type Services = {
  inspect(): Promise<Machine>;
  onboard(machine: Machine, key: string, replace: boolean, event: (event: Event) => void): Promise<void>;
  copyReport(text: string): Promise<void>;
};
const ink = '#17212f', muted = '#536174', blue = '#2563eb', line = '#e3e8ef';
const text = { fontFamily: 'Pretendard', color: ink, fontSize: 15, lineHeight: 22 };
const column = { display: 'flex', flexDirection: 'column' } as const;
const labels: Record<string, string> = { update: 'Tailscale 설치 · 업데이트', logout: '기존 계정 로그아웃', connect: '네트워크 연결', ssh: '원격 접속 준비', verify: '최종 확인' };
function Button({ id, children, action, secondary = false }: { id: string; children: ReactNode; action(): void; secondary?: boolean }) {
  const [focused, setFocused] = useState(false);
  return <div testId={id} role="button" aria-label={typeof children === 'string' ? children : id} tabIndex={0}
    onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
    onClick={action} onKeyDown={e => { if (e.key === 'enter' || e.key === 'space') action(); }}
    style={{ ...column, padding: 14, borderRadius: 10, alignItems: 'center', cursor: 'pointer', borderWidth: 1,
      borderColor: secondary ? line : blue, backgroundColor: secondary ? '#ffffff' : blue,
      boxShadow: focused ? { offsetX: 0, offsetY: 0, blurRadius: 0, spreadRadius: 3, color: '#bfdbfe' } : undefined,
      hover: { backgroundColor: secondary ? '#f3f5f8' : '#1d4ed8' }, active: { opacity: 0.8 } }}>
    <text style={{ ...text, color: secondary ? ink : '#ffffff', fontWeight: 600 }}>{children}</text>
  </div>;
}

export function App({ services }: { services: Services }) {
  const [page, setPage] = useState<'intro' | 'key' | 'review'>('intro');
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
    setPhase('loading'); setEvents([]); setKey(''); setPage('intro');
    try { setMachine(await services.inspect()); setPhase('ready'); setMessage('관리자에게 받은 키로 이 기기를 준비합니다.'); }
    catch (e) { setPhase('error'); setMessage(e instanceof Error ? e.message : '상태 확인에 실패했습니다.'); }
  };
  useEffect(() => { void load(); }, []);
  useEffect(() => {
    if (phase !== 'working') return;
    const timer = setInterval(() => { setElapsed(v => v + 1); if (motion) setPulse(v => !v); }, 1000);
    return () => clearInterval(timer);
  }, [phase, motion]);
  const next = () => {
    if (!machine) return;
    try {
      if (needsKey(machine, replace)) validateKey(key);
      setMessage('설정할 내용을 확인해 주세요.'); setPage('review');
    } catch (e) { setMessage((e as Error).message); }
  };
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
  const step = phase === 'working' || phase === 'done' ? 2 : page === 'review' ? 1 : 0;
  const title = phase === 'done' ? '원격 지원을 받을 준비가 됐어요.'
    : phase === 'error' ? '잠시 멈췄어요. 함께 확인해요.'
    : phase === 'working' ? '차근차근 준비하고 있어요.'
    : page === 'intro' ? '이 기기를 연결해 볼까요?'
    : page === 'key' ? '연결 정보를 알려주세요.' : '시작 전에 확인해 주세요.';
  return <div style={{ ...column, width: '100%', height: '100%', backgroundColor: '#f6f8fb', padding: 24, alignItems: 'center', gap: 16 }}>
    <div style={{ display: 'flex', flexDirection: 'row', width: 700, alignItems: 'center', justifyContent: 'space-between' }}>
      <text style={{ ...text, fontSize: 17, fontWeight: 600 }}>kiloworks / onboarding</text>
      <text style={{ ...text, color: muted, fontSize: 12 }}>Windows · x64 / ARM64</text>
    </div>
    <div style={{ ...column, width: 700, flexGrow: 1, padding: 26, gap: 16, backgroundColor: '#ffffff', borderWidth: 1, borderColor: line, borderRadius: 18 }}>
      <div style={{ display: 'flex', flexDirection: 'row', gap: 24, alignItems: 'center' }}>
        {['연결 정보', '설정 확인', '기기 준비'].map((label, index) => <div key={label} style={{ display: 'flex', flexDirection: 'row', gap: 8, alignItems: 'center' }}>
          <div style={{ ...column, width: 24, height: 24, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: index <= step ? blue : '#eef1f5' }}>
            <text style={{ ...text, fontSize: 12, color: index <= step ? '#ffffff' : muted }}>{phase === 'done' || index < step ? '✓' : index + 1}</text>
          </div>
          <text style={{ ...text, fontSize: 13, color: index === step ? ink : muted, fontWeight: index === step ? 600 : 400 }}>{label}</text>
        </div>)}
      </div>
      <div key={`${phase}-${page}`} motion={{ initial: { opacity: motion ? 0 : 1 }, animate: { opacity: 1 }, transition: { duration: motion ? 0.2 : 0 } }}
        style={{ ...column, flexGrow: 1, gap: 12, paddingTop: 12 }}>
        <text testId="heading" role="heading" aria-level={1} style={{ ...text, fontSize: 27, lineHeight: 38, fontWeight: 600 }}>{title}</text>
        <text testId="status" role="status" style={{ ...text, color: phase === 'error' ? '#a33a2b' : muted, fontSize: 14 }}>{message}</text>
        {phase === 'ready' && machine && page === 'intro' && <>
          <div style={{ ...column, backgroundColor: '#f6f8fb', padding: 20, gap: 15, borderRadius: 12 }}>
            <text style={{ ...text, fontWeight: 600 }}>관리자에게 받은 등록 키만 준비해 주세요.</text>
            <text style={{ ...text, color: muted }}>1. 연결 정보를 입력해요.</text>
            <text style={{ ...text, color: muted }}>2. 이 기기에 설정할 내용을 확인해요.</text>
            <text style={{ ...text, color: muted }}>3. 필요한 순간에 Windows 관리자 권한을 요청해요.</text>
          </div>
          <text style={{ ...text, color: muted, fontSize: 13 }}>설치 중에도 진행 상황을 알려드려요. 입력한 등록 키는 저장하지 않아요.</text>
          <div style={{ ...column, flexGrow: 1 }} />
          <Button id="begin" action={() => { setPage('key'); setMessage('관리자가 전달한 일회용 등록 키를 붙여넣어 주세요.'); }}>시작하기</Button>
        </>}
        {phase === 'ready' && machine && page === 'key' && <>
          <div style={{ ...column, backgroundColor: '#f6f8fb', padding: 16, gap: 5, borderRadius: 10 }}>
            <text style={{ ...text, fontSize: 14 }}>{`이 기기의 계정: ${machine.user}`}</text>
            <text style={{ ...text, color: muted, fontSize: 13 }}>{machine.connected ? `현재 연결: ${machine.tailnet} · ${machine.ip}` : '아직 Tailscale에 연결되지 않았어요.'}</text>
          </div>
          {machine.connected && <Button id="replace" secondary action={() => { setReplace(v => !v); setKey(''); }}>{replace ? '✓ 기존 계정 로그아웃 후 새 연결 선택됨' : '현재 연결 유지 · 누르면 다른 네트워크로 변경'}</Button>}
          {needsKey(machine, replace) && <div style={{ ...column, gap: 9 }}>
            <text style={{ ...text, fontSize: 14, fontWeight: 600 }}>Tailscale 등록 키</text>
            <input testId="auth-key" role="textbox" aria-label="Tailscale 등록 키" value={key} onChange={e => setKey(e.value || '')} placeholder="tskey-auth-… 붙여넣기"
              theme={{ appearance: 'light', caret: blue, accent: blue, text: ink, bg: '#ffffff', border: '#c4cedb' }}
              style={{ ...text, backgroundColor: '#ffffff', padding: 14, height: 50, borderWidth: 1, borderColor: '#c4cedb', borderRadius: 10 }} />
            <text style={{ ...text, color: muted, fontSize: 12 }}>24시간 유효 · 일회용 · 기기에 저장하지 않음</text>
          </div>}
          <div style={{ ...column, flexGrow: 1 }} />
          <div style={{ display: 'flex', flexDirection: 'row', gap: 12 }}>
            <div style={{ ...column, width: 100 }}><Button id="back" secondary action={() => setPage('intro')}>뒤로</Button></div>
            <div style={{ ...column, flexGrow: 1 }}><Button id="next" action={next}>다음</Button></div>
          </div>
        </>}
        {phase === 'ready' && machine && page === 'review' && <>
          <div style={{ ...column, backgroundColor: '#f6f8fb', padding: 18, gap: 11, borderRadius: 12 }}>
            <text style={{ ...text, fontSize: 14 }}>{`SSH 접속 대상: ${machine.user}`}</text>
            <text style={{ ...text, fontSize: 14 }}>{replace ? '기존 Tailscale 계정 로그아웃 후 새 네트워크에 연결' : machine.connected ? '현재 네트워크 연결 유지' : '등록 키로 Tailscale 네트워크에 연결'}</text>
            <text style={{ ...text, fontSize: 14 }}>Tailscale 최신 버전과 Windows SSH 서버 준비</text>
            <text style={{ ...text, fontSize: 14 }}>기본 관리자 공개키 두 개 등록</text>
          </div>
          <div style={{ ...column, backgroundColor: '#fff7ed', padding: 14, borderRadius: 10 }}>
            <text style={{ ...text, color: '#8b4b18', fontSize: 14 }}>모든 네트워크에서 SSH 접속(TCP 22번)을 허용해요.</text>
          </div>
          <text style={{ ...text, color: muted, fontSize: 13 }}>아래 버튼을 누르면 이 설정에 동의하고 Windows 승인 창으로 이동해요.</text>
          <div style={{ ...column, flexGrow: 1 }} />
          <div style={{ display: 'flex', flexDirection: 'row', gap: 12 }}>
            <div style={{ ...column, width: 100 }}><Button id="back" secondary action={() => setPage('key')}>뒤로</Button></div>
            <div style={{ ...column, flexGrow: 1 }}><Button id="start" action={() => void start()}>동의하고 준비 시작</Button></div>
          </div>
        </>}
        {phase === 'working' && <>
          <div style={{ ...column, padding: 18, gap: 16, backgroundColor: '#f6f8fb', borderRadius: 12 }}>
            {Object.entries(labels).filter(([id]) => id !== 'logout' || replace).map(([id, label]) => {
              const active = latest?.stage === id;
              const complete = Object.keys(labels).indexOf(id) < Object.keys(labels).indexOf(latest?.stage || '');
              return <div key={id} style={{ display: 'flex', flexDirection: 'row', gap: 12, alignItems: 'center' }}>
                <div motion={{ animate: { opacity: active && motion && pulse ? 0.4 : 1 }, transition: { duration: motion ? 0.7 : 0 } }}
                  style={{ ...column, width: 22, height: 22, borderRadius: 11, backgroundColor: active || complete ? blue : '#e2e7ef', alignItems: 'center', justifyContent: 'center' }}>
                  <text style={{ ...text, color: '#ffffff', fontSize: 12 }}>{complete ? '✓' : active ? '·' : ''}</text>
                </div>
                <text style={{ ...text, color: active ? blue : complete ? ink : muted, fontSize: 14 }}>{label}</text>
              </div>;
            })}
          </div>
          <text style={{ ...text, color: muted, fontSize: 13 }}>{`경과 ${Math.floor(elapsed / 60)}분 ${elapsed % 60}초 · 창을 닫지 말고 기다려 주세요.`}</text>
          <text style={{ ...text, color: muted, fontSize: 13 }}>다운로드와 설치에 몇 분 걸릴 수 있어요. 문제가 생기면 한 번 더 시도해요.</text>
          <div style={{ ...column, flexGrow: 1 }} />
          <Button id="motion" secondary action={() => setMotion(v => !v)}>{motion ? '모션 줄이기' : '모션 켜기'}</Button>
        </>}
        {(phase === 'done' || phase === 'error') && <>
          {latest?.report && <div role="region" aria-label="준비 결과" tabIndex={0} style={{ ...column, maxHeight: 180, overflowY: 'scroll', backgroundColor: '#f6f8fb', padding: 16, borderRadius: 12 }}>
            <text testId="report" style={{ ...text, fontSize: 13, lineHeight: 20 }}>{latest.report}</text>
          </div>}
          <text style={{ ...text, color: muted, fontSize: 13 }}>{phase === 'done' ? '관리자에게 이 리포트를 전달해 실제 원격 접속을 확인해 주세요.' : '연결된 설정은 유지해요. 상태를 다시 확인하거나 리포트를 관리자에게 전달해 주세요.'}</text>
          <div style={{ ...column, flexGrow: 1 }} />
          <div style={{ display: 'flex', flexDirection: 'row', gap: 12 }}>
            <div style={{ ...column, width: 185 }}><Button id="refresh" secondary action={() => { setReplace(false); void load(); }}>현재 상태 다시 확인</Button></div>
            <div style={{ ...column, flexGrow: 1 }}><Button id="copy-report" action={() => void copy()}>관리자에게 리포트 복사</Button></div>
          </div>
        </>}
      </div>
    </div>
    <text style={{ ...text, color: muted, fontSize: 12 }}>v0.1.1 · 미서명 프리뷰 · 원격 접속 확인은 관리자와 함께 진행해 주세요.</text>
  </div>;
}
