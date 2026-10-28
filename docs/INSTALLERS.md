# Desktop installers

The Desktop builds GitHub Actions workflow publishes two installer artifacts:

- **DailyReport-Windows-Installer** contains `DailyReportReminder-Setup-Windows-x64.exe`. Run it on Windows 10/11 64-bit. It installs for the current user, includes the Visual C++ runtime DLLs, and creates a Start menu shortcut and uninstaller. A desktop shortcut is optional.
- **DailyReport-macOS-Installer** contains `DailyReportReminder-Setup-macOS.dmg`. Open it on macOS 13 or later and drag Daily Report into Applications. The packaging step prints the app's supported CPU architectures in the build log.

Both installations start with local profile setup. Install Git to collect commits, add local project folders, and configure Gmail on each computer. No user profiles, report drafts, or Gmail credentials are included in these installers.

These builds do not have a commercial Windows code-signing certificate or an Apple Developer ID signature and notarization. Windows or macOS may require approval before opening. Only approve downloads you trust. Apple signing and notarization must be configured before a broadly distributed macOS release.

## Rebuild locally

Build the Flutter app in release mode with `--no-tree-shake-icons` first.

On Windows, install Inno Setup and run `tools/build_windows_installer.ps1` with `-Compiler` pointing to ISCC.exe and `-RuntimeDir` pointing to your Visual Studio redistributable x64 `Microsoft.VC*.CRT` directory. `-OutputPath` optionally controls the output directory.

On a Mac, run `bash tools/build_macos_installer.sh` after `flutter build macos --release --no-tree-shake-icons`. The script creates and verifies a compressed disk image with an Applications shortcut using Apple's built-in tools.
