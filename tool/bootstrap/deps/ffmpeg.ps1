#Requires -Version 5.1
Set-StrictMode -Version Latest

# BtbN/FFmpeg-Builds — win64-lgpl static (8.1 release branch), NOT gyan GPLv3 essentials.
# Pinned autobuild tag for reproducible downloads; bump when upgrading FFmpeg.
$Script:FfmpegReleaseTag = 'autobuild-2026-06-26-13-36'
$Script:FfmpegZipFileName = 'ffmpeg-n8.1.2-win64-lgpl-8.1.zip'
$Script:FfmpegZipUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$($Script:FfmpegReleaseTag)/$($Script:FfmpegZipFileName)"
$Script:FfmpegZipMd5 = 'd0761ad21f2a6eaa4396374e1e46cc4e'
$Script:MinFfmpegExeBytes = 50 * 1024 * 1024
$Script:MinFfmpegZipBytes = 100 * 1024 * 1024

function Test-FfmpegExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $sizeBytes = (Get-Item -LiteralPath $Path).Length
    if ($sizeBytes -lt $Script:MinFfmpegExeBytes) {
        return $false
    }

    try {
        $null = & $Path -hide_banner -version 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    } catch {
        return $false
    }

    return Test-FfmpegLgplCompliance -Path $Path
}

function Test-FfmpegLgplCompliance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $buildConf = & $Path -hide_banner -buildconf 2>&1 | Out-String
        if ($buildConf -match '--enable-gpl' -or $buildConf -match '--enable-nonfree') {
            Write-Warning 'FFmpeg buildconf contains GPL/nonfree flags.'
            return $false
        }

        $encoders = & $Path -hide_banner -encoders 2>&1 | Out-String
        if ($encoders -match '\blibx264\b' -or $encoders -match '\blibx265\b') {
            Write-Warning 'FFmpeg encoders include GPL-only libx264/libx265.'
            return $false
        }

        if ($encoders -notmatch '\bh264_mf\b' -and $encoders -notmatch '\blibopenh264\b') {
            Write-Warning 'FFmpeg lacks LGPL-safe H.264 encoders (h264_mf / libopenh264).'
            return $false
        }

        $muxers = & $Path -hide_banner -muxers 2>&1 | Out-String
        if ($muxers -notmatch '\bhls\b') {
            Write-Warning 'FFmpeg lacks HLS muxer.'
            return $false
        }
    } catch {
        return $false
    }

    return $true
}

function Get-ExtractedFfmpegExe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractRoot
    )

    $binMatches = @(Get-ChildItem -LiteralPath $ExtractRoot -Recurse -Filter 'ffmpeg.exe' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match '[\\/]bin$' })

    if ($binMatches.Count -eq 0) {
        throw "Could not find bin\ffmpeg.exe under extracted archive at $ExtractRoot"
    }

    return $binMatches[0].FullName
}

function Ensure-FfmpegDependency {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $repoRoot = $Context.RepoRoot
    $maxAttempts = $Context.MaxAttempts
    $force = [bool]$Context.Force
    $failures = [System.Collections.Generic.List[object]]::new()

    $assetsDir = Join-Path $repoRoot 'assets'
    $ffmpegDest = Join-Path $assetsDir 'ffmpeg.exe'
    $cacheDir = Join-Path $repoRoot 'tool\.cache'
    $zipCachePath = Join-Path $cacheDir $Script:FfmpegZipFileName
    $displayName = 'FFmpeg LGPL (BtbN win64-lgpl, ffmpeg.exe)'

    if ((Test-FfmpegExecutable -Path $ffmpegDest) -and -not $force) {
        $existingSize = (Get-Item -LiteralPath $ffmpegDest).Length
        Write-Host "$displayName`: already present ($([math]::Round($existingSize / 1MB, 1)) MB, LGPL verification OK)."
        return @{
            Success = $true
            Failures = @()
        }
    }

    if ($force -and (Test-Path -LiteralPath $ffmpegDest)) {
        Write-Host 'Force: removing existing assets\ffmpeg.exe'
        Remove-Item -LiteralPath $ffmpegDest -Force
    }

    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

    $zipResult = Invoke-RetryDownload `
        -Id 'ffmpeg' `
        -DisplayName "$displayName (zip cache)" `
        -Url $Script:FfmpegZipUrl `
        -DestinationPath $zipCachePath `
        -MaxAttempts $maxAttempts `
        -ExpectedMd5 $Script:FfmpegZipMd5 `
        -MinSizeBytes $Script:MinFfmpegZipBytes `
        -TimeoutSec 900 `
        -Force:$force

    if (-not $zipResult.Success) {
        $failures.Add((New-BootstrapFailure `
            -Id 'ffmpeg' `
            -DisplayName $displayName `
            -Url $Script:FfmpegZipUrl `
            -ErrorMessage "$($zipResult.LastError) (after $maxAttempts attempts)" `
            -ManualHint @"
手动下载 $($Script:FfmpegZipFileName) 从 https://github.com/BtbN/FFmpeg-Builds/releases/tag/$($Script:FfmpegReleaseTag)
选择 win64-lgpl 静态构建（非 gpl），解压 bin\ffmpeg.exe 到 assets\ffmpeg.exe
"@))
        return @{
            Success = $false
            Failures = $failures.ToArray()
        }
    }

    $extractRoot = Join-Path $cacheDir 'ffmpeg-btbn-lgpl-extract'
    try {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

        Write-Host "$displayName`: extracting BtbN lgpl build ..."
        Expand-Archive -LiteralPath $zipCachePath -DestinationPath $extractRoot -Force

        $extractedFfmpeg = Get-ExtractedFfmpegExe -ExtractRoot $extractRoot
        New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
        Copy-Item -LiteralPath $extractedFfmpeg -Destination $ffmpegDest -Force
    } catch {
        Remove-FileIfExists -Path $ffmpegDest
        $failures.Add((New-BootstrapFailure `
            -Id 'ffmpeg' `
            -DisplayName $displayName `
            -Url $Script:FfmpegZipUrl `
            -ErrorMessage $_.Exception.Message `
            -ManualHint 'Ensure the BtbN lgpl zip is valid; re-run with -Force.'))
        return @{
            Success = $false
            Failures = $failures.ToArray()
        }
    } finally {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-FfmpegExecutable -Path $ffmpegDest)) {
        Remove-FileIfExists -Path $ffmpegDest
        $failures.Add((New-BootstrapFailure `
            -Id 'ffmpeg' `
            -DisplayName $displayName `
            -Url $Script:FfmpegZipUrl `
            -ErrorMessage 'Extracted ffmpeg.exe failed LGPL compliance verification.' `
            -ManualHint 'Re-run with -Force or manually place a BtbN win64-lgpl ffmpeg.exe under assets\.'))
        return @{
            Success = $false
            Failures = $failures.ToArray()
        }
    }

    $finalSize = (Get-Item -LiteralPath $ffmpegDest).Length
    Write-Host "$displayName`: ready at assets\ffmpeg.exe ($([math]::Round($finalSize / 1MB, 1)) MB)."
    return @{
        Success = $true
        Failures = @()
    }
}
