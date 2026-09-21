#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

$stateKey = 'HKLM:\SOFTWARE\AtlasOS\Services\SpinningAnimations'
if (-not (Test-Path -LiteralPath $stateKey)) { New-Item -Path $stateKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $stateKey -Name 'path' -Value $PSCommandPath -Type String

# /silent runs are non-interactive (the playbook applies defaults through
# Invoke-AtlasDefaults.ps1), so fall through to the prompt's own default.
$choice = if ($Silent) {
    1
} else {
    $Host.UI.PromptForChoice(
        '',
        'What would you like to do?',
        @('1. Disable the spinning animation', '2. Enable the spinning animation (default)'),
        1
    )
}

if ($choice -eq 0) {
    & bcdedit.exe /set '{globalsettings}' custom:16000069 true | Out-Null
    Set-ItemProperty -LiteralPath $stateKey -Name 'state' -Value 0 -Type DWord
} else {
    & bcdedit.exe /deletevalue '{globalsettings}' custom:16000069 2>$null | Out-Null
    Set-ItemProperty -LiteralPath $stateKey -Name 'state' -Value 1 -Type DWord
}

Write-Output ''
Write-Output 'Finished, please reboot your device for changes to apply.'
if (-not $Silent) { $null = Read-Host 'Press Enter to exit' }
