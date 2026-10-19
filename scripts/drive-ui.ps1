param([switch]$E2E)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class NativeInput {
 [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public UNION u; }
 [StructLayout(LayoutKind.Explicit)] public struct UNION { [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUT mi; }
 [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
 [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int x,y; public uint data,flags,time; public UIntPtr extra; }
 [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] input, int size);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
 public static void Text(string s) { foreach(char c in s) { var a = new INPUT[2]; a[0].type=a[1].type=1; a[0].u.ki.scan=a[1].u.ki.scan=c; a[0].u.ki.flags=4; a[1].u.ki.flags=6; if(SendInput(2,a,Marshal.SizeOf(typeof(INPUT)))!=2) throw new Exception("Text input failed"); } }
}
'@
function Find([string]$Id, [int]$Timeout = 30) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Timeout)
  do {
    $p.Refresh()
    if ($p.HasExited) { throw 'Application exited during UI test' }
    if ($p.MainWindowHandle -ne 0) {
      $root = [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
      $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
      $node = $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)
      if ($null -ne $node) { return $node }
    }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "UI control not found: $Id"
}
function Click([string]$Id) {
  $node = Find $Id
  $pattern = $node.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
  $pattern.Invoke()
  Start-Sleep -Milliseconds 200
}
$key = if ($E2E) { [Console]::In.ReadLine() } else { 'tskey-auth-test-only-not-a-real-key' }
$p = Start-Process $env:ONBOARDING_EXE -PassThru
try {
  [void](Find 'begin' 60)
  Click 'begin'
  if (!$E2E) {
    Click 'next'
    if ((Find 'status').Current.Name -notmatch '키') { throw 'Invalid key did not block progression' }
  }
  $input = Find 'auth-key'
  [void][NativeInput]::SetForegroundWindow($p.MainWindowHandle)
  $input.SetFocus()
  [NativeInput]::Text($key)
  $key = $null
  Click 'next'
  [void](Find 'start')
  if ((Find 'heading').Current.Name -notmatch '시작 전에') { throw 'Missing explicit final review' }
  if (!$E2E) { Write-Host 'Native UI input, validation and final consent: PASS'; return }
  Click 'start'
  $deadline = [DateTime]::UtcNow.AddMinutes(30)
  do {
    $heading = (Find 'heading').Current.Name
    if ($heading -match '준비가 됐어요') { Write-Host 'Native packaged GUI onboarding: PASS'; return }
    if ($heading -match '멈췄어요') { throw 'Onboarding failed; inspect the sanitized install log' }
    Start-Sleep -Seconds 2
  } while ([DateTime]::UtcNow -lt $deadline)
  throw 'Onboarding E2E timed out'
} finally {
  $key = $null
  if (!$p.HasExited) { $p.CloseMainWindow() | Out-Null; if (!$p.WaitForExit(10000)) { $p.Kill() } }
}
