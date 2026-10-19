# GitHub OIDC / Tailscale WIF 설정

장기 Tailscale OAuth secret이나 사용자 API 토큰은 GHA에 등록하지 않습니다.

## Tailscale 설정

1. 테스트할 tailnet의 [Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials)를 엽니다.
2. tag:gha를 정의하고 테스트 통신에 필요한 최소 접근만 허용합니다. 운영 자원 접근을 허용하지 않습니다. 기존 ACL의 광범위한 기본 허용도 확인합니다.
3. Credential → OpenID Connect를 선택합니다.
4. GitHub Actions issuer를 선택하거나 Custom issuer에 `https://token.actions.githubusercontent.com`을 입력합니다.
5. Subject를 `repo:kiloworks/onboarding:ref:refs/heads/main`으로 제한합니다.
6. 가능하면 custom claim `workflow_ref`를 `kiloworks/onboarding/.github/workflows/e2e.yml@refs/heads/main`으로 제한합니다. 포크·PR·다른 ref는 허용하지 않습니다.
7. Auth Keys 쓰기와 tag:gha만 허용합니다.
8. 생성된 Client ID와 Audience를 복사합니다. 두 값은 비밀이 아닌 식별자이며 client secret은 필요하지 않습니다.

## GitHub 설정

저장소 Actions variables에 `TS_WIF_CLIENT_ID`, `TS_WIF_AUDIENCE`를 설정합니다. 장기 secret을 추가하지 않습니다. main과 워크플로 변경 권한을 보호합니다. 환경 기반 보호를 추가한다면 OIDC sub 형태도 함께 바뀌므로 Tailscale 신뢰 설정을 일치시킵니다.

성공한 Windows CI 실행 ID를 입력으로 `Windows OIDC E2E`를 main에서 실행합니다. 코드 SHA와 CI 산출물 SHA가 같아야 합니다. 각 러너는 서로 다른 일회용·사전 승인·ephemeral 키를 발급받고 앱 자체의 입력 흐름으로 등록합니다. 새 설치 검증 전에 Tailscale Action으로 설치·연결하지 않습니다.

## 정리 및 예외

일반 종료·실패에는 로그아웃하여 ephemeral 노드 제거를 유도하고 미사용 auth key를 폐기합니다. GHA 강제 종료·러너 소실 시 cleanup이 실행되지 않을 수 있습니다. run ID와 러너 이름으로 테스트 기기 잔존 여부를 Tailscale 콘솔에서 확인하고 필요하면 해당 기기만 수동 삭제합니다. tag:gha 기기를 일괄 삭제하지 않습니다.

태그 기반 자동 검증은 사용자 소유 기기 등록을 증명하지 않습니다. Keyport에서 발급한 실제 사용자 소유 키와 하드웨어 SSH 보안키는 별도 승인된 실기 검증에 사용합니다. 키·JWT·단기 토큰은 테스트 로그나 스크린샷에 넣지 않습니다.

참고: https://tailscale.com/docs/features/workload-identity-federation
