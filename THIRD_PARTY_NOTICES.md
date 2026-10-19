# Third-party software

Onboarding uses GPUIX (@gpuix/react and @gpuix/native 0.10.0), Apache-2.0,
Copyright the GPUIX contributors: https://github.com/remorses/gpuix.
The ARM64 binding is built from commit 515df198fef2685f5ed7dd120bf0db638eb5c360.
GPUIX includes GPUI from the Zed project and other Rust dependencies.

React is MIT licensed, Copyright Meta Platforms, Inc. and affiliates.
Bun is MIT licensed and embeds JavaScriptCore, whose notices and applicable
licenses are distributed in THIRD_PARTY_LICENSES.txt by Bun:
https://github.com/oven-sh/bun/blob/main/LICENSE.md.

The release package includes a licenses directory with upstream runtime and
native dependency licenses. See scripts/licenses.ts for the reproducible
license collection. Tailscale and Microsoft OpenSSH are separate software
installed using their official distribution mechanisms; they are not
redistributed in the Onboarding installer.

Microsoft Visual C++ redistributable CRT DLLs are included app-locally under
Microsoft redistribution terms. See licenses/Microsoft-CRT.txt.
