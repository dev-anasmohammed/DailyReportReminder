#ifndef ReleaseDir
  #error ReleaseDir must point to the Flutter Windows release directory
#endif
#ifndef RuntimeDir
  #error RuntimeDir must point to the Visual C++ x64 CRT redistribution directory
#endif
#ifndef OutputPath
  #define OutputPath "..\.."
#endif

[Setup]
AppId={{DC20A71E-E18A-47BE-BA81-AED348D2CEAA}
AppName=DailyReport
AppVersion=1.0.0
AppPublisher=DailyReport
AppPublisherURL=https://github.com/dev-anasmohammed/DailyReportReminder
DefaultDirName={localappdata}\Programs\DailyReport
DefaultGroupName=DailyReport
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputPath}
OutputBaseFilename=DailyReportReminder-Setup-Windows-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\daily_report_reminder.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "startup"; Description: "Start DailyReport when I sign in"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\DailyReport"; Filename: "{app}\daily_report_reminder.exe"; AppUserModelID: "com.anas.dailyreport.reminder"
Name: "{autodesktop}\DailyReport"; Filename: "{app}\daily_report_reminder.exe"; Tasks: desktopicon; AppUserModelID: "com.anas.dailyreport.reminder"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Daily Report"; ValueData: """{app}\daily_report_reminder.exe"""; Flags: uninsdeletevalue; Tasks: startup
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; ValueType: binary; ValueName: "Daily Report"; ValueData: "02 00 00 00 00 00 00 00 00 00 00 00"; Flags: createvalueifdoesntexist uninsdeletevalue; Tasks: startup
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Daily Report"; Flags: deletevalue; Tasks: not startup
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; ValueName: "Daily Report"; Flags: deletevalue; Tasks: not startup

[Run]
Filename: "{app}\daily_report_reminder.exe"; Description: "Launch DailyReport"; Flags: nowait postinstall skipifsilent
