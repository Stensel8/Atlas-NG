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

$internalScript = Join-Path -Path $PSScriptRoot -ChildPath 'AtlasModules\Scripts\Helpers\Install-AtlasSoftware.ps1'
if (-not (Test-Path -LiteralPath $internalScript -PathType Leaf)) {
    Write-Error "Atlas internal software installer '$internalScript' is missing."
    exit 1
}

& $internalScript @PSBoundParameters
if (-not $?) {
    exit 1
}

if ($null -ne $LASTEXITCODE) {
    exit $LASTEXITCODE
}

exit 0
