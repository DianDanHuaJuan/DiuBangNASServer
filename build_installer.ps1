$scriptDir = Join-Path $PSScriptRoot "packaging\windows"
& (Join-Path $scriptDir "build_installer.ps1") @args
