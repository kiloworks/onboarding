# Windows 검증 계획

## 사용자 실기 검증 기록

- 2026-10-19: magneto가 Rust GPUI 전환 후 ARM 기기에서 실행과 SSH 접속 성공을 확인했다. Windows 빌드 번호, SSH 접속 경로와 실제 FIDO 하드웨어 사용 여부는 확인하지 않았다.
- 설치파일 다운로드가 Edge의 유지 선택 후에도 차단되고, Defender 실시간 보호를 끄면 다운로드된다는 보고가 있다. 제공된 보호 기록은 `Trojan:Win32/Wacatac.B!ml`, 상태 제거됨이며, Discord 첨부파일 `onboarding-0.2.0-windows-x64-setup.exe`를 받던 `.crdownload`가 대상이다. ARM 실행 성공과 이 x64 파일 탐지는 별도 증거로 취급한다. Discord 파일과 공식 릴리스의 바이트 일치 및 오탐 여부는 확인하지 않았다. 실시간 보호 해제는 배포 해결책으로 채택하지 않는다.
- 공식 v0.2.0 x64 릴리스 설치파일 SHA-256 재확인: `7471d1fd6d57abc054e14646a3b99739e0a66dc71de3fca0f2bd0d8154fe22d4`.
- 후속 보호 기록에서 GitHub 공식 릴리스 다운로드(`release-assets.githubusercontent.com`, x64 설치파일)도 동일한 `Trojan:Win32/Wacatac.B!ml` 판정으로 제거됨을 확인했다. Discord 경로에만 국한된 현상이 아니다. 설치파일 또는 내부 구성요소 중 어느 부분이 탐지 원인인지는 아직 확인하지 않았다.

## 확정 요구사항

2026-10-19 magneto 요청: 실제 클라이언트인 Windows 10 x64와 Windows 11 x64를 지원하고, GitHub Actions에서 가능한 범위까지 실제 E2E를 수행한다.

| 러너 | 실제 검증 환경 | 목적 |
| --- | --- | --- |
| windows-2022 | Windows Server 2022 x64 | x64 패키지·앱·설치·서비스 통합 검증 |
| windows-2025 | Windows Server 2025 x64 | x64 패키지·앱·설치·서비스 통합 검증 |
| windows-11-arm | Windows 11 ARM64 | 첫 출시 ARM64 native 패키지·앱·설치·서비스 통합 검증 |

Server 러너 합격을 Windows 10/11 x64 클라이언트 합격으로 표기하지 않는다. 클라이언트 OS의 UAC, GPU/드라이버, 일반 사용자 시작, 재부팅 후 서비스, 실제 보안키 SSH 서명 검증은 해당 OS의 별도 VM/실기 검증으로 보완한다. 필요한 클라이언트 테스트 환경은 아직 확보·결정하지 않았다.

## GHA에서 구현할 검증 범위

- 고정된 GPUI·런타임 버전으로 빌드·Rust 검사·테스트·패키징을 검증한다.
- Windows 접근성 UIAutomation API으로 키 입력·검증·진행·실패·완료 UI를 테스트한다. 실제 창 실행과 headless 렌더링 검증을 구분한다.
- 패키지 설치와 앱 실행, Tailscale 탐지·필요 시 설치, 네트워크 등록과 실제 연결 상태를 확인한다.
- OpenSSH 서비스·자동 시작·방화벽·기본 공개키 두 개·파일 권한을 확인한다. 기존 공개키 보존과 재실행 시 중복 등록 방지를 검증한다.
- 별도 임시 SSH 테스트 키를 이용한 실제 SSH 인증·명령 실행으로 원격 경로를 검증한다. 이 테스트 키는 배포 앱에 포함하지 않는다. 기본 ECDSA-SK 두 키의 실제 하드웨어 서명 검증을 이 테스트로 대체했다고 주장하지 않는다.
- 만료/소비된 키·네트워크 실패·부분 실패·재실행과 로그 비밀 비노출을 검증한다. 실제 API가 필요하지 않은 실패는 mock으로 재현한다.
- 실제 E2E는 각 매트릭스 작업에 서로 다른 일회용 키와 기기 이름을 사용하고, 실패해도 테스트 노드와 임시 자격 증명을 정리한다.
- 비밀 없는 PR 검증과 신뢰된 코드만 실행하는 비밀 사용 E2E를 분리한다. 외부 PR에 실제 자격 증명을 노출하지 않는다.
- GPUI/native ARM64 배포 여부와 번들 런타임 호환성은 구현 전 확인한다. 미지원·실행 불가를 조용히 생략하거나 성공으로 바꾸지 않고 실패/제약과 후속 조치를 명시한다.

## 아직 결정할 사항

- 실제 E2E는 [GitHub OIDC 결정](adr/0004-github-oidc-e2e.md)에 따라 Tailscale WIF와 tag:gha-smoke-test-node를 사용한다. 실제 tailnet·Client ID·audience·claim 제한 설정과 사용자 소유 등록의 별도 검증 방법은 준비가 필요하다.
- Windows 10/11 x64 실제 클라이언트 VM 또는 실기 검증 환경과 릴리스 승인 조건.
- ARM64는 첫 출시 정식 지원 대상이며 native 배포 경로의 실제 GPUI·런타임 지원 확인이 필요하다.

## 확인한 공식 자료

- [GitHub 호스팅 러너](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Windows Server 2025 이미지](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md)
- [GPUI 문서](https://gpuix.dev/): Windows DirectX 기반 native 테스트 지원. 프로젝트에서 동일 경로가 실행되는지는 실제 검증이 필요하다.
