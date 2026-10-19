$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$headers = @{ 'User-Agent' = 'Kiloworks-Onboarding'; Accept = 'application/vnd.github+json' }
function Download($url, $path) {
    Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -TimeoutSec 120 -OutFile $path
}
function Verify-Update($manifest, $signature, $installer, $publicKey, $version, $arch, $name) {
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    $rsa.PersistKeyInCsp = $false
    try {
        $rsa.FromXmlString($publicKey)
        if (!$rsa.VerifyData([IO.File]::ReadAllBytes($manifest), 'SHA256', [IO.File]::ReadAllBytes($signature))) { throw '업데이트 전자서명이 올바르지 않습니다.' }
    } finally { $rsa.Dispose() }
    $m = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($m.version -cne $version -or $m.arch -cne $arch -or $m.file -cne $name) { throw '업데이트 버전 또는 CPU 정보가 일치하지 않습니다.' }
    if ($m.sha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.sha256) { throw '업데이트 파일 해시가 일치하지 않습니다.' }
}
if ($Mode -eq 'check') {
    $releases = @()
    for ($page = 1; ; $page++) {
        $batch = @(Invoke-RestMethod -Uri "https://api.github.com/repos/kiloworks/onboarding/releases?per_page=100&page=$page" -Headers $headers -TimeoutSec 15)
        $releases += $batch
        if ($batch.Count -lt 100) { break }
    }
    ConvertTo-Json -InputObject @($releases | Where-Object { !$_.draft } | Select-Object tag_name, assets) -Depth 5 -Compress
} elseif ($Mode -eq 'prepare') {
    $base = "https://github.com/kiloworks/onboarding/releases/download/$Tag"
    $name = "onboarding-$Version-windows-$Arch-setup.exe"
    $installer = Join-Path $Directory $name
    Download "$base/$name.manifest.json" "$installer.manifest.json"
    Download "$base/$name.sig" "$installer.sig"
    Download "$base/$name" $installer
    Verify-Update "$installer.manifest.json" "$installer.sig" $installer $PublicKey $Version $Arch $name
    # Recheck the exact bytes immediately before launch; never trust a persisted verification flag.
    $helper = @'
$ErrorActionPreference = 'Stop'
try {
    $parent = Get-Process -Id $ParentId -ErrorAction SilentlyContinue
    if ($parent) { $parent.WaitForExit() }
    Verify-Update "$Installer.manifest.json" "$Installer.sig" $Installer $PublicKey $Version $Arch ([IO.Path]::GetFileName($Installer))
    $p = Start-Process -FilePath $Installer -ArgumentList @('/S', "/D=$InstallDir") -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "설치 실패: $($p.ExitCode)" }
    Start-Process -FilePath (Join-Path $InstallDir 'onboarding.exe')
} catch {
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show("업데이트 실패. 기존 앱을 다시 실행하거나 설치 파일로 복구해 주세요.`n$($_.Exception.Message)", 'Onboarding 업데이트') | Out-Null
} finally {
    Remove-Item -LiteralPath $Directory -Recurse -Force -ErrorAction SilentlyContinue
}
'@
    $verify = ${function:Verify-Update}.ToString()
    function Literal($s) { "'" + $s.Replace("'", "''") + "'" }
    $prefix = "function Verify-Update { $verify }; "
    foreach ($pair in @(@('Installer',$installer), @('PublicKey',$PublicKey), @('Version',$Version), @('Arch',$Arch), @('InstallDir',$InstallDir), @('Directory',$Directory))) {
        $prefix += '$' + $pair[0] + '=' + (Literal $pair[1]) + ';'
    }
    $prefix += '$ParentId=' + $ParentId + ';'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix + $helper))
    $process = Start-Process "$PSHOME\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-EncodedCommand',$encoded) -PassThru
    if ($process.HasExited) { throw '업데이트 설치 도우미를 시작할 수 없습니다.' }
} else { throw 'Unknown update mode' }
