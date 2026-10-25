#Requires -Version 5.1
<#
EReader Windows test runner: execute static checks and every Flutter test.
Full logs stay in .local-test-results/ (ignored by git).
Sanitized per-test outcomes and summaries are committed and pushed to the
SAME feature/m0-flutter-foundation branch. No branch switch or force push.

Usage:
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run-all-tests.ps1 -NoPublish
#>
[CmdletBinding()]
param(
  [switch]$NoPublish,
  [switch]$SkipPubGet,
  [switch]$SkipFormat,
  [ValidateRange(1,120)][int]$TestTimeoutMinutes = 20,
  [ValidateRange(1,120)][int]$ToolTimeoutMinutes = 20
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$branch = 'feature/m0-flutter-foundation'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$git = if ($gitCmd) { $gitCmd.Source } else { "git" }
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($flutterCmd) { $flutterCmd.Source } else { "C:\Users\eneam\AppData\Local\Temp\flutter\bin\flutter.bat" }
$dartCmd = Get-Command dart -ErrorAction SilentlyContinue
$dart = if ($dartCmd) { $dartCmd.Source } else { "C:\Users\eneam\AppData\Local\Temp\flutter\bin\dart.bat" }
$sourceSha = (& $git rev-parse HEAD).Trim()
if ($sourceSha -notmatch '^[0-9a-f]{40}$') { throw 'Invalid git HEAD' }
$localBranch = (& $git branch --show-current).Trim()
$trackedChanges = @(& $git status --porcelain --untracked-files=no)
$preflightClean = $localBranch -eq $branch -and $trackedChanges.Count -eq 0
$id = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' +
  $sourceSha.Substring(0,8) + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
$raw = Join-Path (Join-Path $root '.local-test-results') $id
[void][IO.Directory]::CreateDirectory($raw)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stages = New-Object System.Collections.ArrayList
$cases = New-Object System.Collections.ArrayList
$failures = New-Object System.Collections.ArrayList
$fileRuns = New-Object System.Collections.ArrayList
$compilerLocations = New-Object System.Collections.ArrayList
$startedUtc = [DateTime]::UtcNow
$publishResult = 'disabled'

function Write-Text([string]$path, [string]$body) {
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent)) {
    [void][IO.Directory]::CreateDirectory($parent)
  }
  [IO.File]::WriteAllText($path, $body, $script:utf8)
}
function Quote-Argument([string]$argument) {
  # The cmd.exe intermediary runs flutter.bat. Deny variable expansion
  # characters. All paths come from this known repo and test filenames.
  if ($argument -match '[\r\n"%!^]') {
    throw 'Unsupported shell expansion character in path or argument'
  }
  return '"' + $argument + '"'
}
function Execute([string]$label, [string]$exe, [string[]]$arguments,
                 [int]$timeout) {
  $name = $label -replace '[^a-zA-Z0-9_.-]', '_'
  $out = Join-Path $script:raw ($name + '.stdout.log')
  $err = Join-Path $script:raw ($name + '.stderr.log')
  $start = [DateTime]::UtcNow
  $exitCode = 125
  $timedOut = $false
  Write-Host ('>>> ' + $label) -ForegroundColor Cyan
  try {
    $command = (Quote-Argument $exe) + ' ' +
      (($arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    # PowerShell 5.1 sometimes reports null for the exit code of a
    # redirected Start-Process cmd.exe even after WaitForExit(). A tiny
    # local-only cmd wrapper writes the ACTUAL child exit status to a
    # sidecar. This is vital: zero passed cases vs a failed process must
    # never be confused with the runner's unknown-status sentinel 125.
    $exitPath = Join-Path $script:raw ($name + '.exit-code')
    $wrapper = Join-Path $script:raw ($name + '.cmd')
    $quotedExitPath = Quote-Argument $exitPath
    $wrapperBody = @(
      '@echo off'
      ('call ' + $command)
      'set "child_exit=%ERRORLEVEL%"'
      ('> ' + $quotedExitPath + ' echo %child_exit%')
      'exit /b %child_exit%'
    ) -join "`r`n"
    Write-Text $wrapper ($wrapperBody + "`r`n")
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList @(
      '/d','/s','/c',(Quote-Argument $wrapper)
    ) -WorkingDirectory $script:root -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($timeout * 60000)) {
      $timedOut = $true
      & taskkill.exe /F /T /PID $p.Id 2>$null | Out-Null
      $exitCode = 124
    } else {
      # Prefer the child's sidecar exit code, not an unreliable process
      # handle property. The sidecar and wrapper stay under the ignored
      # .local-test-results directory; only the integer is published.
      $value = 0
      if ((Test-Path -LiteralPath $exitPath) -and
          [int]::TryParse(([IO.File]::ReadAllText($exitPath)).Trim(),
            [ref]$value)) {
        $exitCode = $value
      } else {
        $p.Refresh()
        if ($null -ne $p.ExitCode) { $exitCode = [int]$p.ExitCode }
      }
    }
  } catch {
    Write-Text $err 'Tool invocation failed; check local PowerShell error output.'
    if (-not (Test-Path $out)) { Write-Text $out '' }
  }
  $elapsed = [Math]::Round(([DateTime]::UtcNow - $start).TotalSeconds, 1)
  [void]$script:stages.Add([ordered]@{
    step=$label;exitCode=$exitCode;seconds=$elapsed;timedOut=$timedOut
  })
  Write-Host ("    exit {0}; {1}s" -f $exitCode,$elapsed)
  return [pscustomobject]@{ExitCode=$exitCode;TimedOut=$timedOut;Stdout=$out;Stderr=$err}
}
function Redact([string]$value) {
  if ($null -eq $value) { return '' }
  # Flutter JSON suite paths frequently use forward slashes while the
  # PowerShell checkout path uses backslashes. Normalize BEFORE redaction
  # so no Windows absolute path or private home path reaches GitHub.
  $s = $value.Replace('\', '/')
  $normalizedRoot = $script:root.Replace('\', '/')
  $s = [regex]::Replace($s, [regex]::Escape($normalizedRoot),
      '<repo>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($env:USERPROFILE) { $s = $s.Replace($env:USERPROFILE, '<home>') }
  $s = [regex]::Replace($s, '(?i)(?:sk-proj-|sk-|ghp_|github_pat_)[A-Za-z0-9_-]{8,}', '<token>')
  $s = [regex]::Replace($s, '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}', '<token>')
  $s = [regex]::Replace($s, '(?i)(?:password|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*\S+', '<secret>')
  $s = [regex]::Replace($s, '(?i)[A-Za-z]:\\Users\\[^\\\s]+', '<home>')
  $s = $s.Replace([char]13, ' ').Replace([char]10, ' ')
  $s = $s.Replace('|', '/')
  if ($s.Length -gt 220) { $s = $s.Substring(0,220) }
  return $s
}
function Collect-CompileLocations([string]$path, [string]$testFile) {
  # Extract ONLY file:line:column and a fixed failure kind. Never push
  # exception body, Expected/Actual text, URLs, credentials or local paths.
  if (-not (Test-Path -LiteralPath $path)) { return }
  $seen = @{}
  foreach ($line in [IO.File]::ReadLines($path)) {
    foreach ($match in [regex]::Matches(
      $line, '(?i)(?<![a-z0-9_])((?:lib|test)[/\\][a-z0-9_./\\-]+\.dart):(\d+):(\d+)')) {
      $relative = $match.Groups[1].Value.Replace('\','/')
      if ($relative.Contains('..') -or $relative.Length -gt 180) { continue }
      $lineNumber = [int]$match.Groups[2].Value
      $columnNumber = [int]$match.Groups[3].Value
      if ($lineNumber -lt 1 -or $columnNumber -lt 1) { continue }
      $key = $relative + ':' + $lineNumber + ':' + $columnNumber
      if ($seen.ContainsKey($key)) { continue }
      $seen[$key] = $true
      [void]$script:compilerLocations.Add([ordered]@{
        testFile=(Redact $testFile);file=$relative
        line=$lineNumber;column=$columnNumber
        kind='compile_or_load_location'
      })
      if ($seen.Count -ge 80) { return }
    }
  }
}

function Read-TestEvents([string]$log, [string]$defaultFile,
                         [string]$runLabel) {
  $suites = @{}
  $tests = @{}
  $problem = @{}
  if (-not (Test-Path -LiteralPath $log)) { return }
  foreach ($line in [IO.File]::ReadLines($log)) {
    if (-not $line.StartsWith('{')) { continue }
    try { $e = $line | ConvertFrom-Json -ErrorAction Stop }
    catch { continue }
    switch ([string]$e.type) {
      'suite' {
        $suites[[string]$e.suite.id] = [string]$e.suite.path
      }
      'testStart' {
        if ($null -eq $e.test) { break }
        $id = [string]$e.test.id
        $source = $defaultFile
        $suiteId = [string]$e.test.suiteID
        if ($suites.ContainsKey($suiteId)) { $source = $suites[$suiteId] }
        $source = $source.Replace('\', '/')
        $rootUnix = $script:root.Replace('\', '/')
        if ($source.StartsWith($rootUnix + '/',
            [StringComparison]::OrdinalIgnoreCase)) {
          $source = $source.Substring($rootUnix.Length + 1)
        }
        $tests[$id] = [ordered]@{
          file=(Redact $source.Replace('\','/'))
          name=(Redact ([string]$e.test.name))
          status='incomplete';issue='';run=$runLabel
        }
      }
      'error' {
        $key = [string]$e.testID
        if (-not $problem.ContainsKey($key)) {
          $category = 'runtime'
          if ([string]$e.error -match '(?i)timed out|TimeoutException') {
            $category = 'timeout'
          } elseif ($e.isFailure -eq $true) {
            $category = 'assertion'
          } elseif ([string]$e.error -match '(?i)compil|syntax|Error:') {
            $category = 'compile_or_runtime'
          }
          $problem[$key] = $category
        }
      }
      'testDone' {
        $key = [string]$e.testID
        if (-not $tests.ContainsKey($key)) { break }
        if ($e.hidden -eq $true) { $tests.Remove($key); break }
        $tests[$key].status = [string]$e.result
        if ($e.skipped -eq $true) { $tests[$key].status = 'skipped' }
        if ($problem.ContainsKey($key)) {
          $tests[$key].issue = $problem[$key]
        }
      }
    }
  }
  foreach ($test in $tests.Values) {
    [void]$script:cases.Add($test)
    if ($test.status -ne 'success' -and $test.status -ne 'skipped') {
      [void]$script:failures.Add($test)
    }
  }
}
function Json([object]$data) {
  if ($null -eq $data) { return '[]' }
  return ConvertTo-Json -InputObject $data -Depth 12
}

$version = Execute 'flutter-version' $flutter @('--version') $ToolTimeoutMinutes
$dartVersion = Execute 'dart-version' $dart @('--version') $ToolTimeoutMinutes
if (-not $SkipPubGet) {
  $pub = Execute 'pub-get' $flutter @('pub','get') $ToolTimeoutMinutes
}
if (-not $SkipFormat) {
  $format = Execute 'format-check' $dart @(
    'format','--output=none','--set-exit-if-changed','lib','test'
  ) $ToolTimeoutMinutes
}
$analyze = Execute 'flutter-analyze' $flutter @('analyze','--no-pub') $ToolTimeoutMinutes
$allFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'test') -Recurse -File -Filter '*_test.dart' | Sort-Object FullName)
$global = Execute 'flutter-test-all' $flutter @(
  'test','--reporter','json','--no-pub'
) $TestTimeoutMinutes
Collect-CompileLocations $global.Stdout '<full_suite>'
Collect-CompileLocations $global.Stderr '<full_suite>'
if ($global.ExitCode -eq 0) {
  Read-TestEvents $global.Stdout '' 'full_suite'
} else {
  Write-Host 'Combined run failed. Running each test file for complete isolation.' -ForegroundColor Yellow
  for ($i = 0; $i -lt $allFiles.Count; $i++) {
    $relative = $allFiles[$i].FullName.Substring($root.Length).TrimStart('\','/').Replace('\','/')
    $name = ('individual-{0:D4}' -f ($i+1))
    Write-Host ("[{0}/{1}] {2}" -f ($i+1), $allFiles.Count, $relative)
    $one = Execute $name $flutter @(
      'test','--reporter','json','--no-pub',$relative
    ) $TestTimeoutMinutes
    $before = $cases.Count
    Read-TestEvents $one.Stdout $relative $name
    Collect-CompileLocations $one.Stdout $relative
    Collect-CompileLocations $one.Stderr $relative
    $parsed = $cases.Count - $before
    [void]$fileRuns.Add([ordered]@{
      file=$relative;exitCode=$one.ExitCode;timedOut=$one.TimedOut
      parsedCases=$parsed
    })
    if ($parsed -eq 0) {
      $record = [ordered]@{
        file=$relative;name='<suite could not load>'
        status='error'
        issue=$(if ($one.TimedOut) {'timeout'} else {'compile_or_runner_error'})
        run=$name
      }
      [void]$cases.Add($record)
      [void]$failures.Add($record)
    }
  }
}
$pass = @($cases | Where-Object { $_.status -eq 'success' }).Count
$fail = @($cases | Where-Object { $_.status -eq 'failure' }).Count
$errorCount = @($cases | Where-Object {
  $_.status -eq 'error' -or $_.status -eq 'incomplete'
}).Count
$skipped = @($cases | Where-Object { $_.status -eq 'skipped' }).Count
$brokenStages = @($stages | Where-Object { $_.exitCode -ne 0 }).Count
$outcome = if ($allFiles.Count -eq 0 -or $cases.Count -eq 0 -or
    $brokenStages -gt 0 -or $fail -gt 0 -or $errorCount -gt 0) {
  'FAIL'
} else { 'PASS' }
# Analyzer lines publish only diagnostic headers; full stdout/stderr is local.
$analyzerIssues = New-Object System.Collections.ArrayList
foreach ($path in @($analyze.Stdout,$analyze.Stderr)) {
  if (-not (Test-Path $path)) { continue }
  foreach ($line in [IO.File]::ReadLines($path)) {
    if ($line -match '^\s*(error|warning|info)\s+[-\u2022]' -or
        $line -match 'issues? found') {
      [void]$analyzerIssues.Add((Redact $line))
      if ($analyzerIssues.Count -ge 200) { break }
    }
  }
}
$totals = [ordered]@{
  passed=$pass;failed=$fail;errors=$errorCount;skipped=$skipped
  testFilesDiscovered=$allFiles.Count;testOutcomesParsed=$cases.Count
}
$summary = [ordered]@{
  runId=$id;sourceCommit=$sourceSha;branch=$localBranch
  startedUtc=$startedUtc.ToString('o')
  completedUtc=[DateTime]::UtcNow.ToString('o')
  result=$outcome;totals=$totals;stages=@($stages.ToArray())
  isolatedFileRuns=@($fileRuns.ToArray())
  compileLocations=@($compilerLocations.ToArray())
  analyzerIssues=@($analyzerIssues.ToArray())
  localOnlyRawLogDirectory='.local-test-results/' + $id
  note='Raw logs are local-only; no user file contents or secrets are published.'
}
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# EReader test report')
$md.Add('')
$md.Add(('* Result: **{0}**' -f $outcome))
$md.Add(('* Source: {0} ({1})' -f $sourceSha,$localBranch))
$md.Add(('* Run: {0}' -f $id))
$md.Add(('* Cases: {0} passed, {1} failed, {2} errors, {3} skipped' -f $pass,$fail,$errorCount,$skipped))
$md.Add(('* Test files discovered: {0}' -f $allFiles.Count))
$md.Add('')
$md.Add('## All commands')
$md.Add('| Command | Exit | Seconds | Timeout |')
$md.Add('|---|---:|---:|---|')
foreach ($step in $stages) {
  $md.Add(('| {0} | {1} | {2} | {3} |' -f
    $step.step,$step.exitCode,$step.seconds,$step.timedOut))
}
$md.Add('')
$md.Add('## Failures (complete list in JSON)')
$md.Add('| Test file | Test case | Type |')
$md.Add('|---|---|---|')
foreach ($row in @($failures.ToArray()) | Select-Object -First 120) {
  $md.Add(('| {0} | {1} | {2} |' -f $row.file,$row.name,$row.issue))
}
$md.Add('')
$md.Add('## Source locations of compilation/load errors (safe metadata)')
$md.Add('| Test file | Source file | Line | Column |')
$md.Add('|---|---|---:|---:|')
foreach ($loc in @($compilerLocations.ToArray()) | Select-Object -First 100) {
  $md.Add(('| {0} | {1} | {2} | {3} |' -f
    $loc.testFile,$loc.file,$loc.line,$loc.column))
}
$md.Add('')
$md.Add('## Analyzer diagnostics')
foreach ($msg in @($analyzerIssues | Select-Object -First 100)) {
  $md.Add('- ' + $msg)
}
$md.Add('')
$md.Add('Raw stdout/stderr logs are saved locally and are never committed.')
$markdown = $md -join [Environment]::NewLine
$metaJson = Json $summary
$caseJson = Json @($cases.ToArray())
$failJson = Json @($failures.ToArray())
Write-Text (Join-Path $raw 'latest.md') $markdown
Write-Text (Join-Path $raw 'summary.json') $metaJson
Write-Text (Join-Path $raw 'cases.json') $caseJson
Write-Text (Join-Path $raw 'failures.json') $failJson
Write-Host ('Raw logs and report: ' + $raw)
if (-not $NoPublish) {
  try {
    if (-not $preflightClean) {
      throw 'Current branch differs, or tracked worktree/index was dirty at launch.'
    }
    $origin = (& $git remote get-url origin).Trim()
    if ($origin -notmatch '(?i)github\.com[:/]EneaMapelli/EReader(?:\.git)?$') {
      throw 'Origin does not point to the expected private EReader repository.'
    }
    if ((& $git branch --show-current).Trim() -ne $branch) {
      throw 'Branch changed while running.'
    }
    $published = Join-Path $root 'test-results'
    $runFolder = Join-Path $published 'runs'
    [void][IO.Directory]::CreateDirectory($runFolder)
    $rel = @(
      "test-results/runs/$id.md",
      "test-results/runs/$id.json",
      "test-results/runs/$id-cases.json",
      "test-results/runs/$id-failures.json",
      'test-results/latest.md',
      'test-results/latest.json',
      'test-results/latest-cases.json',
      'test-results/latest-failures.json'
    )
    Write-Text (Join-Path $runFolder ($id + '.md')) $markdown
    Write-Text (Join-Path $runFolder ($id + '.json')) $metaJson
    Write-Text (Join-Path $runFolder ($id + '-cases.json')) $caseJson
    Write-Text (Join-Path $runFolder ($id + '-failures.json')) $failJson
    Write-Text (Join-Path $published 'latest.md') $markdown
    Write-Text (Join-Path $published 'latest.json') $metaJson
    Write-Text (Join-Path $published 'latest-failures.json') $failJson
    Write-Text (Join-Path $published 'latest-cases.json') $caseJson
    & $git add -- @rel
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage report files' }
    & $git commit -m ("test(results): Windows $outcome $id")
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit test results' }
    # No force push or alternate branch. Concurrent changes lead to an
    # ordinary non-fast-forward rejection and reports remain local.
    & $git push origin ("HEAD:refs/heads/$branch")
    if ($LASTEXITCODE -ne 0) { throw 'Push failed; verify Git credentials or fetch updates' }
    $publishResult = 'same_branch_pushed'
    Write-Host 'Summary and per-test results pushed to the existing feature branch.' -ForegroundColor Green
  } catch {
    $publishResult = 'failed_raw_results_kept_locally'
    Write-Warning ('Could not automatically publish: ' + $_.Exception.Message)
    Write-Warning ('Results are still available under ' + $raw)
    Write-Warning ('To publish this completed run without retesting: ' +
      'powershell -NoProfile -ExecutionPolicy Bypass -File ' +
      '.\tool\publish-local-test-report.ps1 -RunId ' + $id)
  }
}
Write-Host ("Result {0}; pass={1}, fail={2}, errors={3}, skipped={4}; upload={5}" -f
  $outcome,$pass,$fail,$errorCount,$skipped,$publishResult)
if ($outcome -eq 'FAIL') { exit 1 }
if ($publishResult -eq 'failed_raw_results_kept_locally') { exit 2 }
exit 0
