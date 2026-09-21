#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$registryPath = 'HKLM:\SOFTWARE\AtlasOS\Services'

if (-not (Test-Path $registryPath)) {
    Write-Host "Registry path '$registryPath' not found, skipping." -ForegroundColor Yellow
    exit 0
}

Get-ChildItem -Path $registryPath | ForEach-Object {
    $subkey = $_
    $state = Get-ItemProperty -Path $subkey.PSPath -Name 'state' -ErrorAction SilentlyContinue
    $path  = Get-ItemProperty -Path $subkey.PSPath -Name 'path'  -ErrorAction SilentlyContinue

    if ($null -eq $state -or $null -eq $path) { return }

    # Some settings store their path with environment variables (e.g. %windir%\...)
    $scriptPath = [Environment]::ExpandEnvironmentVariables($path.path)

    # A missing target means the setting's script was renamed or removed by an update;
    # drop the stale key instead of failing every run from here on.
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "Script not found, cleaning up obsolete registry key: $scriptPath" -ForegroundColor Yellow
        Remove-Item -Path $subkey.PSPath -Force -Recurse -ErrorAction SilentlyContinue
        return
    }

    # Any non-zero state means the setting is active; 0 is the Windows default.
    if ($state.state -ne 0) {
        Write-Host "Running: $scriptPath" -ForegroundColor Cyan
        switch -Wildcard ($scriptPath) {
            '*.ps1' { & $scriptPath -Silent; break }
            # A .reg target is data, not a script: importing it through the shell
            # association would pop regedit's confirmation dialog.
            '*.reg' { & reg.exe import $scriptPath 2>$null | Out-Null; break }
            default { & $scriptPath /silent }
        }
    }
}
