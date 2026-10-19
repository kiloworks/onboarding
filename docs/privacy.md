# 개인정보 안내

Kiloworks Onboarding에는 별도 분석 텔레메트리나 자동 지원 리포트 전송 기능이 없습니다. 사용자가 요청한 설치·업데이트와 Tailscale 연결 과정에서는 해당 서비스로 네트워크 요청을 보냅니다.

- 소프트웨어 조회·다운로드에는 Tailscale 및 Microsoft/GitHub 배포 서버가 사용됩니다. 서버에는 요청 IP와 일반적인 다운로드 요청 정보가 전달될 수 있습니다. [Tailscale 개인정보 정책](https://tailscale.com/privacy-policy), [Microsoft 개인정보처리방침](https://privacy.microsoft.com/privacystatement), [GitHub 개인정보처리방침](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)이 각 서비스에 적용됩니다.
- 입력한 Tailscale 등록 키는 기기 연결에 사용합니다. 앱이 키 원문을 파일·로그·프로세스 명령줄에 저장하지 않습니다. 설치한 Tailscale의 기기 상태·인증 정보 보관은 Tailscale 자체 동작과 정책을 따릅니다.
- 기기 상태 표시와 SSH 설정을 위해 Windows 사용자 계정·SID·Tailscale 네트워크와 IP를 로컬에서 조회합니다. 지정된 관리자 공개키를 등록하며 개인키를 수집하지 않습니다.
- 로컬 설치 로그와 복사 가능한 지원 리포트에는 사용자 계정명·네트워크 주소 등이 포함될 수 있습니다. 리포트는 자동 전송되지 않습니다. 사용자가 복사해 전달할 때 개인정보가 포함될 수 있음을 확인해야 합니다.
- 앱 제거 후에도 설치된 Tailscale, SSH 서비스·키·방화벽 설정과 지원 로그가 남을 수 있습니다. 원격 관리 해제와 로그 위치는 [운영 문서](operations.md)를 참고하세요.

프로젝트 문의는 [GitHub Issues](https://github.com/kiloworks/onboarding/issues)를 사용하세요. 등록 키, 개인키 또는 개인정보가 담긴 원본 로그를 공개 이슈에 올리지 마세요.
