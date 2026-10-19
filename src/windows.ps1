$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$client = New-Object Net.Sockets.TcpClient
$client.Connect('127.0.0.1', $Port)
$stream = $client.GetStream()
$reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false)))
$writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($false)))
$writer.AutoFlush = $true
$writer.WriteLine($Nonce)
$config = $reader.ReadLine() | ConvertFrom-Json
$key = [string]$config.key
$config.key = $null
$stage = 'prepare'
$reboot = $false

function Send([string]$Message, [bool]$Done = $false, [bool]$Ok = $false, [string]$Report = '') {
  $writer.WriteLine((@{ stage = $script:stage; message = $Message; done = $Done; ok = $Ok; report = $Report } | ConvertTo-Json -Compress))
}
function Retry([scriptblock]$Work) {
  try { & $Work } catch {
    Send '잠시 후 한 번 더 시도합니다. 이미 완료된 설정은 유지합니다.'
    Start-Sleep -Seconds 3
    & $Work
  }
}
function Run-Process([string]$File, [string[]]$Arguments, [int]$Timeout = 180) {
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $File
  $info.Arguments = ($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $p = New-Object Diagnostics.Process
  $p.StartInfo = $info
  [void]$p.Start()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  if (!$p.WaitForExit($Timeout * 1000)) { try { $p.Kill() } catch {}; throw 'command timeout' }
  $output = $outTask.Result
  [void]$errTask.Result
  if ($p.ExitCode -ne 0) { throw "command exit $($p.ExitCode)" }
  return $output
}
function Status {
  if (!(Test-Path $script:ts)) { return $null }
  try { return ((& $script:ts status --json 2>$null | Out-String) | ConvertFrom-Json) } catch { return $null }
}
function Update-Tailscale {
  Send 'Tailscale 최신 버전을 확인합니다. 다운로드와 업데이트 중에도 창을 유지해 주세요.'
  $meta = Invoke-RestMethod 'https://pkgs.tailscale.com/stable/?mode=json' -TimeoutSec 60
  $latest = [string]$meta.MSIsVersion
  if ($latest -notmatch '^\d+\.\d+\.\d+$') { throw 'invalid package version' }
  if (Test-Path $script:ts) {
    $current = (& $script:ts version 2>$null | Select-Object -First 1).Trim()
    if ($current -match '^(\d+\.\d+\.\d+)') {
      if ([version]$Matches[1] -ge [version]$latest) { Send 'Tailscale이 최신 상태입니다. 다운로드를 생략합니다.'; return }
    }
  }
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'amd64' }
  $name = [string]$meta.MSIs.$arch
  if ($name -notmatch '^tailscale-setup-[0-9.]+-(amd64|arm64)\.msi$') { throw 'invalid installer name' }
  $dir = Join-Path $env:ProgramData ('Onboarding-install-' + [Guid]::NewGuid().ToString('N'))
  # Only Administrators and SYSTEM may replace an installer that will run elevated.
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($sid in @('S-1-5-32-544', 'S-1-5-18')) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
  }
  [void][IO.Directory]::CreateDirectory($dir, $acl)
  try {
    $msi = Join-Path $dir 'tailscale.msi'
    Send '공식 Tailscale 설치 파일을 내려받고 서명을 확인합니다.'
    Invoke-WebRequest ('https://pkgs.tailscale.com/stable/' + $name) -OutFile $msi -UseBasicParsing -TimeoutSec 300
    $signature = Get-AuthenticodeSignature $msi
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Tailscale Inc\.?[, ]') { throw 'installer signature verification failed' }
    Send 'Tailscale을 설치 또는 업데이트합니다. 잠시 기다려 주세요.'
    $p = Start-Process (Join-Path $env:WINDIR 'System32/msiexec.exe') -ArgumentList @('/i', ('"' + $msi + '"'), '/qn', '/norestart', 'TS_NOLAUNCH=1', 'TS_ONBOARDING_FLOW=hide') -Wait -PassThru
    if ($p.ExitCode -eq 3010) { $script:reboot = $true }
    elseif ($p.ExitCode -ne 0) { throw "MSI exit $($p.ExitCode)" }
    if (!(Test-Path $script:ts)) { throw 'Tailscale CLI is missing after installation' }
  } finally { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
}
function Connect-Tailscale {
  $s = Status
  if ($s -and $s.BackendState -eq 'Running') { Send '현재 네트워크 연결이 정상입니다. 키를 다시 사용하지 않습니다.'; return }
  if ($script:key -notmatch '^tskey-auth-[A-Za-z0-9_-]{10,}$') { throw 'a new auth key is required' }
  Send '전달받은 일회용 키로 네트워크에 연결합니다.'
  $pipeName = 'onboarding-key-' + [Guid]::NewGuid().ToString('N')
  $security = New-Object IO.Pipes.PipeSecurity
  foreach ($sid in @('S-1-5-32-544', 'S-1-5-18')) {
    $security.AddAccessRule((New-Object IO.Pipes.PipeAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
  }
  $pipe = New-Object IO.Pipes.NamedPipeServerStream($pipeName, [IO.Pipes.PipeDirection]::Out, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous, 4096, 4096, $security)
  try {
    $wait = $pipe.WaitForConnectionAsync()
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:ts
    $info.Arguments = 'up --auth-key=file:\\.\pipe\' + $pipeName + ' --reset --accept-routes=false --unattended --timeout=90s'
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $p = New-Object Diagnostics.Process; $p.StartInfo = $info
    [void]$p.Start()
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (!$wait.Wait(30000)) { try { $p.Kill() } catch {}; throw 'auth key pipe timeout' }
    $bytes = [Text.Encoding]::UTF8.GetBytes($script:key)
    $pipe.Write($bytes, 0, $bytes.Length); $pipe.Flush(); $pipe.Dispose()
    [Array]::Clear($bytes, 0, $bytes.Length)
    if (!$p.WaitForExit(120000)) { try { $p.Kill() } catch {}; throw 'network registration timeout' }
    [void]$out.Result; [void]$err.Result
    if ($p.ExitCode -ne 0) { throw 'registration rejected; key may be expired or consumed' }
  } finally { $pipe.Dispose() }
  $s = Status
  if (!$s -or $s.BackendState -ne 'Running') { throw 'Tailscale is not connected' }
  $script:key = ''
}
function SSH-ServerPath {
  foreach ($candidate in @((Join-Path $env:ProgramFiles 'OpenSSH/sshd.exe'), (Join-Path $env:WINDIR 'System32/OpenSSH/sshd.exe'))) {
    if (Test-Path $candidate) { return $candidate }
  }
  throw 'OpenSSH Server is missing'
}
function Upgrade-OpenSSH {
  Send '기본 보안키를 지원하는 Microsoft OpenSSH 서버로 업데이트합니다.'
  $release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' -Headers @{ 'User-Agent' = 'kiloworks-onboarding' } -TimeoutSec 60
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'ARM64' } else { 'Win64' }
  $asset = @($release.assets | Where-Object { $_.name -match ('^OpenSSH-' + $arch + '-v[0-9.]+\.msi$') }) | Select-Object -First 1
  if (!$asset -or $asset.browser_download_url -notmatch '^https://github\.com/PowerShell/Win32-OpenSSH/releases/download/') { throw 'official OpenSSH package is unavailable' }
  $dir = Join-Path $env:ProgramData ('Onboarding-ssh-' + [Guid]::NewGuid().ToString('N'))
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($sid in @('S-1-5-32-544', 'S-1-5-18')) {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
  }
  [void][IO.Directory]::CreateDirectory($dir, $acl)
  try {
    $msi = Join-Path $dir 'openssh.msi'
    Invoke-WebRequest $asset.browser_download_url -OutFile $msi -UseBasicParsing -TimeoutSec 300
    $signature = Get-AuthenticodeSignature $msi
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation[, ]') { throw 'Microsoft OpenSSH installer signature verification failed' }
    $p = Start-Process (Join-Path $env:WINDIR 'System32/msiexec.exe') -ArgumentList @('/i', ('"' + $msi + '"'), 'ADDLOCAL=Server', '/qn', '/norestart') -Wait -PassThru
    if ($p.ExitCode -eq 3010) { $script:reboot = $true }
    elseif ($p.ExitCode -ne 0) { throw "OpenSSH MSI exit $($p.ExitCode)" }
  } finally { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
}
function Install-SSH {
  Send 'Windows OpenSSH 서버를 준비합니다. Windows 기능 설치는 몇 분이 걸릴 수 있습니다.'
  $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
  if (!$cap) { throw 'OpenSSH Server capability is unavailable' }
  if ($cap.State -ne 'Installed') {
    $result = Add-WindowsCapability -Online -Name $cap.Name
    if ($result.RestartNeeded) { $script:reboot = $true }
  }
  $userSid = New-Object Security.Principal.SecurityIdentifier([string]$config.sid)
  $account = $userSid.Translate([Security.Principal.NTAccount]).Value
  $local = Get-LocalUser -SID $userSid
  if (!$local -or !$local.Enabled) { throw 'enabled local Windows user required' }
  $isAdmin = @(Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.SID.Value -eq $userSid.Value }).Count -gt 0
  if ($isAdmin) {
    $authFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
  } else {
    $profile = (Get-ItemProperty ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $userSid.Value)).ProfileImagePath
    if (!$profile -or !(Test-Path $profile)) { throw 'Windows user profile is unavailable' }
    $sshDir = Join-Path $profile '.ssh'
    if (Test-Path $sshDir) { if ((Get-Item $sshDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'SSH directory cannot be a link' } }
    New-Item -ItemType Directory -Force $sshDir | Out-Null
    $authFile = Join-Path $sshDir 'authorized_keys'
  }
  if (Test-Path $authFile) { if ((Get-Item $authFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'authorized_keys cannot be a link' } }
  New-Item -ItemType Directory -Force (Split-Path $authFile) | Out-Null
  if (!(Test-Path $authFile)) { New-Item -ItemType File $authFile | Out-Null }
  $existing = @(Get-Content $authFile)
  foreach ($pub in $config.keys) {
    if ($pub -notmatch '^sk-ecdsa-sha2-nistp256@openssh.com [A-Za-z0-9+/=]+(?: .*)?$') { throw 'invalid embedded SSH key' }
    if ($existing -notcontains $pub) { Add-Content -Path $authFile -Value $pub -Encoding ascii; $existing += $pub }
  }
  $acl = New-Object Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($sid in @('S-1-5-32-544', 'S-1-5-18')) {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
  }
  if (!$isAdmin) { $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($userSid, 'FullControl', 'Allow'))); $acl.SetOwner($userSid) }
  else { $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544'))) }
  Set-Acl $authFile $acl
  Start-Service sshd
  $sshd = SSH-ServerPath
  $keygen = Join-Path (Split-Path $sshd) 'ssh-keygen.exe'
  [void](Run-Process $keygen @('-A'))
  # Refuse an incompatible/existing sshd configuration instead of rewriting its policy.
  [void](Run-Process $sshd @('-t'))
  $effective = Run-Process $sshd @('-T', '-C', ('user=' + $local.Name + ',host=localhost,addr=127.0.0.1'))
  if ($effective -notmatch 'pubkeyaccepted(algorithms|keytypes) .*sk-ecdsa-sha2-nistp256@openssh.com') {
    Upgrade-OpenSSH
    $sshd = SSH-ServerPath
    [void](Run-Process (Join-Path (Split-Path $sshd) 'ssh-keygen.exe') @('-A'))
    [void](Run-Process $sshd @('-t'))
    $effective = Run-Process $sshd @('-T', '-C', ('user=' + $local.Name + ',host=localhost,addr=127.0.0.1'))
    if ($effective -notmatch 'pubkeyaccepted(algorithms|keytypes) .*sk-ecdsa-sha2-nistp256@openssh.com') { throw 'OpenSSH does not accept the required security-key algorithm' }
  }
  if ($effective -notmatch '(?im)^port 22\s*$' -or $effective -notmatch '(?im)^pubkeyauthentication yes\s*$') { throw 'existing SSH configuration must allow public-key authentication on port 22' }
  $expectedFile = if ($isAdmin) { '__PROGRAMDATA__/ssh/administrators_authorized_keys' } else { '.ssh/authorized_keys' }
  if ($effective -notmatch ('(?im)^authorizedkeysfile .*' + [regex]::Escape($expectedFile))) { throw 'existing SSH AuthorizedKeysFile differs from the supported path' }
  Send '기본 공개키 두 개와 SSH 서비스를 설정합니다. 모든 네트워크에서 TCP 22번을 허용합니다.'
  Set-Service sshd -StartupType Automatic
  $fw = Get-NetFirewallRule -Name 'Kiloworks-Onboarding-SSH' -ErrorAction SilentlyContinue
  if ($fw) { Remove-NetFirewallRule -Name 'Kiloworks-Onboarding-SSH' }
  New-NetFirewallRule -Name 'Kiloworks-Onboarding-SSH' -DisplayName 'Kiloworks Onboarding SSH (all networks)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
  Restart-Service sshd
  $script:targetAccount = $account
  $script:authorizedKeys = $authFile
}
try {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  if (!(New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) { throw 'administrator permission required' }
  if ([string]$config.sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { throw 'invalid target SID' }
  $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
  $stage = 'update'; Retry { Update-Tailscale }
  $stage = 'logout'
  if ($config.replace) {
    Send '사용자가 승인한 기존 Tailscale 계정을 로그아웃합니다.'
    [void](Run-Process $ts @('logout'))
  }
  $stage = 'connect'; Retry { Connect-Tailscale }
  $stage = 'ssh'; Retry { Install-SSH }
  $stage = 'verify'
  $s = Status
  if (!$s -or $s.BackendState -ne 'Running') { throw 'network is not connected' }
  $service = Get-Service sshd
  if ($service.Status -ne 'Running' -or $service.StartType -ne 'Automatic') { throw 'SSH service verification failed' }
  $firewall = Get-NetFirewallRule -Name 'Kiloworks-Onboarding-SSH'
  if ($firewall.Enabled.ToString() -ne 'True') { throw 'firewall verification failed' }
  $ip = [string]($s.TailscaleIPs | Select-Object -First 1)
  if (!$ip) { throw 'Tailscale address unavailable' }
  $report = "SSH 계정: $targetAccount`nTailscale IP: $ip`n공개키 파일: $authorizedKeys`n방화벽: 모든 네트워크 TCP 22`n관리자 측 원격 접속: 미검증"
  if ($reboot) { $report += "`nWindows에서 재부팅을 요청했습니다. 재부팅 후 앱으로 상태를 다시 확인해 주세요." }
  Send '네트워크 연결과 SSH 준비가 완료되었습니다.' $true $true $report
} catch {
  # Upstream output may contain secrets; return only controlled diagnostics and error codes.
  $safe = [string]$_.Exception.Message
  $safe = $safe -replace 'tskey-[A-Za-z0-9_-]+', '[비밀 삭제]'
  if ($safe.Length -gt 300) { $safe = '작업 실패. Windows 기능과 네트워크 상태를 확인해 주세요.' }
  Send ("$stage 단계 실패: $safe") $true $false
} finally {
  $key = ''; $config = $null
  $reader.Dispose(); $writer.Dispose(); $client.Dispose()
}
