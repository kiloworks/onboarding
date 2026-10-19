$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Standard'
$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$status = (& $ts status --json | Out-String) | ConvertFrom-Json
$ip = [string]($status.TailscaleIPs | Select-Object -First 1)
if (!$ip) { throw 'No Tailscale IP for SSH test' }
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = @(Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.SID.Value -eq $id.User.Value }).Count -gt 0
$authFile = if ($isAdmin) { Join-Path $env:ProgramData 'ssh/administrators_authorized_keys' } else { Join-Path $env:USERPROFILE '.ssh/authorized_keys' }
$original = [IO.File]::ReadAllBytes($authFile)
$expected = @(Get-Content config/administrators_authorized_keys)
foreach ($pub in $expected) { if (@(Get-Content $authFile) -notcontains $pub) { throw 'Default public key missing' } }
$work = Join-Path $env:RUNNER_TEMP ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
  $bin = if (Test-Path "$env:ProgramFiles/OpenSSH/ssh.exe") { "$env:ProgramFiles/OpenSSH" } else { "$env:WINDIR/System32/OpenSSH" }
  $key = Join-Path $work 'test-key'
  & "$bin/ssh-keygen.exe" -t ed25519 -N '' -f $key -q
  if ($LASTEXITCODE -ne 0) { throw 'Temporary SSH test key generation failed' }
  Add-Content $authFile (Get-Content "$key.pub") -Encoding ascii
  $known = Join-Path $work 'known_hosts'
  Get-ChildItem "$env:ProgramData/ssh/ssh_host_*_key.pub" | ForEach-Object {
    "$ip $(Get-Content $_.FullName)" | Add-Content $known -Encoding ascii
  }
  $output = & "$bin/ssh.exe" -i $key -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known" -o ConnectTimeout=20 -l $env:USERNAME $ip 'echo onboarding-ssh-ok' 2>$null
  if ($LASTEXITCODE -ne 0 -or ($output | Out-String) -notmatch 'onboarding-ssh-ok') { throw 'Real SSH authentication/command execution failed' }
  Write-Host 'SSH over this node Tailscale address: PASS (same-node test; cross-peer and FIDO hardware signing remain separate)'
} finally {
  [IO.File]::WriteAllBytes($authFile, $original)
  Remove-Item -Recurse -Force $work
}
