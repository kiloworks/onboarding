# Windows를 첫 배포 대상으로 한다

2026-10-19 magneto 결정: 기존 Windows 설치 흐름을 활용하여 Windows용 GPUIX 앱의 Tailscale 연결과 SSH 원격 관리 준비를 최우선으로 완성한다. macOS와 Linux는 후속 플랫폼 티켓으로 추적하며 첫 Windows 배포의 선행 조건으로 삼지 않는다.

실제 클라이언트 지원 대상은 Windows 10/11이며 x64와 ARM64를 첫 출시부터 지원한다. Windows 10을 최소 OS 제품군으로 보고 특정 기능 업데이트 버전으로 임의 제한하지 않는다. GPUIX·런타임·OS 기능의 실제 제약을 조사하고 요구사항과 충돌하면 알린다. GHA 검증 매트릭스에는 windows-2022, windows-2025, windows-11-arm을 모두 포함하고 ARM64는 native 배포·실행을 검증한다. 기존 macOS 패키지 흐름은 재사용 후보이며, Linux 설치 흐름은 별도 조사·구현이 필요하다.
