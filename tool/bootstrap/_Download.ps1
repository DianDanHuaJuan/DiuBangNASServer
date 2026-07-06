#Requires -Version 5.1
Set-StrictMode -Version Latest

function Resolve-RepoRoot {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RepoRoot = '',

        [Parameter(Mandatory = $false)]
        [string]$ScriptRoot = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        return (Resolve-Path -LiteralPath $RepoRoot).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($ScriptRoot)) {
        return (Resolve-Path (Join-Path $ScriptRoot '..')).Path
    }

    return (Get-Location).Path
}

function Get-FileMd5Hex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hash = $md5.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $md5.Dispose()
    }

    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Remove-FileIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Test-DownloadedFileValid {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedMd5 = '',

        [Parameter(Mandatory = $false)]
        [long]$MinSizeBytes = 1024
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $sizeBytes = (Get-Item -LiteralPath $Path).Length
    if ($sizeBytes -lt $MinSizeBytes) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedMd5)) {
        $actualMd5 = Get-FileMd5Hex -Path $Path
        if ($actualMd5 -ne $ExpectedMd5.ToLowerInvariant()) {
            return $false
        }
    }

    return $true
}

function Invoke-RetryDownload {
    <#
    .SYNOPSIS
      Download a file with limited retries, cleanup on failure, optional MD5 verification.
    .OUTPUTS
      Hashtable: Success, LastError, Url, DestinationPath
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [int]$MaxAttempts,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedMd5 = '',

        [Parameter(Mandatory = $false)]
        [long]$MinSizeBytes = 1024,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec = 600,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $destinationDir = Split-Path -Parent $DestinationPath
    if (-not [string]::IsNullOrWhiteSpace($destinationDir)) {
        New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    }

    if ((Test-Path -LiteralPath $DestinationPath) -and -not $Force) {
        if (Test-DownloadedFileValid -Path $DestinationPath -ExpectedMd5 $ExpectedMd5 -MinSizeBytes $MinSizeBytes) {
            $existingSize = (Get-Item -LiteralPath $DestinationPath).Length
            Write-Host "$DisplayName`: already present ($([math]::Round($existingSize / 1MB, 1)) MB, verification OK)."
            return @{
                Success = $true
                Id = $Id
                DisplayName = $DisplayName
                Url = $Url
                DestinationPath = $DestinationPath
                LastError = $null
            }
        }

        Write-Warning "$DisplayName`: existing file failed verification. Deleting and re-downloading."
        Remove-FileIfExists -Path $DestinationPath
    }

    if ($Force) {
        Remove-FileIfExists -Path $DestinationPath
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Host "$DisplayName`: downloading (attempt $attempt/$MaxAttempts) ..."
            Write-Host "  URL: $Url"

            Remove-FileIfExists -Path $DestinationPath

            Invoke-WebRequest `
                -Uri $Url `
                -OutFile $DestinationPath `
                -UseBasicParsing `
                -TimeoutSec $TimeoutSec

            if (-not (Test-Path -LiteralPath $DestinationPath)) {
                throw "Download did not create $DestinationPath"
            }

            if (-not (Test-DownloadedFileValid -Path $DestinationPath -ExpectedMd5 $ExpectedMd5 -MinSizeBytes $MinSizeBytes)) {
                $sizeBytes = (Get-Item -LiteralPath $DestinationPath).Length
                if (-not [string]::IsNullOrWhiteSpace($ExpectedMd5)) {
                    $actualMd5 = Get-FileMd5Hex -Path $DestinationPath
                    throw "Verification failed (expected MD5 $($ExpectedMd5.ToLowerInvariant()), got $actualMd5, size $sizeBytes bytes)."
                }

                throw "Downloaded file is too small ($sizeBytes bytes); likely incomplete or blocked."
            }

            $finalSize = (Get-Item -LiteralPath $DestinationPath).Length
            Write-Host "$DisplayName`: download verified ($([math]::Round($finalSize / 1MB, 1)) MB)."
            return @{
                Success = $true
                Id = $Id
                DisplayName = $DisplayName
                Url = $Url
                DestinationPath = $DestinationPath
                LastError = $null
            }
        } catch {
            $lastError = $_.Exception.Message
            Remove-FileIfExists -Path $DestinationPath

            if ($attempt -lt $MaxAttempts) {
                $delaySeconds = [math]::Pow(2, $attempt)
                Write-Warning "$DisplayName`: attempt $attempt failed: $lastError"
                Write-Host "Retrying in ${delaySeconds}s ..."
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }

    return @{
        Success = $false
        Id = $Id
        DisplayName = $DisplayName
        Url = $Url
        DestinationPath = $DestinationPath
        LastError = $lastError
    }
}

function New-BootstrapFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $false)]
        [string]$Url = '',

        [Parameter(Mandatory = $false)]
        [string]$ManualHint = ''
    )

    return @{
        Id = $Id
        DisplayName = $DisplayName
        Url = $Url
        LastError = $ErrorMessage
        ManualHint = $ManualHint
    }
}

function Write-BootstrapFailureReport {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Failures,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    Write-Host ''
    Write-Host '========================================'
    Write-Host 'Bootstrap FAILED — 以下依赖未能准备就绪:'
    Write-Host '========================================'

    foreach ($failure in $Failures) {
        Write-Host ''
        Write-Host "[$($failure.Id)] $($failure.DisplayName)"
        if (-not [string]::IsNullOrWhiteSpace($failure.Url)) {
            Write-Host "  URL: $($failure.Url)"
        }
        Write-Host "  Error: $($failure.LastError)"
        if (-not [string]::IsNullOrWhiteSpace($failure.ManualHint)) {
            Write-Host "  Hint: $($failure.ManualHint)"
        }
    }

    Write-Host ''
    Write-Host '========================================'
    Write-Host "Re-run: .\tool\bootstrap_windows.ps1 [-Force]"
    Write-Host "  Or fix individually: -Only media_kit | -Only ffmpeg"
    Write-Host '========================================'
}
