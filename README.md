# Onboarding

Windows PC를 Tailscale 네트워크에 연결하고 SSH 원격 지원을 준비하는 GPUIX 데스크톱 앱입니다. 공개 설치 파일에는 등록 키가 없습니다. 관리자가 Keyport 등으로 별도 발급한 **24시간 일회용·사전 승인 auth key**를 첫 실행에 입력합니다.

## 설치와 사용

1. [Releases](https://github.com/kiloworks/onboarding/releases)에서 CPU에 맞는 `windows-x64-setup.exe` 또는 `windows-arm64-setup.exe`를 받습니다.
2. 설치 후 시작 메뉴의 **Kiloworks → Onboarding**을 실행합니다.
3. 표시된 SSH 대상 Windows 계정과 작업 설명을 확인하고 전달받은 `tskey-auth-…` 키를 입력합니다.
4. 설치 시작 시 필요한 Windows 관리자 권한을 승인합니다. 대기 중에는 단계·경과 시간·진행 모션을 표시합니다.
5. 완료 리포트를 복사해 관리자에게 전달합니다. 실패 시 복구 가능한 작업을 한 번 재시도하고 실패 단계를 표시합니다.

**현재 버전은 미서명 테스트 릴리스입니다.** Windows SmartScreen 경고가 표시될 수 있습니다. 설치 파일의 출처와 함께 제공한 SHA-256을 확인하세요. 회사의 실행 정책을 임의로 해제하지 마세요.

## 기기에 적용하는 변경

- 공식 안정 채널을 조회하고 Tailscale이 없으면 설치, 구버전이면 업데이트합니다. 최신이면 다운로드를 생략합니다. 설치 MSI의 Authenticode 서명을 검증합니다.
- 기존 tailnet 연결은 화면에 표시합니다. 사용자가 로그아웃·새 연결을 선택한 경우에만 업데이트 후 기존 계정을 로그아웃합니다. 현재 연결을 유지하며 SSH 설정만 복구할 수도 있습니다.
- Tailscale을 unattended 모드로 연결하고 경로 수신을 끕니다.
- Windows OpenSSH Server를 설치하고 자동 시작합니다. 기본 보안키를 지원하지 않는 구버전은 Microsoft의 공식 GitHub MSI 배포로 업그레이드하며 Microsoft 서명을 검증합니다. 현재 upstream MSI 채널은 Preview 이름을 사용할 수 있습니다.
- [기본 공개키 두 개](config/administrators_authorized_keys)를 기존 키를 보존하며 등록합니다. 관리자 계정은 공통 관리자 키 파일, 일반 로컬 계정은 해당 사용자 프로필의 키 파일을 사용합니다.
- **모든 네트워크 프로필에서 TCP 22번 인바운드를 허용합니다.** Tailscale 인터페이스 전용 규칙이 아닙니다. 네트워크에서 PC에 도달할 수 있는 다른 장비도 SSH 연결을 시도할 수 있습니다.
- 기존 SSH 인증 정책은 임의로 변경하지 않습니다. 호환되지 않는 기존 설정·보안키 알고리즘은 실패 리포트로 알립니다.
- 앱을 제거해도 Tailscale과 SSH 설정은 유지됩니다. 원격 관리 해제는 [운영 문서](docs/operations.md)를 따릅니다.

## 지원과 검증 범위

목표 클라이언트는 Windows 10/11 **x64 및 ARM64**입니다. GPUIX·Bun·Windows 기능의 실제 제약이 적용되며 모든 과거 Windows 10 빌드의 검증을 의미하지 않습니다. 일반 로컬 Windows 계정을 대상으로 합니다. macOS와 Linux는 [후속 티켓](docs/tickets/)입니다.

GHA 매트릭스: `windows-2022`, `windows-2025`, `windows-11-arm`.

- 일반 CI: 타입 검사·핵심 로직·PowerShell 검사·GPUIX native UI 테스트·CPU별 빌드·설치 프로그램 설치/실행/제거.
- 별도 OIDC E2E: GitHub OIDC를 Tailscale WIF로 교환하여 일회용 tag:gha ephemeral 키를 발급하고 실제 앱에 입력, 실제 연결·SSH 준비·임시 테스트 키의 동일 기기 Tailscale 주소 SSH 인증을 확인한 뒤 로그아웃·미사용 키 정리.
- 서버 러너 합격은 Windows 10/11 x64 클라이언트 실기 검증을 대체하지 않습니다. UAC의 표준 사용자 경로, 재부팅 후 동작, 실제 ECDSA-SK 하드웨어 서명은 별도 검증이 필요합니다.
- 실제 연결 E2E는 WIF 설정 후 수동 실행합니다. 실행 기록이 없는 항목은 검증 완료로 간주하지 마세요.

## 비밀 처리

입력한 auth key는 메모리에서만 사용합니다. 승격 작업과 UI는 일회용 nonce로 인증한 loopback 연결로 통신하고, Tailscale CLI에는 메모리 named pipe 경로를 전달합니다. 키 원문을 프로세스 명령줄·디스크·로그에 넣지 않습니다. 승격용 임시 스크립트에는 키가 없고, 승격 후 해시를 확인한 동일 바이트만 실행합니다. 관리자 권한의 악성 프로세스나 동일 사용자 세션의 완전한 침해까지 보호하는 모델은 아닙니다.

지원 로그: `%LOCALAPPDATA%\Kiloworks\Onboarding\install.log`. 복사 리포트에는 단계·오류·SSH 계정·Tailscale 주소 등이 포함됩니다. 개인정보가 포함될 수 있으므로 관리자에게 비공개로 전달하세요.

## 개발

```sh
bun install --frozen-lockfile
bun run typecheck
bun test tests/core.test.ts
bun run test:ui
bun run dev
```

GPUIX native UI 테스트는 macOS와 Windows에서 가능합니다. Windows 설치 동작은 Windows에서만 실행합니다. `@gpuix/react`와 `@gpuix/native`는 0.10.0으로 함께 고정합니다.

Windows ARM64의 native npm 패키지가 현재 배포되지 않아 `.github/workflows/native-arm.yml`에서 고정한 upstream commit과 submodule로 직접 빌드합니다. x64는 npm의 대응 바이너리를 사용합니다. Bun 런타임과 MSVC app-local DLL은 설치 파일에 포함되므로 최종 사용자에게 Node/Bun/Rust 설치를 요구하지 않습니다.

```sh
bun run build
bun scripts/licenses.ts
# GHA가 native dependency notices를 dist/licenses/native에 추가합니다.
# NSIS로 packaging/onboarding.nsi를 패키징합니다.
```

공개 PR은 실제 Tailscale 자격 증명을 사용하지 않습니다. 실제 E2E 설정은 [WIF 문서](docs/wif-setup.md)를 참고하세요.

## 라이선스

앱 소스는 MIT입니다. GPUIX와 포함 런타임은 각 라이선스를 따릅니다. 설치 파일의 `licenses` 디렉토리와 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인하세요. 기존 비공개 tailscale-onboarding의 목적과 흐름을 참고했으며 그 소스와 자격 증명을 복사하지 않았습니다.
