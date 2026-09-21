#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

Set-AtlasSettingState -SettingName 'ProcessExplorer' -State 0 -ScriptPath $PSCommandPath

$wingetCheck = Join-Path $env:windir 'AtlasModules\Scripts\Test-WingetReady.ps1'
& $wingetCheck -Silent
if ($LASTEXITCODE -ne 0) {
    Write-Output 'info: WinGet is not functional, reverting other changes anyways...'
} else {
    & winget uninstall -e --id Microsoft.Sysinternals.ProcessExplorer --force --purge `
        --disable-interactivity --accept-source-agreements -h
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'info: Process Explorer uninstallation failed, reverting other changes anyways...'
    }
}

& sc.exe config pcw start=boot | Out-Null

$ifeoKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\taskmgr.exe'
Remove-ItemProperty -LiteralPath $ifeoKey -Name 'Debugger' -ErrorAction SilentlyContinue

$shortcutPath = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'Programs\Process Explorer.lnk'
Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

# Close Task Manager before probing it: a second launch just focuses the running instance,
# which would make the check below pass even while the IFEO hijack is still in place.
Stop-Process -Name 'taskmgr' -Force -ErrorAction SilentlyContinue

& taskmgr.exe 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'Warning: Task Manager is still not working, applying fallback fix...'
    Remove-ItemProperty -LiteralPath $ifeoKey -Name 'Debugger' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    & winget uninstall -e --id Microsoft.Sysinternals.ProcessExplorer --force --purge `
        --disable-interactivity --accept-source-agreements -h 2>$null | Out-Null
    & sc.exe config pcw start=boot | Out-Null
    Write-Output 'Fallback fix applied. Please restart your computer for the changes to take effect.'
    if (-not $Silent) { $null = Read-Host 'Press Enter to exit' }
    return
}

if ($Silent) {
    Stop-Process -Name 'taskmgr' -Force -ErrorAction SilentlyContinue
    return
}

Write-Output ''
Write-Output 'Finished, changes have been applied.'
$null = Read-Host 'Press Enter to exit'
