# One-time per-user installation. No administrator rights, no running browser required.
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MyShelter'),
    [switch]$NoScheduledTask,
    [switch]$NoDesktopShortcut
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'windows_updater.py'
if (-not (Test-Path -LiteralPath $source)) {
    throw 'windows_updater.py must be in the same directory as this installer.'
}
& py -3 -c 'import sys; assert sys.version_info >= (3, 12)'
if ($LASTEXITCODE -ne 0) {
    throw 'Python 3.12+ with Windows py launcher is required.'
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $InstallDir 'windows_updater.py') -Force

@'
@echo off
py -3 "%~dp0windows_updater.py" --root "%~dp0" launch %*
'@ | Set-Content -LiteralPath (Join-Path $InstallDir 'MyShelter.cmd') -Encoding Ascii

@'
@echo off
py -3 "%~dp0windows_updater.py" --root "%~dp0" update %*
'@ | Set-Content -LiteralPath (Join-Path $InstallDir 'UpdateMyShelter.cmd') -Encoding Ascii

@'
@echo off
py -3 "%~dp0windows_updater.py" --root "%~dp0" rollback
'@ | Set-Content -LiteralPath (Join-Path $InstallDir 'RollbackMyShelter.cmd') -Encoding Ascii

if (-not $NoDesktopShortcut) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MyShelter.lnk')
    )
    $shortcut.TargetPath = (Join-Path $InstallDir 'MyShelter.cmd')
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description = 'MyShelter - local installed version, updates checked in background'
    $shortcut.Save()
}
if (-not $NoScheduledTask) {
    try {
        $taskName = 'MyShelter Preview Updates'
        $updateCmd = Join-Path $InstallDir 'UpdateMyShelter.cmd'
        $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/d /c ""' + $updateCmd + '""')
        $trigger = New-ScheduledTaskTrigger -Daily -At '12:00'
        $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Host 'Daily update check installed (runs only when signed in).'
    } catch {
        Write-Warning ('Could not register scheduled update: ' + $_.Exception.Message)
        Write-Host 'The game still checks for updates every time you launch it.'
    }
}
Write-Host "MyShelter installed at: $InstallDir"
Write-Host 'Start from desktop shortcut or MyShelter.cmd.'
Write-Host 'First run requires an approved GitHub preview release; no release is published by this installer.'
Write-Host 'RollbackMyShelter.cmd restores prior build and pauses updates; UpdateMyShelter.cmd update --force resumes.'
