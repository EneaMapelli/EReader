#Requires -Version 5.1
<#
Publish the SANITIZED results from an ALREADY completed Windows run.
Never reads raw stdout/stderr and never reruns Flutter tests.

Usage:
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\publish-local-test-report.ps1 -RunId 20261025T092418Z-0ff39187-2aa89e
#>
[CmdletBinding()]
param(
  [ValidatePattern('^(?:|\d{8}T\d{6}Z-[a-f0-9]{8}-[a-f0-9]{6})$')]
  [string]$RunId = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoBranch = 'feature/m0-flutter-foundation'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $repoRoot
$runRoot = Join-Path $repoRoot '.local-test-results'
if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
  throw 'No local test run folder found. The previous run must still exist.'
}
if (-not $RunId) {
  $chosen = Get-ChildItem -LiteralPath $runRoot -Directory |
    Where-Object { $_.Name -match '^\d{8}T\d{6}Z-[a-f0-9]{8}-[a-f0-9]{6}$' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'summary.json')) } |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($null -eq $chosen) { throw 'No completed sanitized local run exists.' }
  $RunId = $chosen.Name
}
$runDir = Join-Path $runRoot $RunId
if (-not (Test-Path -LiteralPath $runDir -PathType Container)) {
  throw ('Local run not found: ' + $RunId)
}
$inputNames = @('summary.json','cases.json','failures.json','latest.md')
$input = @{}
foreach ($name in $inputNames) {
  $file = Join-Path $runDir $name
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw ('Incomplete local run: missing ' + $name)
  }
  $size = (Get-Item -LiteralPath $file).Length
  if ($size -le 0 -or $size -gt 10MB) {
    throw ('Unexpected sanitized report size: ' + $name)
  }
  $input[$name] = [IO.File]::ReadAllText($file)
}
$summary = $input['summary.json'] | ConvertFrom-Json
$cases = @($input['cases.json'] | ConvertFrom-Json)
$failures = @($input['failures.json'] | ConvertFrom-Json)
if ($summary.runId -ne $RunId -or
    $summary.branch -ne $repoBranch -or
    [string]$summary.sourceCommit -notmatch '^[a-f0-9]{40}$' -or
    $RunId.Split('-')[1] -ne $summary.sourceCommit.Substring(0,8) -or
    $summary.result -notin @('PASS','FAIL')) {
  throw 'The saved run metadata does not match its source or branch.'
}
$totals = $summary.totals
$observed = @($cases | Where-Object { $_.status -eq 'success' }).Count
$failed = @($cases | Where-Object { $_.status -eq 'failure' }).Count
$errors = @($cases | Where-Object {
  $_.status -eq 'error' -or $_.status -eq 'incomplete'
}).Count
$skipped = @($cases | Where-Object { $_.status -eq 'skipped' }).Count
if ($cases.Count -ne [int]$totals.testOutcomesParsed -or
    $observed -ne [int]$totals.passed -or
    $failed -ne [int]$totals.failed -or
    $errors -ne [int]$totals.errors -or
    $skipped -ne [int]$totals.skipped -or
    $failures.Count -ne $failed + $errors) {
  throw 'Saved report case totals do not reconcile.'
}
# Review names/paths before pushing: the sanitizer leaves raw logs local.
foreach ($case in @($cases) + @($failures)) {
  $file = [string]$case.file
  if ($file -notmatch '^(?:test/[A-Za-z0-9_./-]+\.dart|<full_suite>)$' -or
      $file.Contains('..') -or
      $file.Length -gt 220) {
    throw 'Report includes an unsafe or unrecognized test file path.'
  }
}
foreach ($name in $inputNames) {
  if ($input[$name] -match '(?i)([a-z]:[\\/]|[\\/](?:Users|home)[\\/])') {
    throw ('Possible absolute path in report: ' + $name)
  }
}
$git = (Get-Command git -ErrorAction Stop).Source
$headBranch = (& $git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $headBranch -ne $repoBranch) {
  throw 'Switch to feature/m0-flutter-foundation before publishing.'
}
$dirty = @(& $git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
  throw 'Tracked worktree is not clean; commit existing changes separately.'
}
$origin = (& $git remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0 -or
    $origin -notmatch '(?i)github\.com[:/]EneaMapelli/EReader(?:\.git)?$') {
  throw 'Git origin does not match the EReader repository.'
}
& $git cat-file -e ($summary.sourceCommit + '^{commit}')
if ($LASTEXITCODE -ne 0) { throw 'Tested source commit is missing locally.' }
& $git merge-base --is-ancestor $summary.sourceCommit HEAD
if ($LASTEXITCODE -ne 0) {
  throw 'The tested source is not an ancestor of this branch. Refusing upload.'
}

$public = Join-Path $repoRoot 'test-results'
$runs = Join-Path $public 'runs'
[void][IO.Directory]::CreateDirectory($runs)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$destinations = [ordered]@{
  "test-results/runs/$RunId.md" = 'latest.md'
  "test-results/runs/$RunId.json" = 'summary.json'
  "test-results/runs/$RunId-cases.json" = 'cases.json'
  "test-results/runs/$RunId-failures.json" = 'failures.json'
  'test-results/latest.md' = 'latest.md'
  'test-results/latest.json' = 'summary.json'
  'test-results/latest-cases.json' = 'cases.json'
  'test-results/latest-failures.json' = 'failures.json'
}
# Immutable historical run evidence cannot be overwritten.
foreach ($entry in $destinations.GetEnumerator()) {
  if (-not $entry.Key.StartsWith('test-results/runs/')) { continue }
  $target = Join-Path $repoRoot $entry.Key
  if ((Test-Path -LiteralPath $target) -and
      [IO.File]::ReadAllText($target) -ne $input[$entry.Value]) {
    throw 'An immutable run report already exists with different content.'
  }
}
foreach ($entry in $destinations.GetEnumerator()) {
  $target = Join-Path $repoRoot $entry.Key
  [IO.File]::WriteAllText($target, $input[$entry.Value], $utf8)
}
& $git add -- @($destinations.Keys)
if ($LASTEXITCODE -ne 0) { throw 'Could not stage sanitized report files.' }
& $git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host ('Sanitized run already committed: ' + $RunId)
  exit 0
}
& $git commit -m ("test(results): publish recovered Windows $($summary.result) $RunId")
if ($LASTEXITCODE -ne 0) {
  throw 'Report staging succeeded but the Git commit failed.'
}
& $git push origin ("HEAD:refs/heads/$repoBranch")
if ($LASTEXITCODE -ne 0) {
  throw 'Report committed locally, but push failed. Fetch/reconcile branch before retrying; never force push.'
}
Write-Host ('Published prior sanitized run: ' + $RunId)
Write-Host ("Source: $($summary.sourceCommit) ; pass=$observed fail=$failed errors=$errors")
