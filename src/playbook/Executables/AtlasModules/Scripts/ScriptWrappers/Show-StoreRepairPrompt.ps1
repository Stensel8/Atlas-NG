#Requires -Version 5.1
# Offers to re-run the Microsoft Store repair after a failed attempt.
# Launched directly by Fix-Store.ps1 on an interactive run, or by the
# 'Atlas Store Repair Retry' scheduled task at logon when the failed run was silent.
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

$windir = [Environment]::GetFolderPath('Windows')
$repairScript = Join-Path $windir 'AtlasDesktop\9. Troubleshooting\Fix-Store.ps1'

# The retry task is one-shot: drop it whether or not the user accepts, so the
# prompt does not come back at every logon.
Unregister-ScheduledTask -TaskName 'Atlas Store Repair Retry' -Confirm:$false -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) {
    [System.Windows.Forms.MessageBox]::Show(
        "The Microsoft Store repair script could not be found at:`n$repairScript",
        'Atlas', 'OK', 'Error') | Out-Null
    exit 1
}

$result = [System.Windows.Forms.MessageBox]::Show(
    'There was an error when fixing Microsoft Store. Would you like to try again?',
    'Confirm', 'YesNo', 'Error')

if ($result -ne 'Yes') { exit 0 }

[System.Windows.Forms.MessageBox]::Show(
    'Please do not close the script under any circumstances. Doing so could leave your Windows installation in a broken state.',
    'Warning', 'OK', 'Warning') | Out-Null

Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-File', "`"$repairScript`""
)
