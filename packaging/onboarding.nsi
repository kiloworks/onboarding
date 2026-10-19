Unicode True
!include "MUI2.nsh"
!include "WinVer.nsh"
!ifndef ARCH
!define ARCH "x64"
!endif
Name "Kiloworks Onboarding"
OutFile "..\dist\onboarding-0.3.0-windows-${ARCH}-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Kiloworks\Onboarding"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\onboarding.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"
Function .onInit
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP "Windows 10 이상이 필요합니다."
    Abort
  ${EndIf}
FunctionEnd
Section "Onboarding"
  SetOutPath "$INSTDIR"
  File "..\dist\onboarding.exe"
  File "..\dist\*.dll"
  File "..\LICENSE"
  File "..\THIRD_PARTY_NOTICES.md"
  ; Replace generated notices only when upgrading this registered installation.
  ReadRegStr $R0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding" "UninstallString"
  ${If} $R0 == '"$INSTDIR\Uninstall.exe"'
  ${OrIf} $R0 == '$$"$INSTDIR\Uninstall.exe$$"'
    RMDir /r "$INSTDIR\licenses"
    Delete "$INSTDIR\gpuix-native.node"
  ${EndIf}
  SetOutPath "$INSTDIR\licenses"
  File /r "..\dist\licenses\*"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Kiloworks"
  CreateShortcut "$SMPROGRAMS\Kiloworks\Onboarding.lnk" "$INSTDIR\onboarding.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding" "DisplayName" "Kiloworks Onboarding"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding" "DisplayVersion" "0.3.0"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding" "NoRepair" 1
SectionEnd
Section "Uninstall"
  Delete "$INSTDIR\onboarding.exe"
  Delete "$INSTDIR\gpuix-native.node"
  Delete "$INSTDIR\vcruntime140*.dll"
  Delete "$INSTDIR\msvcp140*.dll"
  Delete "$INSTDIR\concrt140.dll"
  Delete "$INSTDIR\vccorlib140.dll"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR\licenses"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\Kiloworks\Onboarding.lnk"
  RMDir "$SMPROGRAMS\Kiloworks"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiloworksOnboarding"
SectionEnd
