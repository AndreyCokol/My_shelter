# Private owner QA first-install. No admin, no public GitHub Release.
# The archive and two launcher source files must live next to this script.
[CmdletBinding()]
param(
  [string]$BundleDir = $PSScriptRoot,
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MyShelter'),
  [switch]$NoScheduledTask,
  [switch]$NoDesktopShortcut
)
$ErrorActionPreference = 'Stop'
$archive = Join-Path $BundleDir 'MyShelter-Windows-x64.zip'
$manifestPath = Join-Path $BundleDir 'manifest.json'
$bootstrap = Join-Path $BundleDir 'Install-MyShelter.ps1'
$updaterSource = Join-Path $BundleDir 'windows_updater.py'
foreach ($path in @($archive, $manifestPath, $bootstrap, $updaterSource)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required QA bundle file missing: $path" }
}
$m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($m.schema -ne 1 -or $m.application -cne 'MyShelter' -or $m.channel -cne 'preview' -or
    $m.source_sha -cnotmatch '^[0-9a-f]{40}$' -or
    $m.archive_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
    $m.exe_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
    $m.archive_size -lt 100 -or $m.archive_size -gt 536870912 -or
    $m.exe_size -lt 100 -or $m.exe_size -gt 536870912) {
  throw 'Invalid signed-off QA candidate manifest fields (not an independently signed manifest)'
}
$archiveInfo = Get-Item -LiteralPath $archive
if ($archiveInfo.Length -ne $m.archive_size -or
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.archive_sha256) {
  throw 'QA archive checksum/size mismatch; no state was changed'
}
$versions = Join-Path $InstallDir 'versions'
$version = Join-Path $versions $m.source_sha
$staging = Join-Path $versions ($m.source_sha + '.staging-local')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($archive)
try {
  $entries = @($z.Entries)
  $names = @($entries | ForEach-Object { $_.FullName })
  if ($entries.Count -ne 2 -or ($names | Select-Object -Unique).Count -ne 2 -or
      $names -notcontains 'MyShelter.exe' -or $names -notcontains 'README.txt') {
    throw 'Unexpected QA archive ZIP membership'
  }
  foreach ($entry in $entries) {
    if ($entry.FullName -notin @('MyShelter.exe', 'README.txt')) { throw "Unsafe ZIP entry: $($entry.FullName)" }
    if ($entry.FullName -ceq 'MyShelter.exe' -and $entry.Length -ne $m.exe_size) { throw 'EXE size differs from manifest' }
    if ($entry.Length -gt 536870912) { throw 'Oversized ZIP member' }
  }
  New-Item -ItemType Directory -Path $versions -Force | Out-Null
  if (-not (Test-Path -LiteralPath $version)) {
    if (Test-Path -LiteralPath $staging) { throw 'Unexpected stale staging directory; investigate before proceeding' }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
      foreach ($entry in $entries) {
        $dest = Join-Path $staging $entry.FullName
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $false)
      }
      $exe = Join-Path $staging 'MyShelter.exe'
      if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.exe_sha256) {
        throw 'Extracted executable checksum mismatch'
      }
      [System.IO.Directory]::Move($staging, $version)
    } catch {
      if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
      throw
    }
  } else {
    $exe = Join-Path $version 'MyShelter.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
        (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $m.exe_sha256) {
      throw 'Existing version directory contains an unexpected executable; refusing overwrite'
    }
  }
} finally { $z.Dispose() }

# Install launcher as a separate phase: failure here does NOT erase the verified game version.
$installArgs = @{ InstallDir = $InstallDir }
if ($NoScheduledTask) { $installArgs.NoScheduledTask = $true }
if ($NoDesktopShortcut) { $installArgs.NoDesktopShortcut = $true }
& $bootstrap @installArgs
if (-not $?) { throw 'Launcher installation failed' }
$statePath = Join-Path $InstallDir 'state.json'
$prior = $null
if (Test-Path -LiteralPath $statePath) { $prior = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json }
if ($null -ne $prior -and $prior.active_sha -ceq $m.source_sha) {
  Write-Host 'This exact QA candidate is already installed'
} else {
  $previous = $null
  if ($null -ne $prior -and $prior.active_sha -match '^[0-9a-f]{40}$') {
    $priorExe = Join-Path $versions (Join-Path $prior.active_sha 'MyShelter.exe')
    if (Test-Path -LiteralPath $priorExe -PathType Leaf) { $previous = $prior.active_sha }
  }
  $newState = @{
    active_sha = $m.source_sha
    previous_sha = $previous
    channel = 'preview'
    published_at = $m.published_at
    updates_paused = $false
  }
  $newJson = ConvertTo-Json -InputObject $newState -Depth 4
  $stateTemp = Join-Path $InstallDir 'state.json.first-install.tmp'
  [System.IO.File]::WriteAllText($stateTemp, $newJson, (New-Object System.Text.UTF8Encoding($false)))
  if (Test-Path -LiteralPath $statePath) {
    [System.IO.File]::Replace($stateTemp, $statePath, (Join-Path $InstallDir 'state.json.before-qa.bak'))
  } else { [System.IO.File]::Move($stateTemp, $statePath) }
}
Write-Host 'MY SHELTER OWNER QA FIRST INSTALL: PASS'
Write-Host "Installed source SHA: $($m.source_sha)"
Write-Host "Launch game: $(Join-Path $InstallDir 'MyShelter.cmd')"
Write-Host 'This is a QA baseline, not owner-approved G0/G4. Do not distribute publicly.'
