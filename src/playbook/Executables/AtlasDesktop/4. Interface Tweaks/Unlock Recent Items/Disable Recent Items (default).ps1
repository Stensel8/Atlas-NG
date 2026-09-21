#Requires -Version 5.1
param([switch]$Silent, [switch]$NoAction)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

Set-AtlasSettingState -SettingName 'RecentItems' -State 0 -ScriptPath $PSCommandPath

$polExp  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$polExpW = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
$polSys  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$polSysW = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
$adv     = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

foreach ($k in @($polExp, $polExpW, $polSys, $polSysW, $adv)) {
    if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force | Out-Null }
}

New-ItemProperty -LiteralPath $polExp  -Name 'NoInstrumentation'          -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $polExp  -Name 'ClearRecentDocsOnExit'      -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $polExp  -Name 'NoRecentDocsHistory'        -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $polExpW -Name 'NoRemoteDestinations'       -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $polSys  -Name 'NoStartMenuMFUprogramsList' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $polSys  -Name 'NoRecentDocsHistory'        -Value 1 -PropertyType DWord -Force | Out-Null
# 2 = force off; 1 forces the list ON, which is the opposite of what this script is for
New-ItemProperty -LiteralPath $polSysW -Name 'ShowOrHideMostUsedApps'     -Value 2 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $polSysW -Name 'HideRecentlyAddedApps'      -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $adv     -Name 'Start_TrackProgs'           -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $adv     -Name 'Start_TrackDocs'            -Value 0 -PropertyType DWord -Force | Out-Null

Invoke-AtlasSettingsPage -Operation hide -Page 'privacy-general'

if (-not $NoAction) {
    Stop-Process -Name 'explorer'    -Force -ErrorAction SilentlyContinue
    Stop-Process -Name 'SettingsApp' -Force -ErrorAction SilentlyContinue
    Start-Process 'explorer.exe'
}

if ($Silent) { return }
Write-Output ''
Write-Output 'Recent items have been disabled.'
$null = Read-Host 'Press Enter to exit'
