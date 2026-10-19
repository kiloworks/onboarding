# E2E는 GitHub OIDC와 Tailscale Workload Identity Federation을 사용한다

2026-10-19 magneto 결정: 공개 저장소의 실제 연결 E2E는 GitHub OIDC를 Tailscale Workload Identity Federation으로 직접 교환한다. 장기 OAuth client secret이나 사용자 API 토큰을 GHA에 저장하지 않고, 외부 자체 키 발급 서비스도 추가하지 않는다. 테스트 기기는 `tag:gha`로 등록하고 종료 시 제거한다.

## 구현 조건

- Tailscale 신뢰 설정은 실제 저장소, 보호된 실행 ref 또는 environment 및 필요한 workflow claim으로 한정한다. 환경을 사용하면 OIDC subject 형태가 달라짐을 반영한다. 포크·PR·임의 ref는 허용하지 않는다.
- `id-token: write`는 실제 연결 테스트 job에만 부여한다. Client ID와 audience는 비밀이 아니며, OIDC JWT와 교환된 단기 토큰·auth key는 비밀로 취급한다.
- 최소 범위의 단기 API 토큰으로 `tag:gha`를 가진 일회용·사전 승인·ephemeral auth key를 각 매트릭스 작업마다 생성한다. 앱은 일반 사용자와 동일한 키 입력 흐름으로 이 키를 사용한다.
- 공식 Tailscale Action을 사용해 앱 설치 전에 테스트 대상 러너의 Tailscale을 미리 설치·등록해 버리면 신규 설치 E2E가 무력화된다. 토큰 교환·키 발급과 테스트 대상 앱 설치를 분리한다. 별도 접속 검증용 peer에 Action을 사용하는 것은 가능하다.
- tag:gha의 접근 범위는 테스트 통신에 필요한 최소한으로 제한한다. 일반 운영 자원에 대한 접근은 열지 않는다. 전용 테스트 tailnet 사용 여부는 실제 환경에 맞춰 결정한다.
- 실패 시에도 always 정리에서 생성된 노드를 logout하여 ephemeral 노드 제거를 유도하고 제거 결과를 확인한다. 명시적인 API 삭제가 필요하면 실제 최소 scope와 대상 제한을 확인하며, 이번 실행에서 생성한 기기 ID만 삭제한다. 태그 전체 일괄 삭제는 금지한다.
- 각 작업에 run ID·attempt·matrix를 포함한 고유 기기 이름과 생성 기기 ID를 기록한다. JWT·토큰·키 원문은 기록하지 않는다. 강제 취소·러너 소실 시 always가 실행되지 않을 수 있으므로 ephemeral 잔존 정리 동작과 탐지·수동 정리 절차도 문서화한다.
- 공개 로그·UI 테스트 캡처·아티팩트에 단기 비밀이 유출되지 않게 한다. 토큰 요청부터 마스킹하며 민감 UI 캡처를 제외하거나 안전하게 가린다. OIDC는 악성 실행 코드에 대한 비밀 보호 장치가 아니므로 검토된 코드만 신뢰한다.

태그 기반 자동 E2E는 실제 운영의 사용자 소유 등록을 증명하지 않는다. 후자는 Keyport에서 발급한 실제 키를 이용한 별도 승인된 검증으로 남긴다.

## 공식 자료

- https://tailscale.com/docs/features/workload-identity-federation
- https://tailscale.com/docs/integrations/github/github-action
- https://github.com/tailscale/github-action

## 실제 WIF 설정 반영

2026-10-19 실제 credential이 허용한 태그는 `tag:gha-smoke-test-node`로 확인되어, 처음 제안한 `tag:gha` 대신 이 테스트 전용 태그를 사용한다. 기존 credential scope와 운영 ACL을 넓히지 않는다. GitHub의 실제 subject는 `repo:kiloworks@265963833/onboarding@1425032376:ref:refs/heads/main`으로 관찰되어 그 값에 정확히 제한한다.
