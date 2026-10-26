#Requires -Version 5.1
<#
Run real sherpa-onnx VITS speech inference with an already-installed local
voice. This requires an explicit native-risk acknowledgement; it does not
download a model, transmit text, play sound, or enable the engine in the UI.
Only fixed Italian/English test phrases are synthesized. WAVs are removed
unless -RetainWav is explicitly provided.

Example:
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-offline-voice-qualification.ps1 -ModelsDirectory "C:\path\to\offline-voices" -PackId it-voice -AcceptNativeRisk
Add -PublishSummary to commit ONLY a sanitized JSON result on the same branch.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ModelsDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9_-]{1,63}$')][string]$PackId,
  [switch]$AcceptNativeRisk,
  [switch]$RetainWav,
  [switch]$ExerciseStop,
  [switch]$PublishSummary
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
if (-not $AcceptNativeRisk) {
  throw 'Native ONNX qualification requires -AcceptNativeRisk.'
}
$dir = Get-Item -LiteralPath $ModelsDirectory -ErrorAction Stop
if (-not $dir.PSIsContainer -or
    ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  throw 'ModelsDirectory must be an existing non-link local directory.'
}
$dartCommand = Get-Command dart -ErrorAction SilentlyContinue
$dart = if ($dartCommand) { $dartCommand.Source } else { $null }
if (-not $dart -and $env:FLUTTER_ROOT) {
  $candidate = Join-Path $env:FLUTTER_ROOT 'bin\dart.bat'
  if (Test-Path -LiteralPath $candidate) { $dart = $candidate }
}
if (-not $dart -and $env:TEMP) {
  $candidate = Join-Path $env:TEMP 'flutter\bin\dart.bat'
  if (Test-Path -LiteralPath $candidate) { $dart = $candidate }
}
if (-not $dart) { throw 'Dart SDK not found; set FLUTTER_ROOT or PATH.' }
$arguments = @('run','tool/qualify_offline_voice.dart',
  '--models-dir',$dir.FullName,'--pack-id',$PackId,'--accept-native-risk')
if ($RetainWav) { $arguments += '--retain-wav' }
if ($ExerciseStop) { $arguments += '--exercise-stop' }
$resultsDir = Join-Path $root '.local-test-results\offline-voice-qualification'
[void][IO.Directory]::CreateDirectory($resultsDir)
$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$output = Join-Path $resultsDir ($timestamp + '-' + $PackId + '.json')
# This command prints sanitized JSON to stdout. Native diagnostics sent to
# stderr stay on the developer's local machine, never copied to GitHub.
& $dart @arguments | Out-File -LiteralPath $output -Encoding utf8
$code = $LASTEXITCODE
$payload = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
if ($null -eq $payload -or $payload.kind -ne 'offline-vits-local-qualification') {
  throw 'Qualification did not return the expected result schema.'
}
Write-Host ('Native qualification status: ' + $payload.status)
Write-Host ('Local sanitized report: ' + $output)
if ($PublishSummary) {
  $gitCmd = Get-Command git -ErrorAction Stop
  $git = $gitCmd.Source
  $branch = 'feature/m0-flutter-foundation'
  $actual = (& $git branch --show-current).Trim()
  $origin = (& $git remote get-url origin).Trim()
  $dirty = @(& $git status --porcelain --untracked-files=no)
  if ($actual -ne $branch -or
      $origin -notmatch '(?i)github\.com[:/]EneaMapelli/EReader(?:\.git)?$' -or
      $dirty.Count -ne 0) {
    throw 'Publishing requires the clean original EReader feature branch.'
  }
  $published = Join-Path $root 'test-results\offline-voice-qualification-latest.json'
  # Whitelist the numeric and small status fields. Never publish paths,
  # voice audio, files, native error details or user-provided phrases.
  $properties = $payload.PSObject.Properties
  $locale = if ($properties['locale']) { [string]$payload.locale } else { '' }
  $stopOutcome = if ($properties['stopOutcome']) {
    [string]$payload.stopOutcome
  } else { 'not-run' }
  $stopSettleMs = if ($properties['stopSettleMs']) {
    [int]$payload.stopSettleMs
  } else { -1 }
  $failureStage = if ($properties['failureStage']) {
    [string]$payload.failureStage
  } else { '' }
  $safe = [ordered]@{
    schemaVersion=1
    kind='offline-vits-local-qualification'
    sourceCommit=(& $git rev-parse HEAD).Trim()
    runAtUtc=$timestamp
    status=[string]$payload.status
    locale=$locale
    samples=@($payload.samples | ForEach-Object {
      [ordered]@{
        sample=[int]$_.sample
        synthesisMs=[int]$_.synthesisMs
        durationMs=[int]$_.audio.durationMs
        sampleRate=[int]$_.audio.sampleRate
        processRssMiB=[int]$_.processRssMiB
        realTimeFactor=[double]$_.realTimeFactor
      }
    })
    stopOutcome=$stopOutcome
    stopSettleMs=$stopSettleMs
    failureStage=$failureStage
  }
  $json = ConvertTo-Json -InputObject $safe -Depth 5
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($published, $json, $encoding)
  & $git add -- 'test-results/offline-voice-qualification-latest.json'
  if ($LASTEXITCODE -ne 0) { throw 'Could not stage the sanitized report.' }
  & $git commit -m 'test(m3): publish sanitized offline voice qualification'
  if ($LASTEXITCODE -ne 0) { throw 'Could not commit the sanitized report.' }
  & $git push origin ("HEAD:refs/heads/$branch")
  if ($LASTEXITCODE -ne 0) {
    throw 'Push rejected; summary commit remains local. No force push used.'
  }
}
if ($code -ne 0 -or $payload.status -ne 'PASS') {
  throw 'Offline native qualification FAILED; see local report.'
}
Write-Host 'Offline native qualification passed; review audio by ear if retained.'
