#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force
Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Services\Atlas.Services.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

Set-AtlasSettingState -SettingName 'LanmanWorkstation' -State 0 -ScriptPath $PSCommandPath

Show-AtlasServiceWarning -Silent:$Silent

Set-AtlasServiceStartup -Name 'KSecPkg'          -Start 4
Set-AtlasServiceStartup -Name 'LanmanServer'      -Start 4
Set-AtlasServiceStartup -Name 'LanmanWorkstation' -Start 4
Set-AtlasServiceStartup -Name 'mrxsmb'            -Start 4
Set-AtlasServiceStartup -Name 'mrxsmb20'          -Start 4
Set-AtlasServiceStartup -Name 'rdbss'             -Start 3
Set-AtlasServiceStartup -Name 'srv2'              -Start 4

# SmbDirect is absent on some editions; DISM errors out instead of no-opping there
& dism.exe /Online /Get-FeatureInfo /FeatureName:'SmbDirect' 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    & dism.exe /Online /Disable-Feature /FeatureName:'SmbDirect' /NoRestart 2>&1 | Out-Null
}

if ($Silent) { return }
Write-Output ''
Write-Output 'Finished, please reboot your device for changes to apply.'
$null = Read-Host 'Press Enter to exit'
