#Requires -Version 5.1
<#
Creates a local EReader voice-pack.json for an already obtained VITS model.
This is a checksum utility, NOT a model download, authenticity check, voice
license grant, native inference test or automatic TTS activation.
Example:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\prepare-offline-voice-pack.ps1 -SourceDirectory C:\voices\italian -Id it-voice -DisplayName 'Italian voice' -Locale it-IT -LicenseId MIT
The source must contain model.onnx, tokens.txt, and optionally a strictly
bounded espeak-ng-data/ tree. The manifest is never overwritten.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SourceDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9_-]{1,63}$')][string]$Id,
  [Parameter(Mandatory=$true)][ValidateLength(1,120)][string]$DisplayName,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z]{2,8}([-_][a-zA-Z0-9]{2,8})?$')][string]$Locale,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.()+-]{0,79}$')][string]$LicenseId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Get-Item -LiteralPath $SourceDirectory -ErrorAction Stop
if (-not $source.PSIsContainer -or
    ($source.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  throw 'Voice source must be a regular local directory (not a link).'
}
if ([string]::IsNullOrWhiteSpace($DisplayName)) {
  throw 'DisplayName cannot be blank.'
}
$root = $source.FullName.TrimEnd('\')
if ($source.FullName -eq [IO.Path]::GetPathRoot($source.FullName)) {
  throw 'Choose a dedicated model folder, not an entire drive.'
}
$metadata = Join-Path $root 'voice-pack.json'
if (Test-Path -LiteralPath $metadata) {
  throw 'voice-pack.json already exists; review it instead of overwriting.'
}
$model = Join-Path $root 'model.onnx'
$tokens = Join-Path $root 'tokens.txt'
function Require-VoiceFile([string]$path, [long]$max) {
  $file = Get-Item -LiteralPath $path -ErrorAction Stop
  if ($file.PSIsContainer -or
      ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
      $file.Length -lt 1 -or $file.Length -gt $max) {
    throw 'Model pack contains an invalid or oversized required file.'
  }
  return $file
}
[void](Require-VoiceFile $model (600MB))
[void](Require-VoiceFile $tokens (4MB))
$resources = New-Object System.Collections.ArrayList
$phonemizerBytes = [long]0
$files = @(Get-ChildItem -LiteralPath $root -Force -Recurse)
foreach ($item in $files) {
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Symbolic links and junctions are not supported.'
  }
  $relative = $item.FullName.Substring($root.Length + 1).Replace('\','/')
  if ($item.PSIsContainer) {
    if ($relative -ne 'espeak-ng-data' -and
        -not $relative.StartsWith('espeak-ng-data/')) {
      throw 'Unexpected subdirectory in voice pack.'
    }
    continue
  }
  if ($relative -eq 'model.onnx' -or $relative -eq 'tokens.txt') {
    continue
  }
  if (-not $relative.StartsWith('espeak-ng-data/')) {
    throw 'Unexpected extra file in voice pack.'
  }
  if ($relative.Length -gt 180 -or $item.Length -lt 1 -or
      $item.Length -gt 8MB) {
    throw 'Phonemizer file path or size is invalid.'
  }
  foreach ($part in $relative.Split('/')) {
    if ($part -notmatch '^[A-Za-z0-9._-]+$' -or
        $part -eq '.' -or $part -eq '..' -or
        $part.EndsWith('.') -or
        $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') {
      throw 'Unsafe phonemizer file path.'
    }
  }
  $phonemizerBytes += $item.Length
  if ($phonemizerBytes -gt 64MB -or $resources.Count -ge 2048) {
    throw 'Phonemizer file count or cumulative size exceeds budget.'
  }
  [void]$resources.Add([ordered]@{
    relativePath=$relative
    sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  })
}
# Ensure the source has no empty/unlisted phonemizer directories.
# The Flutter importer requires an exact file and directory inventory.
$expectedFolders = @{}
foreach ($resource in $resources) {
  $parts = $resource['relativePath'].Split('/')
  for ($index = 1; $index -lt $parts.Length; $index++) {
    $folder = ($parts[0..($index - 1)] -join '/')
    $expectedFolders[$folder] = $true
  }
}
foreach ($item in $files) {
  if (-not $item.PSIsContainer) { continue }
  $relative = $item.FullName.Substring($root.Length + 1).Replace('\','/')
  if (-not $expectedFolders.ContainsKey($relative)) {
    throw 'Empty or unlisted phonemizer subdirectory in voice pack.'
  }
}
$orderedResources = @($resources | Sort-Object -Property {
  $_['relativePath']
})
$manifest = [ordered]@{
  version=1
  id=$Id
  displayName=$DisplayName
  locale=$Locale
  licenseId=$LicenseId
  modelSha256=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash.ToLowerInvariant()
  tokensSha256=(Get-FileHash -LiteralPath $tokens -Algorithm SHA256).Hash.ToLowerInvariant()
  phonemizerResources=@($orderedResources)
}
$json = ConvertTo-Json -InputObject $manifest -Depth 6
$utf8 = New-Object System.Text.UTF8Encoding($false)
# CreateNew prevents overwriting another process's manifest.
$stream = [IO.File]::Open(
  $metadata, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
  [IO.FileShare]::None
)
try {
  $writer = New-Object System.IO.StreamWriter($stream, $utf8)
  try {
    $writer.Write($json)
    $writer.Flush()
  } finally {
    $writer.Dispose()
  }
} finally {
  $stream.Dispose()
}
Write-Host ('Created local manifest for ' + $Id) -ForegroundColor Green
Write-Host ('Files hashed: ' + (2 + $orderedResources.Count))
Write-Host 'Review the license and publisher independently before importing.'
