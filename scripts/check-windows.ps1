$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PWD 'src\windows.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Load only functions, never the privileged helper's top-level operations.
foreach ($fn in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
  . ([scriptblock]::Create($fn.Extent.Text))
}
$script:messages = @()
function Send { param($Message) $script:messages += $Message }
$script:attempt = 0
Retry { $script:attempt++; if ($script:attempt -eq 1) { throw 'transient' } }
if ($script:attempt -ne 2) { throw 'Retry must attempt exactly twice' }
$script:attempt = 0
try { Retry { $script:attempt++; throw 'persistent' } } catch {}
if ($script:attempt -ne 2) { throw 'Persistent failure must not loop' }
$out = Run-Process "$env:SystemRoot\System32\whoami.exe" @('/user')
if (!$out) { throw 'Process output capture failed' }
# The registration key must be delivered over a named pipe, not argv or disk.
$source = Get-Content src\windows.ps1 -Raw
if ($source -notmatch 'auth-key=file:') { throw 'Missing auth-key named pipe' }
if ($source -match 'auth-key=\$') { throw 'Auth key must not be in process arguments' }
# A missing server must use the signed MSI route without entering Windows Update servicing.
$script:installs = 0
function Get-Service { param($Name, $ErrorAction) return $null }
function Upgrade-OpenSSH { $script:installs++; throw 'test-install-boundary' }
try { Install-SSH; throw 'Missing server skipped installation' }
catch { if ($_.Exception.Message -ne 'test-install-boundary') { throw } }
if ($script:installs -ne 1) { throw 'Missing server must install the official package once' }
Write-Host 'PowerShell syntax, retry, process boundary and missing SSH server routing: PASS'
# Existing connections cannot bypass a fresh key.
function Status { return @{ BackendState = 'Running' } }
$script:registered = $false
$script:key = 'invalid'
try { Connect-Tailscale; throw 'Existing connection bypassed registration' }
catch { if ($_.Exception.Message -ne 'a new auth key is required') { throw } }
# Exercise reset without touching the runner's actual services or state.
$script:calls = @()
function Stop-Service { param($Name, [switch]$Force) $script:calls += 'stop' }
function Start-Service { param($Name) $script:calls += 'start' }
function Get-Process { param($Name, $ErrorAction) return $null }
function Get-ItemProperty { param($Path) return @{ ProfileImagePath = 'C:\Users\fixture' } }
function Test-Path { param($LiteralPath) return $true }
function Get-Item { param($LiteralPath, [switch]$Force) return @{ Attributes = 0 } }
function Get-ChildItem { param($LiteralPath, [switch]$Recurse, [switch]$Force) return @() }
function Remove-Item { param($LiteralPath, [switch]$Recurse, [switch]$Force) $script:calls += 'delete' }
$script:key = 'tskey-auth-test-only-key'
Reset-Tailscale
if (($script:calls -join ',') -ne 'stop,delete,delete,delete,start') { throw 'Reset must stop, delete all state paths, then start' }
if ($script:registered) { throw 'Reset retained registration success' }
Write-Host 'Fresh registration and destructive reset ordering: PASS'
