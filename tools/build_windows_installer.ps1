param(
  [Parameter(Mandatory=$true)][string]$Compiler,
  [Parameter(Mandatory=$true)][string]$RuntimeDir,
  [string]$OutputPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'build/windows/x64/runner/Release'
if (!(Test-Path (Join-Path $release 'daily_report_reminder.exe'))) {
  throw 'Build first: flutter build windows --release --no-tree-shake-icons'
}
foreach ($name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
  if (!(Test-Path (Join-Path $RuntimeDir $name))) { throw "Missing x64 runtime: $name" }
}
& $Compiler "/DReleaseDir=$release" "/DRuntimeDir=$RuntimeDir" "/DOutputPath=$OutputPath" (Join-Path $PSScriptRoot 'windows-installer.iss')
if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed: $LASTEXITCODE" }
