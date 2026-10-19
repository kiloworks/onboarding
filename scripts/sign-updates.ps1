param([Parameter(Mandatory)][string]$Version, [string]$Directory = 'release')
$ErrorActionPreference = 'Stop'
$Directory = (Resolve-Path -LiteralPath $Directory).Path
if (!$env:ONBOARDING_UPDATE_PRIVATE_KEY) { throw 'ONBOARDING_UPDATE_PRIVATE_KEY secret is required' }
$rsa = [Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString($env:ONBOARDING_UPDATE_PRIVATE_KEY)
    $public = Get-Content config/update-public-key.xml -Raw
    $probe = [Text.Encoding]::UTF8.GetBytes('onboarding-update-key-check')
    $signature = $rsa.SignData($probe, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $verifier = [Security.Cryptography.RSA]::Create()
    try {
        $verifier.FromXmlString($public)
        if (!$verifier.VerifyData($probe, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)) { throw 'Signing key does not match embedded public key' }
    } finally { $verifier.Dispose() }
    foreach ($arch in @('x64','arm64')) {
        $name = "onboarding-$Version-windows-$arch-setup.exe"
        $path = Join-Path $Directory $name
        $manifest = @{ version=$Version; arch=$arch; file=$name; sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() } | ConvertTo-Json -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($manifest)
        [IO.File]::WriteAllBytes("$path.manifest.json", $bytes)
        [IO.File]::WriteAllBytes("$path.sig", $rsa.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1))
    }
} finally { $rsa.Dispose(); Remove-Item Env:ONBOARDING_UPDATE_PRIVATE_KEY }
