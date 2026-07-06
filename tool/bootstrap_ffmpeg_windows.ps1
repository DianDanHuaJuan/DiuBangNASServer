#Requires -Version 5.1
<#
.SYNOPSIS
  Compatibility wrapper — use .\tool\bootstrap_windows.ps1 instead.

.DESCRIPTION
  Forwards to the unified Windows bootstrap script for FFmpeg only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = '',

    [Parameter(Mandatory = $false)]
    [int]$MaxAttempts = 3,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$wrapperRoot = $PSScriptRoot
if (-not $wrapperRoot) {
    $wrapperRoot = (Get-Location).Path
}

$params = @{
    Only = @('ffmpeg')
    MaxAttempts = $MaxAttempts
}
if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    $params.RepoRoot = $RepoRoot
}
if ($Force) {
    $params.Force = $true
}

& (Join-Path $wrapperRoot 'bootstrap_windows.ps1') @params
exit $LASTEXITCODE
