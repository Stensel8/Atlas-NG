#Requires -Version 5.1
param (
    [switch]$Chrome,
    [switch]$Brave,
    [switch]$Firefox,
    [switch]$LibreWolf,
    [switch]$Toolbox,
    [switch]$UniGetUI,
    [switch]$DirectX,
    [switch]$Eclean
)

$ErrorActionPreference = 'Stop'

$executablesRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$initScript = Join-Path -Path $executablesRoot -ChildPath 'AtlasModules\initPowerShell.ps1'
if (-not (Test-Path -LiteralPath $initScript -PathType Leaf)) {
    throw "Atlas PowerShell initialization script '$initScript' is missing."
}

. $initScript

$script:IsArm64 = ((Get-CimInstance -Class Win32_ComputerSystem).SystemType -match 'ARM64') -or ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
$script:TempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())

function Remove-AtlasTempDirectory {
    if ($script:TempDir -and (Test-Path -LiteralPath $script:TempDir -PathType Container)) {
        Remove-Item -LiteralPath $script:TempDir -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# Used only for components not available on winget (DirectX, Atlas Toolbox)
function Invoke-AtlasDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Description
    )
    Write-Output "Downloading $Description..."
    # curl.exe preferred over Invoke-WebRequest: bypasses WinHTTP proxy issues, supports --retry-all-errors
    & curl.exe -LSs $Uri -o $Destination --connect-timeout 10 --retry 3 --retry-all-errors
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "Downloading $Description from '$Uri' failed with exit code $LASTEXITCODE."
    }
}

function Start-AtlasInstaller {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList,
        [Parameter(Mandatory)][string]$Description,
        [int[]]$SuccessExitCode = @(0)
    )
    Write-Output "Installing $Description..."
    $process = Start-Process -FilePath $FilePath -WindowStyle Hidden -ArgumentList $ArgumentList -Wait -PassThru
    if ($process.ExitCode -notin $SuccessExitCode) {
        throw "Installing $Description failed with exit code $($process.ExitCode)."
    }
}

# -- Connectivity & winget readiness

function Test-AtlasInternetConnectivity {
    try {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        return ($ping.Send('8.8.8.8', 2000)).Status -eq [System.Net.NetworkInformation.IPStatus]::Success
    } catch {
        return $false
    }
}

