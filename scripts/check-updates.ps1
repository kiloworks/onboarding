param([string]$Installer, [string]$InstallDir, [string]$Arch)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($file in @('src/update.ps1','scripts/sign-updates.ps1')) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText((Join-Path $root $file), [Text.Encoding]::UTF8), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    if ($file -eq 'src/update.ps1') {
        $fn = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Verify-Update' }, $false)[0]
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.PersistKeyInCsp = $false
try {
    New-Item -ItemType Directory -Path "$temp/config", "$temp/release" | Out-Null
    $public = $rsa.ToXmlString($false)
    [IO.File]::WriteAllText("$temp/config/update-public-key.xml", $public)
    foreach ($fixtureArch in @('x64','arm64')) { [IO.File]::WriteAllText("$temp/release/onboarding-0.4.0-windows-$fixtureArch-setup.exe", 'fixture installer') }
    $env:ONBOARDING_UPDATE_PRIVATE_KEY = $rsa.ToXmlString($true)
    Push-Location $temp
    try { & "$root/scripts/sign-updates.ps1" -Version '0.4.0' } finally { Pop-Location }
    $name = 'onboarding-0.4.0-windows-x64-setup.exe'
    $path = "$temp/release/$name"
    Verify-Update "$path.manifest.json" "$path.sig" $path $public '0.4.0' 'x64' $name
    function Must-Fail($test) {
        $failed = $false
        try { & $test } catch { $failed = $true }
        if (!$failed) { throw 'Untrusted update was accepted' }
    }
    Must-Fail { Verify-Update "$path.manifest.json" "$path.sig" $path $public '0.5.0' 'x64' $name }
    Must-Fail { Verify-Update "$path.manifest.json" "$path.sig" $path $public '0.4.0' 'arm64' $name }
    [IO.File]::AppendAllText($path, 'tampered')
    Must-Fail { Verify-Update "$path.manifest.json" "$path.sig" $path $public '0.4.0' 'x64' $name }
    [IO.File]::AppendAllText("$path.manifest.json", ' ')
    Must-Fail { Verify-Update "$path.manifest.json" "$path.sig" $path $public '0.4.0' 'x64' $name }
    Write-Host 'Update signing round-trip, payload/manifest tampering, version and architecture binding: PASS'
    if ($Installer) {
        $Version = ((Select-String -Path "$root/Cargo.toml" -Pattern '^version = "([^"]+)"').Matches[0].Groups[1].Value)
        $Tag = "v$Version"
        $name = "onboarding-$Version-windows-$Arch-setup.exe"
        $source = Join-Path $temp $name
        Copy-Item -LiteralPath $Installer -Destination $source
        $manifest = @{version=$Version; arch=$Arch; file=$name; sha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()} | ConvertTo-Json -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($manifest)
        [IO.File]::WriteAllBytes("$source.manifest.json", $bytes)
        [IO.File]::WriteAllBytes("$source.sig", $rsa.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1))
        # Replace only transport with local fixtures; use the production verifier and detached install helper.
        function Invoke-WebRequest {
            param($Uri, $Headers, $TimeoutSec, $OutFile, [switch]$UseBasicParsing)
            Copy-Item -LiteralPath (Join-Path $temp ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))) -Destination $OutFile
        }
        $Mode = 'prepare'
        $Directory = Join-Path $temp 'download'
        New-Item -ItemType Directory -Path $Directory | Out-Null
        $PublicKey = $public
        $app = Start-Process (Join-Path $InstallDir 'onboarding.exe') -ArgumentList '--smoke-gui' -PassThru
        $ParentId = $app.Id
        $replacement = $null
        $helperLog = Join-Path $env:LOCALAPPDATA 'Kiloworks/Onboarding/update.log'
        Remove-Item -LiteralPath $helperLog -ErrorAction SilentlyContinue
        try {
            . "$root/src/update.ps1"
            $deadline = [DateTime]::UtcNow.AddSeconds(90)
            do {
                $replacement = Get-Process onboarding -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $app.Id -and $_.Path -eq (Join-Path $InstallDir 'onboarding.exe') } | Select-Object -First 1
                if ($replacement) { $replacement.Refresh(); if ($replacement.MainWindowHandle -ne 0) { break } }
                if (Test-Path -LiteralPath $helperLog) { break }
                Start-Sleep -Milliseconds 200
            } while ([DateTime]::UtcNow -lt $deadline)
            if (!$replacement -or $replacement.MainWindowHandle -eq 0) {
                $app.Refresh()
                $log = Get-Content -LiteralPath $helperLog -Raw -ErrorAction SilentlyContinue
                throw "Updated app did not restart with a native window. Original exited: $($app.HasExited). Helper: $log"
            }
            $app.Refresh()
            if (!$app.HasExited) { throw 'Installer did not wait for the original app to exit' }
            if ((Get-Content (Join-Path $InstallDir 'user-data.txt') -Raw).Trim() -ne 'preserve user data') { throw 'Update lost user data' }
            if (!(Test-Path (Join-Path $InstallDir 'licenses/LICENSE-INDEX.json'))) { throw 'Update lost license files' }
            Write-Host 'Signed update download, app exit, NSIS replacement, restart and data preservation: PASS'
        } finally {
            if ($replacement -and !$replacement.HasExited) { Stop-Process -Id $replacement.Id -Force }
            if (!$app.HasExited) { Stop-Process -Id $app.Id -Force }
        }
    }

} finally {
    $rsa.Dispose()
    Remove-Item Env:ONBOARDING_UPDATE_PRIVATE_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
