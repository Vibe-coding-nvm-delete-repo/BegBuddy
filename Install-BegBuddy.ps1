# Copies BegBuddy into the Hardcore (Classic Era) and Forever beta AddOns folders and checks every file by hash.
& (Join-Path $PSScriptRoot '../tools/Install-Addon.ps1') -Src (Join-Path $PSScriptRoot 'BegBuddy')
