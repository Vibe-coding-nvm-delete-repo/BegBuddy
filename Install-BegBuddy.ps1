# Self-contained installer: copies BegBuddy into local WoW Classic Era / Hardcore / Forever AddOns folders.
param(
  [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft",
  [string[]]$Flavors = @("_classic_era_", "_forever_", "_classic_beta_")
)
$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "BegBuddy"
if (-not (Test-Path (Join-Path $src "BegBuddy.toc"))) {
  throw "BegBuddy.toc not found under $src"
}
$installed = 0
foreach ($flavor in $Flavors) {
  $addonsDir = Join-Path $WowRoot "$flavor\Interface\AddOns"
  if (Test-Path $addonsDir) {
    $dest = Join-Path $addonsDir "BegBuddy"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $src "*") -Destination $dest -Recurse -Force
    Write-Host "Installed BegBuddy -> $dest"
    $installed++
  }
}
if ($installed -eq 0) {
  Write-Warning "No WoW AddOns folders found under $WowRoot. Pass -WowRoot <path>."
}
