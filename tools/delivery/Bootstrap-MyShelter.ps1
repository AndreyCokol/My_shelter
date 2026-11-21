# One-time MyShelter Windows bootstrap.
# Installer/updater source is PINNED to a GitHub commit verified by CI.
[CmdletBinding()]
param(
    [switch]$NoScheduledTask,
    [switch]$NoDesktopShortcut
)
$ErrorActionPreference = 'Stop'
$commit = 'f517117789b22ba57500e5b061c272498b5e4c6c'
$base = "https://raw.githubusercontent.com/AndreyCokol/My_shelter/$commit/tools/delivery"
$temp = Join-Path $env:TEMP ('MyShelter-bootstrap-' + [Guid]::NewGuid().ToString('N'))
New-Item -Path $temp -ItemType Directory -Force | Out-Null
try {
    foreach ($file in @('windows_updater.py', 'Install-MyShelter.ps1')) {
        Invoke-WebRequest -Uri "$base/$file" -OutFile (Join-Path $temp $file) -UseBasicParsing
    }
    $params = @{}
    if ($NoScheduledTask) { $params.NoScheduledTask = $true }
    if ($NoDesktopShortcut) { $params.NoDesktopShortcut = $true }
    & (Join-Path $temp 'Install-MyShelter.ps1') @params
    if (-not $?) { throw 'Bootstrap installation failed' }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