function Assert-AtlasWingetReady {
    # PSGallery requires NuGet provider
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue |
              Where-Object { $_.Version -ge '2.8.5.201' })) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }

    # Always pull latest asheroto/winget-install; it handles check, install, and repair internally
    # Credits: https://github.com/asheroto/winget-install
    Install-Script -Name winget-install -Force -Scope CurrentUser | Out-Null

    # winget-install calls exit internally, must run in a child process
    $scriptFile = Join-Path (Get-InstalledScript 'winget-install' -ErrorAction Stop).InstalledLocation 'winget-install.ps1'
    $ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    $result = Start-Process $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`"" -WindowStyle Hidden -Wait -PassThru
    if ($result.ExitCode -ne 0) {
        throw "winget-install exited with code $($result.ExitCode)."
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available after installation attempt.'
    }

    & winget source update --disable-interactivity 2>&1 | Out-Null
    Write-Output 'winget is ready.'
}

# -- winget install helper

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Description = $Id,
        [switch]$MachineScope
    )
    Write-Output "Installing $Description..."
    $scopeArgs = if ($MachineScope) { @('--scope', 'machine') } else { @() }
    & winget install --id $Id --silent --accept-package-agreements --accept-source-agreements --no-upgrade @scopeArgs 2>&1 | Out-Null
    # Treat "already installed" / "no upgrade" exit codes as success
    if ($LASTEXITCODE -notin @(0, -1978335135, -1978335189, -1978335147, -1978335212)) {
        Write-Warning "$Description (winget id: $Id) returned exit code $LASTEXITCODE."
    }
}

# -- Software installers

function Install-VisualCppRuntimes {
    Invoke-WingetInstall -Id 'Microsoft.VCRedist.2015+.x64' -Description 'Visual C++ Runtime 2015+ x64'
}

function Install-ArchiveTool {
    $nanaZipInstalled = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*NanaZip*' }
    if ($nanaZipInstalled) {
        Write-Output 'NanaZip is already installed, skipping.'
        return
    }

    Invoke-WingetInstall -Id 'M2Team.NanaZip' -Description 'NanaZip'
    if ($LASTEXITCODE -notin @(0, -1978335135, -1978335189, -1978335147, -1978335212)) {
        Write-Warning 'NanaZip installation failed, skipping archive tool.'
    }
}

function Install-DirectXRuntime {
    # Legacy DirectX is not available on winget, direct download required
    $installerPath = Join-Path -Path $script:TempDir -ChildPath 'directx.exe'
    $extractPath   = Join-Path -Path $script:TempDir -ChildPath 'directx'
    Invoke-AtlasDownload -Uri 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe' -Destination $installerPath -Description 'legacy DirectX runtimes'
    Start-AtlasInstaller -FilePath $installerPath -ArgumentList ('/q /c /t:"' + $extractPath + '"') -Description 'legacy DirectX runtime extractor'
    Start-AtlasInstaller -FilePath (Join-Path -Path $extractPath -ChildPath 'dxsetup.exe') -ArgumentList '/silent' -Description 'legacy DirectX runtimes'
}

function Install-AtlasToolbox {
    # Atlas Toolbox is not yet on winget, direct download from GitHub
    if ($env:PATH -like '*Atlas Toolbox*') { return }
    $toolboxPath = Join-Path -Path $script:TempDir -ChildPath 'toolbox.exe'
    # A failed optional install must not abort the playbook run
    try {
        Invoke-AtlasDownload -Uri 'https://github.com/Atlas-OS/atlas-toolbox/releases/latest/download/AtlasToolbox-Setup.exe' -Destination $toolboxPath -Description 'Atlas Toolbox'
        Start-AtlasInstaller -FilePath $toolboxPath -ArgumentList '/verysilent /install /MERGETASKS="desktopicon"' -Description 'Atlas Toolbox'
    }
    catch {
        Write-Warning "Atlas Toolbox could not be installed, setup will continue: $($_.Exception.Message)"
    }
}

function Install-Eclean {
    # eclean is not on winget, direct download from the vendor
    if ($env:PATH -like '*eclean*') { return }
    $ecleanPath = Join-Path -Path $script:TempDir -ChildPath 'eclean-setup.exe'
    try {
        Invoke-AtlasDownload -Uri 'https://update.eclean.gg/windows/latest/eclean-latest_x64-setup.exe?source=atlas' -Destination $ecleanPath -Description 'eclean'
        Start-AtlasInstaller -FilePath $ecleanPath -ArgumentList '/S' -Description 'eclean'
    }
    catch {
        Write-Warning "eclean could not be installed, setup will continue: $($_.Exception.Message)"
    }
}

function Install-BraveBrowser      { Invoke-WingetInstall -Id 'Brave.Brave'          -Description 'Brave Browser'   -MachineScope }
function Install-FirefoxBrowser    { Invoke-WingetInstall -Id 'Mozilla.Firefox'      -Description 'Mozilla Firefox' -MachineScope }
function Install-ChromeBrowser     { Invoke-WingetInstall -Id 'Google.Chrome'        -Description 'Google Chrome'   -MachineScope }
function Install-LibreWolfBrowser  { Invoke-WingetInstall -Id 'LibreWolf.LibreWolf'  -Description 'LibreWolf'       -MachineScope }
function Install-UniGetUI          { Invoke-WingetInstall -Id 'Devolutions.UniGetUI' -Description 'UniGetUI'                      }

# -- Entry point

New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
try {
    if ($Toolbox)    { Install-AtlasToolbox;       return }
    if ($Eclean)     { Install-Eclean;             return }
    if ($UniGetUI)   { Install-UniGetUI;           return }
    if ($DirectX)    { Install-DirectXRuntime;     return }
    if ($Brave)      { Install-BraveBrowser;       return }
    if ($Firefox)    { Install-FirefoxBrowser;     return }
    if ($LibreWolf)  { Install-LibreWolfBrowser;   return }
    if ($Chrome)     { Install-ChromeBrowser;      return }

    # Default: base software (VC++ runtimes, NanaZip)
    if (-not (Test-AtlasInternetConnectivity)) {
        Write-Warning 'No internet connection detected. Skipping base software installation (VC++ runtimes, NanaZip). These can be installed manually from the Atlas Toolbox once online.'
        exit 0
    }

    Assert-AtlasWingetReady
    Install-VisualCppRuntimes
    Install-ArchiveTool
}
finally {
    Remove-AtlasTempDirectory
}
