# 네이티브 앱 재빌드

v0.2.0부터 Rust GPUI를 직접 사용합니다. Bun·JavaScriptCore·React·GPUIX 바인딩은 포함하지 않습니다.

GPUI 소스는 https://github.com/zed-industries/zed/tree/2565b8a3e33537c3d3f56d0d45f11e50a17e512d 이며 Apache-2.0입니다. Cargo.toml의 정확한 git revision과 Cargo.lock으로 의존성을 고정합니다.

Rust 1.98.1과 Windows SDK/Visual Studio C++ Build Tools로 `cargo test --locked --release`, `cargo build --locked --release`를 실행합니다. ARM64 빌드는 ARM64 MSVC·Clang이 필요합니다. 전체 빌드·패키징 경로는 `.github/workflows/ci.yml`입니다. 자체 수정과 재빌드를 제한하지 않습니다.

macOS에서 개발용 UI를 실행할 때는 runtime_shaders를 사용합니다. 설치·상태 확인 기능은 Windows 전용이며 macOS 지원 릴리스를 뜻하지 않습니다.
