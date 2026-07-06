#Requires -Version 5.1
Set-StrictMode -Version Latest

# Register bootstrap dependencies here. To add a new dependency:
#   1. Create tool/bootstrap/deps/<id>.ps1 exporting Ensure-<Id>Dependency
#   2. Add an entry below

$Script:BootstrapDependencies = @(
    @{
        Id = 'media_kit'
        Script = 'media_kit.ps1'
        DisplayName = 'media_kit (libmpv + ANGLE)'
        EnsureFunction = 'Ensure-MediaKitDependency'
    },
    @{
        Id = 'ffmpeg'
        Script = 'ffmpeg.ps1'
        DisplayName = 'FFmpeg LGPL (BtbN win64-lgpl)'
        EnsureFunction = 'Ensure-FfmpegDependency'
    }
)

function Get-BootstrapDependencies {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Only = @()
    )

    if ($Only.Count -eq 0) {
        return $Script:BootstrapDependencies
    }

    $filtered = @($Script:BootstrapDependencies | Where-Object { $Only -contains $_.Id })
    $unknown = @($Only | Where-Object { $filtered.Id -notcontains $_ })
    if ($unknown.Count -gt 0) {
        throw "Unknown bootstrap dependency id(s): $($unknown -join ', '). Valid: $($Script:BootstrapDependencies.Id -join ', ')"
    }

    return $filtered
}
