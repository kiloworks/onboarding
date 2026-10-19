# Windows 패키지 용량

v0.1.0 릴리스 설치 파일을 압축 해제해 측정한 기준값입니다. MiB는 1,048,576바이트입니다.

| 구성 | x64 | ARM64 |
| --- | ---: | ---: |
| 설치 파일 | 39.9 MiB | 34.5 MiB |
| 압축 해제 payload 합계 | 약 127.7 MiB | 약 114.9 MiB |
| onboarding.exe | 92.3 MiB | 79.8 MiB |
| GPUIX renderer | 21.9 MiB | 19.4 MiB |
| 라이선스 원문 | 11.5 MiB | 11.5 MiB |

payload는 실제 NTFS 할당 용량과 같지 않으며, 별도로 설치하는 Tailscale·OpenSSH의 용량을 포함하지 않습니다.

v0.1.x 실행 파일에는 Bun·JavaScriptCore가 포함됩니다. 앱 코드를 minify해도 런타임 대부분은 남습니다. GPUIX는 Chromium이나 WebView를 포함하지 않지만, JS 런타임과 네이티브 렌더러는 필요합니다. Hermes upstream은 Windows를 지원하지 않으므로 v0.2.0에서는 Rust GPUI 직접 링크를 선택했습니다.

v0.1.1부터 동일한 라이선스 원문을 바이트 단위로 중복 제거하고 구성요소 참조를 색인에 보존합니다. 기존 1,139개 원문 전체의 참조 결과가 이전 원문과 동일한지 확인했으며, 라이선스 자체는 약 1.2 MiB로 줄어듭니다. Pretendard는 전체 가변 폰트 대신 원본 Regular·SemiBold 두 파일 약 3 MiB를 포함합니다.

CI artifact의 `artifacts/size.json`에 빌드별 payload·실행 파일·renderer·라이선스 바이트 수를 기록합니다. 압축 크기 개선을 위해 실행 파일 패커를 추가하거나 사용자 PC에서 런타임을 추가 다운로드하지 않습니다.

## v0.2.0 Rust GPUI 전환

Bun·JavaScriptCore·React와 별도 `.node` 렌더러를 제거하고 GPUI를 Rust 실행파일에 직접 링크합니다. GPUI 소스 revision은 이전 바인딩과 동일합니다. 배포 패키지에는 앱과 MSVC CRT·라이선스만 포함합니다. 실제 수치는 새 Windows CI의 size.json과 릴리스 설치파일로 측정합니다.

v0.1.1 기준 x64는 실행파일 95.35 MiB, renderer 21.97 MiB, payload 120.29 MiB, 설치파일 약 41.3 MiB입니다. ARM64는 실행파일 82.83 MiB, renderer 19.44 MiB, payload 107.60 MiB, 설치파일 약 35.9 MiB입니다.
