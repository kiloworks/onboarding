import { useLayoutEffect, useState, type ReactNode } from 'react';
import { useGpuixRequired } from '@gpuix/react';
import { readFileSync } from 'node:fs';
import regular from '../assets/fonts/Pretendard-Regular.otf' with { type: 'file' };
import semibold from '../assets/fonts/Pretendard-SemiBold.otf' with { type: 'file' };

export function AppFonts({ children }: { children: ReactNode }) {
  const renderer = useGpuixRequired();
  const [ready, setReady] = useState(false);
  useLayoutEffect(() => {
    // This API is in our pinned native source but not the published 0.10.0 declarations.
    const fonts = renderer as unknown as { registerFont?: (data: Buffer) => void };
    if (process.platform === 'win32' && !fonts.registerFont) throw new Error('폰트를 지원하는 Windows 렌더러가 필요합니다.');
    if (fonts.registerFont) {
      fonts.registerFont(readFileSync(regular));
      fonts.registerFont(readFileSync(semibold));
    }
    setReady(true);
  }, [renderer]);
  return ready ? children : null;
}
