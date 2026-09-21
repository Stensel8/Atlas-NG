#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

$stateKey = 'HKLM:\SOFTWARE\AtlasOS\Services\ToggleWindowsUpdates'
if (-not (Test-Path -LiteralPath $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $stateKey -Name 'path' -Value $PSCommandPath -Type String

$wuSvc = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
$isDisabled = $wuSvc -and $wuSvc.StartType -eq 'Disabled'

$currentLabel = if ($isDisabled) { ' (current)' } else { '' }
$enableLabel  = if (-not $isDisabled) { ' (current)' } else { '' }

if ($Silent) {
    # A silent run re-applies whatever the user already chose; with no stored choice
    # there is nothing to apply, so leave Windows Update exactly as it is.
    $storedState = (Get-ItemProperty -LiteralPath $stateKey -Name 'state' -ErrorAction SilentlyContinue).state
    switch ($storedState) {
        0       { $choice = 0 }
        1       { $choice = 1 }
        default { return }
    }
} else {
    $choice = $Host.UI.PromptForChoice(
        'Windows Update Toggle',
        '',
        @("1. Disable Windows Updates$currentLabel", "2. Enable Windows Updates$enableLabel"),
        -1
    )
}

if ($choice -eq 0) {
    Write-Output 'Disabling Windows Update service and scheduled tasks...'
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Set-Service -Name wuauserv -StartupType Disabled
    Stop-Service -Name UsoSvc -Force -ErrorAction SilentlyContinue
    Set-Service -Name UsoSvc -StartupType Disabled

    $medicKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc'
    if (-not (Test-Path -LiteralPath $medicKey)) { New-Item -Path $medicKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $medicKey -Name 'Start' -Value 4 -Type DWord
    Stop-Service -Name WaaSMedicSvc -Force -ErrorAction SilentlyContinue

    foreach ($task in @(
        '\Microsoft\Windows\WindowsUpdate\sih'
        '\Microsoft\Windows\WindowsUpdate\sihboot'
        '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan'
        '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker'
        '\Microsoft\Windows\UpdateOrchestrator\Reboot'
    )) {
        $taskPath = $task -replace '[^\\]+$', ''
        $taskName = ($task -split '\\')[-1]
        Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    }

    $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (-not (Test-Path -LiteralPath $wuKey)) { New-Item -Path $wuKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $wuKey -Name 'DisableWindowsUpdateAccess' -Value 1 -Type DWord
    Set-ItemProperty -LiteralPath $wuKey -Name 'DoNotConnectToWindowsUpdateInternetLocations' -Value 1 -Type DWord
    $auKey = "$wuKey\AU"
    if (-not (Test-Path -LiteralPath $auKey)) { New-Item -Path $auKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $auKey -Name 'NoAutoUpdate' -Value 1 -Type DWord

    Invoke-AtlasSettingsPage -Operation hide -Page 'windowsupdate'
    Set-ItemProperty -LiteralPath $stateKey -Name 'state' -Value 0 -Type DWord

    Write-Output 'Windows Updates have been disabled.'

} else {
    Write-Output 'Enabling Windows Update service and scheduled tasks...'
    Set-Service -Name wuauserv -StartupType Manual
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Set-Service -Name UsoSvc -StartupType Manual
    Start-Service -Name UsoSvc -ErrorAction SilentlyContinue

    $medicKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc'
    if (-not (Test-Path -LiteralPath $medicKey)) { New-Item -Path $medicKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $medicKey -Name 'Start' -Value 3 -Type DWord
    Start-Service -Name WaaSMedicSvc -ErrorAction SilentlyContinue

    foreach ($task in @(
        '\Microsoft\Windows\WindowsUpdate\sih'
        '\Microsoft\Windows\WindowsUpdate\sihboot'
        '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan'
        '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker'
        '\Microsoft\Windows\UpdateOrchestrator\Reboot'
    )) {
        $taskPath = $task -replace '[^\\]+$', ''
        $taskName = ($task -split '\\')[-1]
        Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    }

    $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    Remove-ItemProperty -LiteralPath $wuKey -Name 'DisableWindowsUpdateAccess' -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $wuKey -Name 'DoNotConnectToWindowsUpdateInternetLocations' -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath "$wuKey\AU" -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue

    Invoke-AtlasSettingsPage -Operation unhide -Page 'windowsupdate'
    Set-ItemProperty -LiteralPath $stateKey -Name 'state' -Value 1 -Type DWord

    Write-Output 'Windows Updates have been enabled.'
}

if ($Silent) { return }

Write-Output ''
$reboot = $Host.UI.PromptForChoice('', 'Would you like to reboot now to apply changes?', @('&Yes', '&No'), 1)
if ($reboot -eq 0) { Restart-Computer -Force }
