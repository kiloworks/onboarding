$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Desktop preparation is only for disposable GitHub runners' }
# Windows 11 ARM images can open first-login privacy OOBE above the app.
# https://learn.microsoft.com/windows/client-management/mdm/policy-csp-privacy#disableprivacyexperience
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE'
New-Item $policy -Force | Out-Null
New-ItemProperty $policy -Name DisablePrivacyExperience -PropertyType DWord -Value 1 -Force | Out-Null
Get-Process -Name UserOOBEBroker,CloudExperienceHostBroker,CloudExperienceHost,WWAHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if ((Get-ItemProperty $policy).DisablePrivacyExperience -ne 1) { throw 'Runner privacy-experience policy was not applied' }
