# Packages BegBuddy into dist/BegBuddy-<version>.zip and uploads it to CurseForge. Switches and needs: tools/Publish-Addon.ps1.
param([switch]$PackageOnly, [switch]$DryRun, [ValidateSet("release", "beta", "alpha")] [string]$ReleaseType = "release",
  [string[]]$GameVersions = @("1.15.9"))
& (Join-Path $PSScriptRoot '../tools/Publish-Addon.ps1') -Addon BegBuddy @PSBoundParameters
