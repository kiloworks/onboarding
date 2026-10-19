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
Write-Host 'PowerShell syntax, one-retry policy and process boundary: PASS'
