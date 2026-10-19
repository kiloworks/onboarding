# Third-party software

Onboarding uses Rust GPUI and platform crates from the Zed project, Apache-2.0,
commit 2565b8a3e33537c3d3f56d0d45f11e50a17e512d:
https://github.com/zed-industries/zed/tree/2565b8a3e33537c3d3f56d0d45f11e50a17e512d
Copyright the Zed contributors.
The native text input is adapted from GPUI's Apache-2.0 input example.

Cargo dependencies and their upstream notices are collected by scripts/licenses.py.
Byte-identical notices are stored once; licenses/LICENSE-INDEX.json maps each
component's original notice path to its retained plaintext file.
Bun, JavaScriptCore, React and GPUIX bindings are no longer included as of v0.2.0.

Microsoft Visual C++ redistributable CRT DLLs are included app-locally under
Microsoft redistribution terms. See licenses/Microsoft-CRT.txt.

Pretendard Regular and SemiBold 1.3.9, Copyright Kil Hyung-jin and the upstream
font authors, are distributed unmodified under SIL OFL 1.1.
See licenses/Pretendard-OFL.txt and https://github.com/orioncactus/pretendard.

Tailscale and Microsoft OpenSSH are separately installed from official
sources and are not redistributed in the Onboarding installer.
