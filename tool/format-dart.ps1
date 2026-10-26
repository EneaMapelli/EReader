#Requires -Version 5.1
<#
Applies the project Dart formatter on Windows and optionally publishes the
format-only change on the SAME feature branch. It does not run tests and
never stages test reports or personal files.
Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\format-dart.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\format-dart.ps1 -NoCommit
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\format-dart.ps1 -NoPush
#>
[CmdletBinding()]
param([switch]$NoCommit,[switch]$NoPush)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$branch = 'feature/m0-flutter-foundation'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root

$gitCommand = Get-Command git -ErrorAction Stop
$git = $gitCommand.Source
$localBranch = (& $git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $localBranch -ne $branch) {
  throw 'Formatting requires the existing EReader feature branch.'
}
$origin = (& $git remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or
    $origin -notmatch '(?i)github\.com[:/]EneaMapelli/EReader(?:\.git)?$') {
  throw 'Origin does not match the expected EReader repository.'
}
$changesAtStart = @(& $git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $changesAtStart.Count -gt 0) {
  throw 'Tracked files are dirty; preserve existing changes before formatting.'
}

$dartCommand = Get-Command dart -ErrorAction SilentlyContinue
$dart = if ($dartCommand) { $dartCommand.Source } else {
  'C:\Users\eneam\AppData\Local\Temp\flutter\bin\dart.bat'
}
if (-not (Test-Path -LiteralPath $dart) -and
    -not (Get-Command $dart -ErrorAction SilentlyContinue)) {
  throw 'Dart executable not found. Run bootstrap before formatting.'
}
Write-Host 'Formatting tracked Dart code in lib/ and test/...' -ForegroundColor Cyan
& $dart format lib test
if ($LASTEXITCODE -ne 0) { throw 'Dart formatter failed; inspect local changes.' }

$formatted = @(& $git diff --name-only -- lib test)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect formatter diff.' }
if ($formatted.Count -eq 0) {
  Write-Host 'All Dart source files are already formatted.' -ForegroundColor Green
  exit 0
}
foreach ($name in $formatted) {
  if ($name -notmatch '^(lib|test)/[a-zA-Z0-9_./-]+\.dart$' -or
      $name -match '(^|/)\.\.(/|$)') {
    throw 'Formatter changed an unexpected file; inspect changes locally.'
  }
}
Write-Host ('Dart files formatted: ' + $formatted.Count)
if ($NoCommit) {
  Write-Host 'Changes remain local for review (-NoCommit).' -ForegroundColor Yellow
  exit 0
}
& $git add -- lib test
if ($LASTEXITCODE -ne 0) { throw 'Could not stage formatted Dart source.' }
& $git commit -m 'style(dart): apply repository formatter'
if ($LASTEXITCODE -ne 0) { throw 'Could not commit formatted files.' }
if ($NoPush) {
  Write-Host 'Format commit is local (-NoPush).' -ForegroundColor Yellow
  exit 0
}
# Push without --force. Divergent concurrent work is rejected normally.
& $git push origin ("HEAD:refs/heads/$branch")
if ($LASTEXITCODE -ne 0) {
  throw 'Push rejected; keep the local format commit and reconcile remote changes.'
}
Write-Host 'Formatted Dart files committed and pushed on the existing branch.' -ForegroundColor Green
