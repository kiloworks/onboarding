# 런타임 소스와 재빌드

이 앱 소스는 https://github.com/kiloworks/onboarding 에 MIT로 공개됩니다. 실행 파일에 암호화되거나 비공개인 앱 소스는 없습니다. 사용자 수정과 재빌드를 허용합니다.

Bun 1.4.3 소스와 포함 라이브러리 정보:
https://github.com/oven-sh/bun/tree/bun-v1.4.3
https://github.com/oven-sh/bun/blob/bun-v1.4.3/LICENSE.md

JavaScriptCore/WebKit 소스:
https://github.com/oven-sh/WebKit

Bun의 공식 LICENSE.md에 설명된 절차로 해당 Bun 버전이 지정한 WebKit을 가져와 수정·빌드할 수 있습니다. 수정한 Bun으로 이 저장소의 `bun install`, `bun run dev` 또는 `bun run build`를 실행하여 앱을 재빌드할 수 있습니다. 원래 Windows 빌드는 Bun 1.4.3을 사용합니다. 필요한 개발 환경은 Bun의 해당 버전 빌드 문서를 따릅니다.

GPUIX 0.10.0은 Apache-2.0입니다. ARM64 native binding은 아래 고정 소스 및 그 소스가 지정한 zed submodule에서 빌드됩니다.
https://github.com/remorses/gpuix/tree/515df198fef2685f5ed7dd120bf0db638eb5c360

native-arm.yml은 해당 renderer 빌드 과정을 제공합니다. 사용자 지정 renderer도 대응하는 앱 빌드와 함께 사용할 수 있습니다. 라이브러리 자체의 재빌드를 금지하는 별도 이용 제한은 두지 않습니다.
