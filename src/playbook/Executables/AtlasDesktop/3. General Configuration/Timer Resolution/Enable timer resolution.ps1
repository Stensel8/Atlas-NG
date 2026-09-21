#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force
Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Services\Atlas.Services.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

Set-AtlasSettingState -SettingName 'TimerResolution' -State 1 -ScriptPath $PSCommandPath

Show-AtlasServiceWarning -Silent:$Silent

$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -LiteralPath $key -Name 'GlobalTimerResolutionRequests' -Value 1 -PropertyType DWord -Force | Out-Null

$xmlPath = Join-Path $env:windir 'AtlasModules\Other\Force Timer Resolution.xml'
Register-ScheduledTask -TaskName 'Force Timer Resolution' -Xml (Get-Content -LiteralPath $xmlPath -Raw) -Force | Out-Null
Start-ScheduledTask -TaskName 'Force Timer Resolution'

if ($Silent) { return }
Write-Output ''
Write-Output 'Timer resolution has been enabled. Please reboot your device for changes to apply.'
$null = Read-Host 'Press Enter to exit'
