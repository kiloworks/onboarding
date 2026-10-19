param([ValidateSet('x64','arm64')][string]$Arch)
$ErrorActionPreference = 'Stop'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
$crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/$Arch/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (!$crt -or !(Test-Path (Join-Path $crt.FullName 'vcruntime140.dll'))) { throw "App-local MSVC CRT for $Arch is missing" }
Copy-Item (Join-Path $crt.FullName '*.dll') dist/
New-Item -ItemType Directory -Force dist/licenses | Out-Null
@'
Microsoft Visual C++ runtime redistributable components are included as app-local DLLs.
Copyright Microsoft Corporation. All rights reserved.
Redistribution and servicing information:
https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files
License terms: https://aka.ms/VCRedistLicense
'@ | Set-Content dist/licenses/Microsoft-CRT.txt -Encoding utf8
