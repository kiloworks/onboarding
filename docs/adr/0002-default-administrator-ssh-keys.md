# 기본 관리자 SSH 공개키 두 개를 배포한다

2026-10-19 magneto가 제공한 두 개의 보안키 기반 ECDSA SSH 공개키를 `config/administrators_authorized_keys`에 기록하고 앱의 기본 관리자 접근 키로 사용한다. 설치 사용자는 SSH 키를 따로 입력하지 않고 Tailscale 등록 키만 입력한다.

설치 시 기존 authorized_keys를 보존하면서 두 공개키를 중복 없이 추가한다. 개인키는 포함하지 않는다. 두 키가 기본 등록된 모든 대상 기기에 접근할 수 있으므로 키 교체·폐기 시 기존 기기도 별도 갱신해야 한다. 보안키 기반 서명의 대상 OS OpenSSH 호환성은 실제 설치 검증에 포함한다.
