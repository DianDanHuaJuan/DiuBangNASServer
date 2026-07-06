#Requires -Version 5.1
<#
.SYNOPSIS
  收集 MSVC 2015-2022 x64 运行库 DLL，供应用本地部署（Win10/11 依赖系统 UCRT）。

.DESCRIPTION
  复制 vcruntime140.dll、vcruntime140_1.dll、msvcp140.dll 到 Release 目录。
  优先使用 assets\vc_runtime\x64 缓存；否则从 Visual Studio Redist 目录提取。

.PARAMETER ReleaseDir
  Flutter Windows Release 目录（与 diubang_file_s.exe 同级）。

.PARAMETER RepoRoot
  仓库根目录，默认为本脚本上两级。

.EXAMPLE
  .\packaging\windows\collect_vc_runtime.ps1 -ReleaseDir build\windows\x64\runner\Release
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,

    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequiredDlls = @(
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll'
)

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
} else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path
$stagingDir = Join-Path $RepoRoot 'assets\vc_runtime\x64'

function Test-AllDllsPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    foreach ($dll in $RequiredDlls) {
        $path = Join-Path $Directory $dll
        if (-not (Test-Path -LiteralPath $path)) {
            return $false
        }
    }
    return $true
}

function Find-VcRuntimeSourceDir {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        return $null
    }

    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ([string]::IsNullOrWhiteSpace($vsPath)) {
        $vsPath = & $vswhere -latest -property installationPath 2>$null
    }
    if ([string]::IsNullOrWhiteSpace($vsPath)) {
        return $null
    }

    $redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
    if (-not (Test-Path -LiteralPath $redistRoot)) {
        return $null
    }

    $versionDirs = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Sort-Object Name -Descending

    foreach ($versionDir in $versionDirs) {
        $candidates = @(
            (Join-Path $versionDir.FullName 'x64\Microsoft.VC143.CRT'),
            (Join-Path $versionDir.FullName 'x64\Microsoft.VC142.CRT'),
            (Join-Path $versionDir.FullName 'x64\Microsoft.VC141.CRT')
        )
        foreach ($candidate in $candidates) {
            if (Test-AllDllsPresent -Directory $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Copy-VcRuntimeFrom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDir
    )

    $null = New-Item -ItemType Directory -Force -Path $DestinationDir
    foreach ($dll in $RequiredDlls) {
        $source = Join-Path $SourceDir $dll
        $destination = Join-Path $DestinationDir $dll
        [System.IO.File]::Copy($source, $destination, $true)
    }
}

$sourceDir = $null
if (Test-AllDllsPresent -Directory $stagingDir) {
    $sourceDir = $stagingDir
    Write-Host "使用已缓存的 MSVC 运行库: $stagingDir"
} else {
    $sourceDir = Find-VcRuntimeSourceDir
    if ($null -ne $sourceDir) {
        Write-Host "从 Visual Studio Redist 提取 MSVC 运行库: $sourceDir"
        Copy-VcRuntimeFrom -SourceDir $sourceDir -DestinationDir $stagingDir
        $sourceDir = $stagingDir
    }
}

if ($null -eq $sourceDir) {
    throw @"
无法找到 MSVC x64 运行库 DLL。请任选其一：
  1. 安装 Visual Studio 2022（含「使用 C++ 的桌面开发」）后重试
  2. 手动将以下文件放入 assets\vc_runtime\x64\：
     vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll
  （可从 VS 安装目录 VC\Redist\MSVC\<version>\x64\Microsoft.VC143.CRT\ 复制）
"@
}

Copy-VcRuntimeFrom -SourceDir $sourceDir -DestinationDir $ReleaseDir

$legacyRedist = Join-Path $ReleaseDir 'vc_redist.x64.exe'
if (Test-Path -LiteralPath $legacyRedist) {
    Remove-Item -LiteralPath $legacyRedist -Force
    Write-Host '已移除 Release 目录中的 vc_redist.x64.exe。'
}

$totalKb = 0
foreach ($dll in $RequiredDlls) {
    $path = Join-Path $ReleaseDir $dll
    $sizeKb = [math]::Round((Get-Item -LiteralPath $path).Length / 1KB, 1)
    $totalKb += $sizeKb
    Write-Host "  OK  $dll ($sizeKb KB)"
}
Write-Host ("MSVC 运行库已部署到 Release，合计约 {0:N0} KB。" -f $totalKb)
