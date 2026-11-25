# A5 developer smoke launcher for the isolated two-camera prototype.
# Usage:
#   .\tools\Start-A5DualViewPreview.ps1 -GodotPath "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
# or set the GODOT environment variable to the absolute Godot 4.7.2 executable.
# This NEVER replaces the game's main scene or modifies a save.
param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scene = "res://game/scenes/prototypes/dual_view_preview.tscn"
if (-not $GodotPath) { $GodotPath = $env:GODOT }
if (-not $GodotPath) {
    $candidate = Get-Command "godot" -ErrorAction SilentlyContinue
    if (-not $candidate) { $candidate = Get-Command "godot4" -ErrorAction SilentlyContinue }
    if ($candidate) { $GodotPath = $candidate.Source }
}
if (-not $GodotPath) {
    throw "Godot 4.7.2 not found. Pass -GodotPath or set GODOT to the installed engine."
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    $candidate = Get-Command $GodotPath -ErrorAction SilentlyContinue
    if (-not $candidate) { throw "Invalid Godot executable: $GodotPath" }
}

Write-Host "A5 dual-view preview: $scene"
Write-Host "WASD/arrows move, Caps Lock changes view, mouse looks in FPS, Esc releases cursor."
Write-Host "This is an isolated tech preview, NOT the full playable game."
& $GodotPath --path $project $scene
if ($LASTEXITCODE -ne 0) { throw "Godot preview exited with code $LASTEXITCODE" }
