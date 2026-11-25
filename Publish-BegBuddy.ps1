# Self-contained packager for BegBuddy -> dist/BegBuddy-<version>.zip
# If run inside the wow-addons monorepo with ../tools/Publish-Addon.ps1, delegates to it for CurseForge upload.
param(
  [switch]$PackageOnly,
  [switch]$DryRun,
  [ValidateSet("release", "beta", "alpha")] [string]$ReleaseType = "release",
  [string[]]$GameVersions = @("1.15.9")
)
$ErrorActionPreference = "Stop"
$monoScript = Join-Path $PSScriptRoot "../tools/Publish-Addon.ps1"
if (-not $PackageOnly -and (Test-Path $monoScript)) {
  & $monoScript -Addon BegBuddy @PSBoundParameters
  return
}
$src = Join-Path $PSScriptRoot "BegBuddy"
$toc = Get-Content (Join-Path $src "BegBuddy.toc")
$ver = ($toc | Where-Object { $_ -match '^##\s*Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
if (-not $ver) { $ver = "0.0.0" }
$dist = Join-Path $PSScriptRoot "dist"
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zipPath = Join-Path $dist "BegBuddy-$ver.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $src -DestinationPath $zipPath
Write-Host "Packaged $zipPath"
