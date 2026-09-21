#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force
Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Services\Atlas.Services.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

Set-AtlasSettingState -SettingName 'TimerResolution' -State 0 -ScriptPath $PSCommandPath

Show-AtlasServiceWarning -Silent:$Silent

Remove-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' `
    -Name 'GlobalTimerResolutionRequests' -ErrorAction SilentlyContinue

Stop-Process -Name 'SetTimerResolution' -Force -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Force Timer Resolution' -Confirm:$false -ErrorAction SilentlyContinue

if ($Silent) { return }
Write-Output ''
Write-Output 'Timer resolution has been reset to default.'
$null = Read-Host 'Press Enter to exit'
