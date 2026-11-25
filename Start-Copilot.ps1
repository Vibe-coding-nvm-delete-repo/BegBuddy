# Launches BegBuddy Copilot (safe /chatlog watcher + DeepSeek reply drafter + Always-On-Top HUD).
# Usage:
#   .\Start-Copilot.ps1               # Launches Always-On-Top floating HUD
#   .\Start-Copilot.ps1 -Browser      # Opens in browser instead (http://127.0.0.1:4789)
param(
  [int]$Port = 4789,
  [string]$LogPath = "",
  [switch]$Browser
)

$ErrorActionPreference = "Stop"
$engine = Join-Path $PSScriptRoot "copilot\copilot.mjs"
$hud    = Join-Path $PSScriptRoot "copilot\hud.ps1"

$nodeArgs = @($engine, "--port", "$Port")
if ($LogPath) { $nodeArgs += @("--log", $LogPath) }

Write-Host "Starting BegBuddy Copilot on http://127.0.0.1:$Port ..."
$proc = Start-Process -FilePath "node" -ArgumentList $nodeArgs -PassThru -WindowStyle Hidden

try {
  $ready = $false
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 200
    try {
      Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/state" -TimeoutSec 1 | Out-Null
      $ready = $true; break
    } catch {}
  }
  if (-not $ready) { throw "BegBuddy Copilot server failed to start on port $Port." }

  if ($Browser) {
    Start-Process "http://127.0.0.1:$Port"
    Write-Host "Opened in browser. Press Enter here to stop BegBuddy Copilot."
    Read-Host | Out-Null
  } else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $hud -Port $Port
  }
} finally {
  if ($proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
}
