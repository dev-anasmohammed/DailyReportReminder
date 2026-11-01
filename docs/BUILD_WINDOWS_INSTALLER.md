# Create the Windows setup installer

Use this guide in Android Studio or VS Code. Run all commands in the same
PowerShell terminal, from the project folder. You can paste each command
separately and press Enter; variables remain available until you close the terminal.

## 1. Install the tools once

- Flutter, configured for Windows desktop builds.
- Visual Studio or Visual Studio Build Tools with **Desktop development with C++**.
  VS Code alone does not include these build tools.
- [Inno Setup](https://jrsoftware.org/isdl.php). Run the downloaded installer to
  install it. On this computer, its compiler is at
  `C:\Program Files\Inno Setup 7\ISCC.exe`.

## 2. Open the terminal

- Android Studio: **View > Tool Windows > Terminal**.
- VS Code: **Terminal > New Terminal**.

Select PowerShell, then go to the project folder:

```powershell
cd C:\Users\Android\AndroidStudioProjects\DailyReportReminder
```

## 3. Build the release app

Run each command and wait for it to finish successfully:

```powershell
flutter pub get
flutter build windows --release --no-tree-shake-icons
```

The app and its supporting files are created in
`build\windows\x64\runner\Release`. The next step packages them into a setup file.

## 4. Find Inno Setup

Run:

```powershell
$compiler = Get-Item 'C:\Program Files\Inno Setup 7\ISCC.exe'
$compiler.FullName
```

If Inno Setup is installed elsewhere, use this search instead:

```powershell
$compiler = Get-ChildItem -Path "${env:ProgramFiles}\Inno Setup*\ISCC.exe","${env:ProgramFiles(x86)}\Inno Setup*\ISCC.exe","$env:LOCALAPPDATA\Programs\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
$compiler.FullName
```

Continue only when a path ending in `ISCC.exe` is printed.

## 5. Find the Visual C++ runtime

Run these commands in the same terminal:

```powershell
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$runtime = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
$runtime.FullName
```

Continue only when a runtime directory is printed. The installer script checks
that it contains `msvcp140.dll`, `vcruntime140.dll`, and `vcruntime140_1.dll`.

## 6. Create the setup installer

```powershell
.\tools\build_windows_installer.ps1 -Compiler $compiler.FullName -RuntimeDir $runtime.FullName -OutputPath "$PWD\build"
```

Wait for compilation to finish successfully. The result is:

```text
C:\Users\Android\AndroidStudioProjects\DailyReportReminder\build\DailyReportReminder-Setup-Windows-x64.exe
```

## 7. Install on another Windows PC

Copy `DailyReportReminder-Setup-Windows-x64.exe` to the other Windows 10/11
64-bit PC and run it. The setup includes the app files and Visual C++ runtime
DLLs, creates a Start menu shortcut, and provides an uninstaller.

The other PC does not need Flutter, Android Studio, VS Code, or Inno Setup.
Configure the app's profile and Gmail on that PC; install Git there if you want
to collect commits from local repositories.

## Common errors

### Compiler is an empty string

`$compiler` is empty. Repeat step 4 in the current terminal and check the printed
path. Downloading Inno Setup without running its installer is not sufficient.

### RuntimeDir is an empty string, or a runtime DLL is missing

Repeat step 5. If no directory is printed, open Visual Studio Installer and
install or repair **Desktop development with C++**, including the MSVC x64/x86
build tools and redistributable runtime components.

### Build first

Complete step 3 successfully before running the installer script.

### A new terminal was opened

PowerShell variables are not saved between terminals. Repeat steps 4 and 5
before step 6.

For each future release, rebuild the app and create the installer again using
steps 3 through 6. See [INSTALLERS.md](INSTALLERS.md) for installation behavior
and macOS packaging information.
