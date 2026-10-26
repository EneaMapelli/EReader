#Requires -Version 5.1
<#
Build a PORTABLE Windows x64 Release with its Flutter runtime and native DLLs.
No automated tests, formatters, analyzers, Git commits or pushes are run.
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\build-windows.ps1
#>
[CmdletBinding()]
param([switch]$SkipScaffold, [switch]$SkipPubGet)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root

function Find-Flutter {
    $cmd = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $options = @()
    if ($env:FLUTTER_ROOT) {
        $options += (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat')
    }
    if ($env:TEMP) {
        $options += (Join-Path $env:TEMP 'flutter\bin\flutter.bat')
    }
    if ($env:LOCALAPPDATA) {
        $options += (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat')
    }
    foreach ($candidate in $options) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw 'Flutter SDK unavailable. Install Flutter or set FLUTTER_ROOT.'
}
$flutter = Find-Flutter
function Invoke-Flutter([string[]]$arguments) {
    Write-Host ('>>> flutter ' + ($arguments -join ' ')) -ForegroundColor Cyan
    & $script:flutter @arguments
    if ($LASTEXITCODE -ne 0) {
        throw ('Flutter failed (' + $LASTEXITCODE + '): ' +
            ($arguments -join ' '))
    }
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
$git = if ($gitCmd) { $gitCmd.Source } else { $null }
$sha = 'unversioned'
$branchName = 'unknown'
$dirty = 'unknown'
if ($git) {
    $head = @(& $git rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $head.Count -gt 0) {
        $sha = ([string]$head[0]).Trim()
        $branchName = ([string](& $git branch --show-current)).Trim()
        $changes = @(& $git status --porcelain --untracked-files=no)
        $dirty = if ($changes.Count -gt 0) { 'yes' } else { 'no' }
    }
}
if ($branchName -ne 'feature/m0-flutter-foundation') {
    Write-Warning ('Current branch: ' + $branchName +
        '. Latest EReader work is feature/m0-flutter-foundation.')
}

Write-Host 'EReader portable Windows build' -ForegroundColor Green
Write-Host ('Source SHA: ' + $sha)
Invoke-Flutter @('config', '--enable-windows-desktop')

if (-not $SkipScaffold -or
    -not (Test-Path -LiteralPath 'windows\runner\CMakeLists.txt')) {
    # The Windows runner is Flutter-generated on the builder. It is not yet
    # committed to this repository; this step is required for fresh clones.
    Invoke-Flutter @('create', '--project-name', 'ereader', '--org',
        'com.example.ereader', '--platforms=windows', '.')
}
if (-not $SkipPubGet) { Invoke-Flutter @('pub', 'get') }
# Visual Studio Desktop development with C++ / Windows SDK is required.
Invoke-Flutter @('build', 'windows', '--release')

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $release -PathType Container)) {
    $release = Join-Path $root 'build\windows\runner\Release'
}
if (-not (Test-Path -LiteralPath $release -PathType Container)) {
    throw 'Flutter Windows Release folder missing.'
}
if (-not (Test-Path -LiteralPath (Join-Path $release 'ereader.exe') -PathType Leaf)) {
    throw 'Windows Release is incomplete: ereader.exe is missing.'
}
$assetsDirectory = Join-Path $release 'data\flutter_assets'
if (-not (Test-Path -LiteralPath $assetsDirectory -PathType Container)) {
    throw 'Windows Release is incomplete: data\flutter_assets is missing.'
}

$work = Join-Path $root '.local-windows-build'
$releases = Join-Path $work 'releases'
[void][IO.Directory]::CreateDirectory($releases)
$shortSha = if ($sha.Length -ge 8) { $sha.Substring(0,8) } else { $sha }
$name = 'EReader-Windows-x64-' + $shortSha
$stage = Join-Path $work 'staging'
$package = Join-Path $stage $name
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
[void][IO.Directory]::CreateDirectory($package)
# Copy the ENTIRE Flutter Release directory: plugin DLLs, Flutter runtime,
# ICU files and data folder. An .exe alone is not portable.
Get-ChildItem -LiteralPath $release -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $package -Recurse -Force
}

$guide = @'
EReader - Windows portable user test

1. Extract the whole ZIP to a writable folder, e.g. Downloads\EReader.
2. Run ereader.exe or Start-EReader.cmd.
3. Import your own EPUB, PDF or TXT. Begin with offline/system voices.
4. Test opening, page navigation, bookmarking, read aloud and audio stop.
5. This development executable is unsigned, not an official installer.
6. Keep ALL included DLLs and data/ with the EXE.
7. Cloud OpenAI requests need your API key and explicit book consent.
8. Report format, reproduction steps, Windows version and BUILD_INFO.txt SHA.
9. Never send copyrighted books, API keys or raw personal logs in a report.
10. Some devices require a Microsoft Visual C++ runtime installation.
'@
$encoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $package 'START_HERE.txt'),
    $guide, $encoding)
$nl = [Environment]::NewLine
$launcher = @(
    '@echo off'
    'cd /d "%~dp0"'
    'start "" "%~dp0ereader.exe"'
) -join $nl
[IO.File]::WriteAllText((Join-Path $package 'Start-EReader.cmd'),
    $launcher + $nl, (New-Object System.Text.ASCIIEncoding))
$buildInfo = @(
    'product=EReader Windows user test'
    ('source_commit=' + $sha)
    ('branch=' + $branchName)
    ('tracked_changes=' + $dirty)
    ('built_utc=' + [DateTime]::UtcNow.ToString('o'))
    'target=windows-x64'
    'mode=release'
    'code_signed=no'
    'automated_tests_executed_by_this_script=no'
) -join $nl
[IO.File]::WriteAllText((Join-Path $package 'BUILD_INFO.txt'),
    $buildInfo + $nl, $encoding)

$zip = Join-Path $releases ($name + '.zip')
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) {
    throw 'ZIP packaging failed.'
}
$size = (Get-Item -LiteralPath $zip).Length
if ($size -lt 1024) { throw 'Packaged ZIP is unexpectedly small.' }
Write-Host 'Windows portable Release packaged successfully.' -ForegroundColor Green
Write-Host ('EXE: ' + (Join-Path $package 'ereader.exe'))
Write-Host ('ZIP: ' + $zip)
Write-Host ('ZIP MiB: ' + [Math]::Round($size / 1MB, 1))
Write-Host 'Extract ALL files before starting. No tests were run by this script.'
if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ('zip_path=' + $zip)
}
