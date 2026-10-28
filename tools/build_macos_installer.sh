#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/macos/Build/Products/Release/Daily Report.app"
output="${1:-$root/DailyReportReminder-Setup-macOS.dmg}"
if [[ ! -d "$app" ]]; then
  echo 'Build first: flutter build macos --release --no-tree-shake-icons' >&2
  exit 1
fi

# Preserve the bundle's permissions, symlinks, and ad-hoc code signature.
staging="$(mktemp -d "${TMPDIR:-/tmp}/dailyreport-dmg.XXXXXX")"
ditto "$app" "$staging/Daily Report.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Install DailyReport.txt" <<'EOF'
Drag Daily Report into Applications, then open it from Applications.
Requires macOS 13 or later. Git must be installed to collect commits.

This build is not signed with an Apple Developer ID or notarized.
macOS may require explicit approval in System Settings > Privacy & Security.
Only approve an app you obtained from a source you trust.
EOF

lipo -archs "$app/Contents/MacOS/Daily Report"
codesign --verify --deep --strict "$app"
hdiutil create -volname DailyReport -srcfolder "$staging" -ov -format UDZO "$output"
hdiutil verify "$output"
echo "Created: $output"
