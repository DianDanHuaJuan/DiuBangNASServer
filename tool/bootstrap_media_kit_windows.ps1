#Requires -Version 5.1
<#
.SYNOPSIS
  Compatibility wrapper — use .\tool\bootstrap_windows.ps1 instead.

.DESCRIPTION
  Forwards to the unified Windows bootstrap script for media_kit only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = '',

    [Parameter(Mandatory = $false)]
    [int]$MaxAttempts = 3
)

$wrapperRoot = $PSScriptRoot
if (-not $wrapperRoot) {
    $wrapperRoot = (Get-Location).Path
}

$params = @{
    Only = @('media_kit')
    MaxAttempts = $MaxAttempts
}
if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    $params.RepoRoot = $RepoRoot
}

& (Join-Path $wrapperRoot 'bootstrap_windows.ps1') @params
exit $LASTEXITCODE
