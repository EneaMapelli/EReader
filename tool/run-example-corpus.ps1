#Requires -Version 5.1
<#
Run real EPUB and PDF regression tests on user-owned files in example/.
Books, file names, raw logs and per-book JSON stay LOCAL (gitignored).
This script never commits, pushes, or downloads user book content.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-example-corpus.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-example-corpus.ps1 -Deep
#>
[CmdletBinding()]
param([switch]$Deep)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$folder = Join-Path $root 'example'
if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
  throw 'Create the example/ folder next to pubspec.yaml with EPUB/PDF files.'
}

# Flutter may be on PATH or in the SDK location already used locally by the
# test runner. Do not hardcode the computer owner's Windows username.
$cmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($cmd) { $cmd.Source } else { $null }
if (-not $flutter -and $env:FLUTTER_ROOT) {
  $candidate = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
  if (Test-Path -LiteralPath $candidate) { $flutter = $candidate }
}
if (-not $flutter -and $env:TEMP) {
  $candidate = Join-Path $env:TEMP 'flutter\bin\flutter.bat'
  if (Test-Path -LiteralPath $candidate) { $flutter = $candidate }
}
if (-not $flutter) {
  throw 'Flutter SDK not found. Put flutter on PATH or set FLUTTER_ROOT.'
}

$outputDir = Join-Path $root '.local-test-results\example-corpus'
[void][IO.Directory]::CreateDirectory($outputDir)
$utc = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$stdoutPath = Join-Path $outputDir ($utc + '.flutter-json.log')
$stderrPath = Join-Path $outputDir ($utc + '.stderr.log')
$summaryPath = Join-Path $outputDir 'latest.json'
if (Test-Path -LiteralPath $summaryPath) {
  Remove-Item -LiteralPath $summaryPath -Force
}

$flutterArgs = @('test', '--reporter=json',
  '--dart-define=EREADER_EXAMPLE_CORPUS=true')
if ($Deep) { $flutterArgs += '--dart-define=EREADER_EXAMPLE_DEEP=true' }
$flutterArgs += 'test/local_example_corpus_test.dart'

Write-Host 'Running example corpus from local files (no Git upload).' -ForegroundColor Cyan
Write-Host ('EPUB worker comparisons: ' + [bool]$Deep)

# Redirect unredacted Flutter output exclusively into ignored local files.
# Native shell diagnostics can include local paths and must not be published.
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $flutter @flutterArgs 1> $stdoutPath 2> $stderrPath
  $code = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $oldPreference
}
if ($null -eq $code) { $code = 125 }

if (Test-Path -LiteralPath $summaryPath) {
  $report = Get-Content -LiteralPath $summaryPath -Raw |
      ConvertFrom-Json -ErrorAction Stop
  $passed = @($report.entries | Where-Object { $_.outcome -eq 'passed' })
  $failed = @($report.entries | Where-Object { $_.outcome -ne 'passed' })
  Write-Host ('Files: {0}  Passed: {1}  Failed: {2}' -f
      $report.totalFiles, $passed.Count, $failed.Count)
  foreach ($item in $report.entries) {
    $status = if ($item.outcome -eq 'passed') { 'PASS' } else { 'FAIL' }
    $label = ('[{0}] {1} - {2} ({3} ms)' -f
      $status, $item.format.ToUpperInvariant(), $item.file, $item.elapsedMs)
    Write-Host $label
    if ($item.classification -eq 'scanned-or-no-text-needs-ocr') {
      Write-Host '    PDF has no text layer: visual-only until OCR is added.'
    }
    if ($item.outcome -ne 'passed') {
      Write-Host ('    Failure category: ' + $item.failureType)
    }
  }
} else {
  Write-Warning 'The corpus report was not created. Check local Flutter logs.'
}

Write-Host ('Local summary: ' + $summaryPath)
Write-Host ('Local Flutter log: ' + $stdoutPath)
Write-Host ('Local stderr log: ' + $stderrPath)
if ($code -ne 0) {
  throw ('Corpus test run failed (Flutter exit {0}). See local logs.' -f $code)
}
if (-not (Test-Path -LiteralPath $summaryPath)) {
  throw 'The test process finished without producing corpus metrics.'
}
Write-Host 'Corpus suite completed successfully.' -ForegroundColor Green
