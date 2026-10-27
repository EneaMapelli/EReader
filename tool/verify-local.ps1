#Requires -Version 5.1
<#
Local-only Windows verification. No Windows build, GitHub Actions,
git add/commit/push or model download.
Examples:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1 -SoakIterations 500 -IncludeCorpus -DeepCorpus
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1 -AudioOnly
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify-local.ps1 -NativeVoiceSourceFolder C:\voice-models\italian -AcceptNativeRisk
#>
[CmdletBinding()]
param(
  [switch]$AudioOnly,
  [switch]$SkipSoak,
  [ValidateRange(2,2000)][int]$SoakIterations = 200,
  [switch]$IncludeCorpus,
  [switch]$DeepCorpus,
  [string]$NativeVoiceSourceFolder = '',
  [switch]$AcceptNativeRisk,
  [switch]$ExerciseNativeStop,
  [switch]$RetainNativeWav
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($DeepCorpus) { $IncludeCorpus = $true }
if ($NativeVoiceSourceFolder -and -not $AcceptNativeRisk) {
  throw 'Native model requested: explicitly add -AcceptNativeRisk.'
}
if (-not $NativeVoiceSourceFolder -and
    ($AcceptNativeRisk -or $ExerciseNativeStop -or $RetainNativeWav)) {
  throw 'Native flags require -NativeVoiceSourceFolder and -AcceptNativeRisk.'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
if (-not (Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml') -PathType Leaf)) {
  throw 'Run from an EReader checkout with pubspec.yaml.'
}
if ($IncludeCorpus -and
    -not (Test-Path -LiteralPath (Join-Path $root 'example') -PathType Container)) {
  throw 'example/ is missing; add your own private EPUB/PDF files, or omit -IncludeCorpus.'
}
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$commit = 'unavailable'
$branch = 'unavailable'
if ($gitCmd) {
  $gitExe = $gitCmd.Source
  $reportedSha = & $gitExe rev-parse HEAD 2>$null
  if ($LASTEXITCODE -eq 0) { $commit = ([string]$reportedSha).Trim() }
  $reportedBranch = & $gitExe branch --show-current 2>$null
  if ($LASTEXITCODE -eq 0) { $branch = ([string]$reportedBranch).Trim() }
}
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') +
    '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$runDir = Join-Path (Join-Path $root '.local-test-results\local-verification') $runId
[void][IO.Directory]::CreateDirectory($runDir)
$startedUtc = [DateTime]::UtcNow
$stages = New-Object System.Collections.ArrayList
$psExe = (Get-Command powershell.exe -ErrorAction Stop).Source

function Find-Flutter {
  $which = Get-Command flutter -ErrorAction SilentlyContinue
  if ($which) { return $which.Source }
  $candidates = @()
  if ($env:FLUTTER_ROOT) {
    $candidates += (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat')
  }
  if ($env:TEMP) {
    $candidates += (Join-Path $env:TEMP 'flutter\bin\flutter.bat')
  }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return $candidate
    }
  }
  throw 'Flutter is not installed or discoverable. Set PATH or FLUTTER_ROOT.'
}
function Run-Stage([string]$label,[string]$exe,[string[]]$arguments) {
  $stdout = Join-Path $script:runDir ($label + '.stdout.log')
  $stderr = Join-Path $script:runDir ($label + '.stderr.log')
  $since = [DateTime]::UtcNow
  $exitCode = 125
  Write-Host ('>>> ' + $label) -ForegroundColor Cyan
  try {
    # Child powershell.exe isolates scripts which call exit 1.
    # Suppress all unredacted native stdout/stderr from console and
    # preserve them only under the gitignored local results directory.
    $global:LASTEXITCODE = $null
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & $exe @arguments 1> $stdout 2> $stderr
    } finally {
      $ErrorActionPreference = $previousPreference
    }
    if ($null -ne $global:LASTEXITCODE) {
      $exitCode = [int]$global:LASTEXITCODE
    }
  } catch {
    $_ | Out-String | Out-File -LiteralPath $stderr -Append -Encoding UTF8
  }
  $seconds = [Math]::Round(([DateTime]::UtcNow - $since).TotalSeconds, 1)
  $status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
  [void]$script:stages.Add([ordered]@{
    name=$label;result=$status;exitCode=$exitCode;seconds=$seconds
    stdout=$label + '.stdout.log';stderr=$label + '.stderr.log'
  })
  Write-Host ('    {0}: exit={1}, seconds={2}' -f $status,$exitCode,$seconds)
}
if ($AudioOnly) {
  $flutter = Find-Flutter
  Run-Stage 'pub-get' $flutter @('pub','get')
  Run-Stage 'analyze' $flutter @('analyze','--no-pub')
  Run-Stage 'audio-tests' $flutter @('test','--no-pub','--reporter','expanded','test/audio')
} else {
  # Critically: NEVER allow run-all-tests.ps1 to publish results.
  Run-Stage 'full-suite' $psExe @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',
    (Join-Path $PSScriptRoot 'run-all-tests.ps1'),'-NoPublish'
  )
}
if (-not $SkipSoak) {
  $flutter = Find-Flutter
  Run-Stage 'synthetic-wav-soak' $flutter @(
    'test','tool/offline_vits_soak_test.dart',
    ('--dart-define=EREADER_SOAK_ITERATIONS=' + $SoakIterations),
    '--reporter','expanded'
  )
}
if ($IncludeCorpus) {
  $arguments = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',
    (Join-Path $PSScriptRoot 'run-example-corpus.ps1')
  )
  if ($DeepCorpus) { $arguments += '-Deep' }
  Run-Stage 'private-book-corpus' $psExe $arguments
}
if ($NativeVoiceSourceFolder) {
  $arguments = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',
    (Join-Path $PSScriptRoot 'run-offline-voice-qualification.ps1'),
    '-SourceFolder',$NativeVoiceSourceFolder,'-AcceptNativeRisk'
  )
  if ($ExerciseNativeStop) { $arguments += '-ExerciseStop' }
  if ($RetainNativeWav) { $arguments += '-RetainWav' }
  # No -PublishSummary, even when native results succeed.
  Run-Stage 'opt-in-native-vits' $psExe $arguments
}
$failed = @($stages | Where-Object { $_.exitCode -ne 0 })
$result = if ($failed.Count -gt 0) { 'FAIL' } else { 'PASS' }
$summary = [ordered]@{
  schemaVersion=1;kind='ereader-local-verification'
  runId=$runId;sourceCommit=$commit;branch=$branch
  startedUtc=$startedUtc.ToString('o')
  finishedUtc=[DateTime]::UtcNow.ToString('o')
  result=$result;stages=@($stages.ToArray())
  publication='disabled'
  windowsBuild='not-executed'
  githubActions='not-triggered'
}
$summaryFile = Join-Path $runDir 'summary.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($summaryFile,
    (ConvertTo-Json -InputObject $summary -Depth 8),$utf8)
Write-Host ('Local report: ' + $summaryFile)
Write-Host 'Full suite detailed reports: .local-test-results\<run-id>\summary.json'
Write-Host 'Private EPUB/PDF corpus: .local-test-results\example-corpus\latest.json'
Write-Host ('Overall: ' + $result)
if ($failed.Count -gt 0) { exit 1 }
exit 0
