#Requires -Version 5.1
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

$folder = Join-Path $env:windir 'Temp'

Write-Host 'This script fixes errors 2502 and 2503 with Windows installers by resetting TEMP folder permissions.' -ForegroundColor White
Write-Host 'This issue is not related to Atlas.' -ForegroundColor DarkGray
Write-Host ''
if (-not $Silent) { $null = Read-Host 'Press Enter to continue' }
Write-Host ''

try {
    Write-Host '[>>] Taking ownership of TEMP folder...' -ForegroundColor Yellow
    & takeown.exe /f $folder /r /d y | Out-Null

    Write-Host '[>>] Resetting permissions...' -ForegroundColor Yellow
    & icacls.exe $folder /inheritance:e | Out-Null
    & icacls.exe $folder /reset         | Out-Null
    & icacls.exe $folder /inheritance:r | Out-Null

    Write-Host '[>>] Applying default permissions...' -ForegroundColor Yellow
    & icacls.exe "$env:windir\Temp" `
        '/grant:r' '*S-1-5-32-545:(OI)(CI)F' `
        '/grant:r' '*S-1-5-18:(OI)(CI)F' `
        '/grant:r' '*S-1-3-0:(OI)(CI)F' `
        '/grant:r' '*S-1-5-11:(OI)(CI)(X,AD,WD)' `
        /t | Out-Null

    Write-Host '[>>] Clearing Windows temporary files...' -ForegroundColor Yellow
    Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '[OK] Completed.' -ForegroundColor Green
    if (-not $Silent) { $null = Read-Host 'Press Enter to exit' }
} catch {
    Write-Host "[!!] Failed: $_" -ForegroundColor Red
    exit 1
}
