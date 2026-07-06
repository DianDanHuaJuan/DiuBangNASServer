#Requires -Version 5.1
<#
.SYNOPSIS
  校验 Windows Release 目录是否满足分发/安装包要求（本地 smoke test）。

.PARAMETER ReleaseDir
  Release 目录路径，默认为 build\windows\x64\runner\Release
#>
[CmdletBinding()]
param(
    [string]$ReleaseDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $ReleaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
}
$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path

$requiredFiles = @(
    'diubang_file_s.exe',
    'flutter_windows.dll',
    'libmpv-2.dll',
    'ffmpeg.exe',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll',
    'data\app.so',
    'data\icudtl.dat',
    'data\flutter_assets\assets\Encryption_key'
)

$requiredPlugins = @(
    'bonsoir_windows_plugin.dll',
    'file_selector_windows_plugin.dll',
    'window_manager_plugin.dll',
    'system_tray_plugin.dll'
)

Write-Host "校验 Release 目录: $ReleaseDir"

$failures = @()
foreach ($item in ($requiredFiles + $requiredPlugins)) {
    $path = Join-Path $ReleaseDir $item
    if (Test-Path -LiteralPath $path) {
        Write-Host "  OK  $item"
    } else {
        Write-Host "  MISSING  $item"
        $failures += $item
    }
}

$exePath = Join-Path $ReleaseDir 'diubang_file_s.exe'
if (Test-Path -LiteralPath $exePath) {
    $manifest = Join-Path $repoRoot 'windows\runner\runner.exe.manifest'
    if (Test-Path -LiteralPath $manifest) {
        $manifestText = Get-Content -LiteralPath $manifest -Raw
        if ($manifestText -match '8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a') {
            Write-Host '  OK  manifest 声明 Windows 10+ 兼容性'
        }
    }
}

$legacyRedist = Join-Path $ReleaseDir 'vc_redist.x64.exe'
if (Test-Path -LiteralPath $legacyRedist) {
    Write-Host '  FAIL  vc_redist.x64.exe 不应出现在 Release 目录'
    throw 'Release 目录包含 vc_redist.x64.exe，请运行 collect_vc_runtime.ps1 并移除旧版 redist。'
}

if ($failures.Count -gt 0) {
    Write-Error "校验失败，缺少 $($failures.Count) 个文件。"
}

$totalMb = (
    Get-ChildItem -LiteralPath $ReleaseDir -Recurse -File |
    Measure-Object -Property Length -Sum
).Sum / 1MB
Write-Host ("校验通过。总大小约 {0:N1} MB。" -f $totalMb)
Write-Host '注意: 完整实机测试请在 Windows 10/11 干净环境安装并验证防火墙与配对流程。'
