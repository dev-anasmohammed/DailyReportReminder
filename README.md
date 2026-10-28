# Daily Report Reminder

A local-first Flutter app for Windows and macOS. Set your actual start time, get two reminders during an eight-hour day, and prepare your daily report from Git commits.

## Features

- Login startup toggle, Windows tray / macOS menu bar, and close-to-tray behavior.
- First reminder 2–6 hours after starting; second 0–60 minutes before finishing.
- Persistent reminder deadlines, catch-up after sleep/restart on the same day, and ten-minute snooze.
- Add local Git folders. Collect today's commits across local branches, filtered by exact author email and sorted oldest first. Uses author timestamps converted to local time. Does not fetch remote repositories or include uncommitted work.
- Editable Markdown work, tomorrow, and blockers sections, clipboard export, local drafts and report history.
- Complete today's report to stop reminders. No cloud service or AI API required.

## Develop

Install Flutter stable with Dart 3.13.7 or later and Git. Git must be available on the app's PATH. On macOS, `/usr/bin/git` is supplied by the Xcode command-line tools.

```sh
flutter pub get
flutter run -d windows
# On a Mac:
flutter run -d macos
```

Windows requires Visual Studio's **Desktop development with C++** workload and Developer Mode for Flutter plugin symlinks. macOS requires macOS 13+, Xcode, and the dependencies requested by `flutter doctor`.

```sh
dart format lib test
flutter analyze
flutter test
flutter build windows --release
# On a Mac:
flutter build macos --release
```

GitHub Actions checks both targets and uploads desktop build artifacts. Windows users need the whole Release folder, not just its executable. macOS artifacts are unsigned development builds; distribution requires Apple signing and notarization.

## Using the app

1. Confirm the suggested start time. The finish time is eight hours later; breaks do not pause the clock.
2. Add project folders and optionally enter your Git email. Otherwise each repository's `user.email` is used.
3. Collect commits, edit the work section, and fill in tomorrow's plans and blockers. Refreshing commits asks before replacing work-section edits.
4. Copy the report to your reporting tool and mark it completed.
5. Enable login startup after placing the built application in a permanent location. On macOS, use Applications and approve the login item in System Settings if prompted.
6. Use “I'm leaving now” in the tray to open your saved draft when leaving early.

Notification delivery depends on OS permissions and Focus/Do Not Disturb settings. Use Test notification after installation. The in-app snooze works on both targets; notification action availability varies by OS. Reminders require the app to be running and the computer awake. Closing the window keeps it running; quitting stops reminders. A missed deadline is checked every 20 seconds while running. The app cannot detect unexpected departures or notify while powered off.

Drafts and history use local SharedPreferences storage (not encrypted, no cross-device sync). Do not store secrets in report text. macOS App Sandbox is disabled for this developer-distributed app so Git subprocesses can access your chosen repositories. Mac App Store distribution would require a different repository-access design.

## Current verification limits

macOS runtime behavior and Apple signing must be verified on a Mac. CI provides a separate build for each platform. No automatic report sending is implemented.
