#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Task Manager holds the Process Explorer IFEO hijack open, so it has to be closed both
# before and after the uninstall: before, so the uninstall can replace the registry entry,
# and after, in case the uninstaller itself relaunched it.
function Stop-TaskManager {
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'taskmgr.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    & taskkill.exe /F /IM taskmgr.exe 2>$null | Out-Null
    $exitCode = $LASTEXITCODE
    # 128 means "no such process", which is the expected result when Task Manager is not running
    if ($exitCode -ne 0 -and $exitCode -ne 128) {
        throw "taskkill.exe failed while closing taskmgr.exe with exit code $exitCode."
    }
}

$uninstallScript = Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'AtlasDesktop\6. Advanced Configuration\Process Explorer\Uninstall Process Explorer.ps1'

Stop-TaskManager

if (Test-Path -LiteralPath $uninstallScript -PathType Leaf) {
    & $uninstallScript -Silent
}
else {
    Write-Warning "Process Explorer uninstall script '$uninstallScript' was not found; continuing upgrade cleanup."
}

Stop-TaskManager
