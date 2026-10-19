# v0.2.0 Defender 재심 준비

제출 상태: 미제출. 사용자 보호 기록으로 공식 GitHub x64 릴리스 다운로드 차단을 확인했으며 오탐 의심으로 분석을 요청한다. 오탐 확정이나 해결 완료로 취급하지 않는다.

- 제출처: https://www.microsoft.com/en-us/wdsi/filesubmission
- 제출 유형: Software developer (소프트웨어 개발자)
- 제품: Microsoft Defender Antivirus. 해당 PC의 Windows 10/11 버전에 맞춰 선택하며 SmartScreen으로 제출하지 않는다.
- 판정 이의: Incorrectly detected as malware/malicious (악성코드로 잘못 탐지됨)
- 탐지 이름: `Trojan:Win32/Wacatac.B!ml`
- 파일: `onboarding-0.2.0-windows-x64-setup.exe`, 4,051,368바이트
- SHA-256: `7471d1fd6d57abc054e14646a3b99739e0a66dc71de3fca0f2bd0d8154fe22d4`
- 공식 다운로드: https://github.com/kiloworks/onboarding/releases/download/v0.2.0/onboarding-0.2.0-windows-x64-setup.exe
- 소스 커밋: `0c7da14f19209a156f66967d5138b026c962ddf2`
- 추가 확보 사항: 대상 PC의 Windows 버전과 Defender 보안 인텔리전스 버전. 보호 기록의 개인 계정 경로 및 서명된 임시 다운로드 URL은 공개 제출 설명에 포함하지 않는다.

## 제출 설명 초안

Please review this suspected false positive affecting Kiloworks Onboarding v0.2.0, an unsigned open-source Rust GPUI desktop application packaged with NSIS.

NSIS로 패키징한 미서명 오픈소스 Rust GPUI 데스크톱 앱 Kiloworks Onboarding v0.2.0의 오탐 의심 사례를 검토해 주세요.

Microsoft Defender Antivirus reports Trojan:Win32/Wacatac.B!ml and removes the x64 installer during browser download, before execution. The user reproduced this with both a Discord attachment and the official GitHub release asset.

Microsoft Defender Antivirus가 브라우저 다운로드 중 실행 전에 x64 설치파일을 Trojan:Win32/Wacatac.B!ml로 탐지하고 제거합니다. 사용자가 Discord 첨부파일과 공식 GitHub 릴리스 파일에서 모두 재현했습니다.

The application connects a device to Tailscale using an administrator-provided key and configures Microsoft OpenSSH, two administrator SSH public keys, and inbound TCP port 22 on all network profiles after explicit review and UAC consent. It uses elevated PowerShell for system configuration and verifies the publishers of downloaded Tailscale and Microsoft OpenSSH installers.

앱은 관리자가 제공한 키로 기기를 Tailscale에 연결하고, 명시적인 검토와 UAC 동의 후 Microsoft OpenSSH, 관리자 SSH 공개키 두 개와 모든 네트워크 프로필의 인바운드 TCP 22번 포트를 설정합니다. 시스템 설정에 관리자 PowerShell을 사용하며, 다운로드한 Tailscale과 Microsoft OpenSSH 설치파일의 발행자를 검증합니다.

Source: https://github.com/kiloworks/onboarding/tree/0c7da14f19209a156f66967d5138b026c962ddf2 . Please determine whether the submitted installer is incorrectly classified. We have not identified the specific component responsible for detection.

소스는 위 커밋에서 확인할 수 있습니다. 제출한 설치파일이 잘못 분류되었는지 확인해 주세요. 탐지를 유발한 구체적인 구성요소는 아직 식별하지 못했습니다.
