param([switch]$E2E, [switch]$Connected)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
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
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
 public static void Activate(IntPtr hwnd, int x, int y) {
   SetForegroundWindow(hwnd);
   if (GetForegroundWindow() != hwnd) {
     SetCursorPos(x,y);
     var a = new INPUT[2]; a[0].u.mi.flags=2; a[1].u.mi.flags=4;
     if(SendInput(2,a,Marshal.SizeOf(typeof(INPUT)))!=2) throw new Exception("Window activation failed");
   }
 }
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
function Capture([string]$Name) {
  if ($E2E -or $Connected) { return }
  [void][NativeInput]::SetForegroundWindow($p.MainWindowHandle)
  Start-Sleep -Milliseconds 300
  $root = [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
  $rect = $root.Current.BoundingRectangle
  $bitmap = [Drawing.Bitmap]::new([int]$rect.Width, [int]$rect.Height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen([int]$rect.Left, [int]$rect.Top, 0, 0, $bitmap.Size)
    New-Item -ItemType Directory -Force artifacts | Out-Null
    $bitmap.Save((Join-Path $PWD "artifacts/ui-$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
  } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
$key = if ($E2E) { [Console]::In.ReadLine() } else { 'tskey-auth-test-only-not-a-real-key' }
$p = Start-Process $env:ONBOARDING_EXE -PassThru
try {
  $windowDeadline = [DateTime]::UtcNow.AddSeconds(30)
  do { $p.Refresh(); if ($p.HasExited) { throw 'App exited before opening its window' }; if ($p.MainWindowHandle -ne 0) { break }; Start-Sleep -Milliseconds 100 } while ([DateTime]::UtcNow -lt $windowDeadline)
  if ($p.MainWindowHandle -eq 0) { throw 'App did not open a native window' }
  $bounds = ([Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)).Current.BoundingRectangle
  [NativeInput]::Activate($p.MainWindowHandle, [int]($bounds.Left + 100), [int]($bounds.Top + 15))
  [void](Find 'begin' 60)
  Capture 'welcome'
  Click 'begin'
  if ($Connected) {
    [void](Find 'replace')
    Click 'next'
    [void](Find 'start')
    Click 'back'
    Click 'replace'
  }
  if (!$E2E) {
    Click 'next'
    if ((Find 'status').Current.Name -notmatch '키') { throw 'Invalid key did not block progression' }
  }
  $keyField = Find 'auth-key'
  [void][NativeInput]::SetForegroundWindow($p.MainWindowHandle)
  $keyField.SetFocus()
  $focusDeadline = [DateTime]::UtcNow.AddSeconds(3)
  while (!$keyField.Current.HasKeyboardFocus -and [DateTime]::UtcNow -lt $focusDeadline) { Start-Sleep -Milliseconds 100 }
  if (!$keyField.Current.HasKeyboardFocus) { throw 'Native key field did not receive keyboard focus' }
  Start-Sleep -Milliseconds 200
  [NativeInput]::Text($key)
  Start-Sleep -Milliseconds 300
  $key = $null
  Click 'next'
  $startButton = Find 'start'
  $windowBounds = ([Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)).Current.BoundingRectangle
  if ($startButton.Current.IsOffscreen -or $startButton.Current.BoundingRectangle.Bottom -gt $windowBounds.Bottom) { throw 'Final consent button is outside the window' }
  if ((Find 'heading').Current.Name -notmatch '시작 전에') { throw 'Missing explicit final review' }
  Capture 'review'
  if (!$E2E) { Write-Host 'Native UI input, validation and final consent: PASS'; return }
  Click 'start'
  $deadline = [DateTime]::UtcNow.AddMinutes(30)
  $lastProgress = ''
  do {
    $heading = (Find 'heading').Current.Name
    if ($heading -match '준비가 됐어요') { Write-Host 'Native packaged GUI onboarding: PASS'; return }
    $progress = (Find 'status').Current.Name -replace 'tskey-[A-Za-z0-9_-]+', '[secret removed]' -replace 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[token removed]'
    if ($progress -ne $lastProgress) { Write-Host "Onboarding progress: $progress"; $lastProgress = $progress }
    if ($heading -match '멈췄어요') { throw 'Onboarding failed; inspect the sanitized install log' }
    Start-Sleep -Seconds 2
  } while ([DateTime]::UtcNow -lt $deadline)
  throw 'Onboarding E2E timed out'
} catch {
  if (!$E2E -and !$Connected -and !$p.HasExited -and $p.MainWindowHandle -ne 0) {
    Capture 'failure'
  }
  throw
} finally {
  $key = $null
  if (!$p.HasExited) { $p.CloseMainWindow() | Out-Null; if (!$p.WaitForExit(10000)) { $p.Kill() } }
}
