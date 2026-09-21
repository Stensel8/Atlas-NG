#Requires -Version 5.1
# Repairs Microsoft Store and Xbox/Gaming Services install failures.
# Two root causes addressed:
#   1. StateRepository-Deployment.srd corruption — deleting it forces a clean rebuild on next AppX operation
#   2. Store-essential services Disabled by debloat tools — promoted to Manual so Windows can trigger-start them
param(
    [switch]$Silent,
    # On failure, ask the user to retry; under -Silent the prompt is deferred to next logon
    [switch]$PromptOnFailure
)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $env:windir 'AtlasModules\Scripts\Modules\Atlas.Core\Atlas.Core.psd1') -Force

$activeArgs = @($PSBoundParameters.GetEnumerator() |
    Where-Object { $_.Value -is [switch] -and $_.Value.IsPresent } |
    ForEach-Object { "-$($_.Key)" })
Assert-AtlasAdminPrivilege -ScriptPath $PSCommandPath -ScriptArgs $activeArgs

# --- Constants ---

# ClipSVC validates app licenses; AppXSvc deploys packages; StateRepository tracks the installed-app database
$storeServices   = @('ClipSVC', 'AppXSvc', 'StateRepository')
# Required for Xbox Game Pass and Gaming Services installs
$gamingServices  = @('GamingServices', 'GamingServicesNet', 'XboxNetApiSvc', 'XblAuthManager', 'XblGameSave')
$allRootServices = $storeServices + $gamingServices

# SQLite database tracking all installed AppX packages; corruption causes 0x80073CF9 and similar errors
$stateRepoFile = Join-Path $env:ProgramData 'Microsoft\Windows\AppRepository\StateRepository-Deployment.srd'

# --- Output helpers ---
# Each step prints its description without a newline, then ends with ' OK' or ' failed' on the same line.
# Steps that produce sub-notes break to a new line for those notes, then print 'OK' indented.
function Write-Step   ([string]$Msg) { Write-Host "  $Msg" -NoNewline }
function Write-OK     ([string]$Detail = '') {
    $suffix = if ($Detail) { " OK  ($Detail)" } else { ' OK' }
    Write-Host $suffix -ForegroundColor Green
}
function Write-Skipped ([string]$Detail = '') {
    $suffix = if ($Detail) { " skipped  ($Detail)" } else { ' skipped' }
    Write-Host $suffix -ForegroundColor DarkGray
}
$script:FailureCount = 0
function Write-Failed ([string]$Detail = '') {
    $script:FailureCount++
    $suffix = if ($Detail) { " failed  ($Detail)" } else { ' failed' }
    Write-Host $suffix -ForegroundColor Red
}
function Write-SubNote ([string]$Msg) {
    # Call after Write-Step when a note must appear before the OK; adds newline first
    Write-Host ''
    Write-Host "       $Msg" -ForegroundColor Yellow
}

# --- Service helpers ---

# BFS through the full dependency chain — catches transitive dependents that a simple
# DependentServices query misses (e.g. a dependent of a dependent of ClipSVC)
function Get-ServiceDependentsBFS ([string[]]$Names) {
    $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($n in $Names) { [void]$queue.Enqueue($n) }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $svc = Get-Service -Name $current -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        foreach ($dep in $svc.DependentServices) {
            if ($seen.Add($dep.ServiceName)) { [void]$queue.Enqueue($dep.ServiceName) }
        }
    }
    # Root services are tracked separately; remove them from the dependent set
    foreach ($n in $Names) { [void]$seen.Remove($n) }
    return [string[]]$seen
}

function Stop-ServiceSafe ([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -eq 'Stopped') { return }
    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    # Wait up to 15 s for the service to reach Stopped before moving on
    try { $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15)) } catch { $null = $_ }
}

function Start-ServiceSafe ([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Start-Service -Name $Name -ErrorAction SilentlyContinue
    }
}

function Set-StartupTypeSafe ([string]$Name, [string]$StartupType) {
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction SilentlyContinue
}

# --- Repair steps ---

Write-Host ''
Write-Host '  Repairing Microsoft Store and Gaming Services...' -ForegroundColor Cyan
Write-Host ''

# Step 1: collect the full transitive dependent tree
Write-Step 'Collecting dependent services...'
$dependents = Get-ServiceDependentsBFS -Names $allRootServices
$stopOrder  = $dependents + $allRootServices
Write-OK

# Step 2: backup current startup types before touching anything
Write-Step 'Backing up service startup types...'
$backup = @{}
foreach ($name in ($allRootServices + $dependents)) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) { $backup[$name] = $svc.StartType.ToString() }
}
Write-OK

# Step 3: disable and stop all affected services
Write-Step 'Stopping services...'
foreach ($name in $stopOrder) {
    Set-StartupTypeSafe -Name $name -StartupType 'Disabled'
    Stop-ServiceSafe -Name $name
}
Write-OK

try {
    # Step 4: delete the corrupt AppX deployment state database
    # Windows automatically recreates StateRepository-Deployment.srd on the next package operation
    Write-Step 'Deleting StateRepository-Deployment.srd...'
    if (Test-Path -LiteralPath $stateRepoFile) {
        Remove-Item -LiteralPath $stateRepoFile -Force
        Write-OK 'deleted'
    } else {
        Write-Skipped 'file not found, already clean'
    }
} finally {
    # Step 5: restore startup types
    # Essential services that were Disabled (e.g. after debloat) get promoted to Manual.
    # Restoring Disabled means the fix only works until the next reboot.
    Write-Step 'Restoring service startup types...'
    $promotions = @()
    foreach ($name in ($allRootServices + $dependents)) {
        $original = $backup[$name]
        if (-not $original) { continue }

        $isEssential = $allRootServices -contains $name
        $target = if ($isEssential -and $original -eq 'Disabled') { 'Manual' } else { $original }
        if ($target -ne $original) { $promotions += $name }
        Set-StartupTypeSafe -Name $name -StartupType $target
    }
    # Print any promotions as sub-notes, then OK
    foreach ($name in $promotions) { Write-SubNote "'$name' was Disabled — promoted to Manual" }
    if ($promotions.Count -gt 0) { Write-Host '       OK' -ForegroundColor Green } else { Write-OK }

    # Step 6: restart StateRepository so AppX operations can proceed immediately
    # Trigger-started services (ClipSVC, AppXSvc) are started by Windows on demand —
    # forcing them here is unnecessary and may fail if no AppX operation is in flight
    Write-Step 'Starting StateRepository...'
    Start-ServiceSafe -Name 'StateRepository'
    Write-OK
}

# Step 7: Gaming Services package check
# If the package is missing entirely, the gaming service binaries don't exist and installs always fail
Write-Step 'Checking Gaming Services package...'
$gsPkg = Get-AppxPackage -Name 'Microsoft.GamingServices' -ErrorAction SilentlyContinue
if ($gsPkg) {
    Write-OK "v$($gsPkg.Version) present"
} else {
    Write-SubNote 'Microsoft.GamingServices not found — attempting reinstall via winget...'
    if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) {
        & winget install --id 'Microsoft.GamingServices' --silent --accept-package-agreements --accept-source-agreements --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host '       OK  (reinstalled)' -ForegroundColor Green
        } else {
            $script:FailureCount++
            Write-Host "       failed  (winget exit $LASTEXITCODE — install manually from the Store)" -ForegroundColor Red
        }
    } else {
        $script:FailureCount++
        Write-Host '       failed  (winget unavailable — install Gaming Services manually from the Store)' -ForegroundColor Red
    }
}

# Step 8: reinstall the Store package
# wsreset.exe -i silently reinstalls the WindowsStore AppX package without opening the Store window.
# This repairs a missing or damaged Store installation — distinct from wsreset.exe (cache clear only).
Write-Step 'Reinstalling Store package via wsreset -i...'
$wsreset = Start-Process -FilePath 'wsreset.exe' -ArgumentList '-i' -Wait -PassThru
if ($wsreset.ExitCode -eq 0) {
    Write-OK
} else {
    Write-Failed "wsreset exit code $($wsreset.ExitCode)"
}

# --- Summary ---
Write-Host ''
Write-Host '  -------------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  All repair steps completed. Please restart your PC.' -ForegroundColor Cyan
Write-Host ''
Write-Host '  If Store or Gaming Services still do not work after' -ForegroundColor White
Write-Host '  restarting, please file a bug report at:' -ForegroundColor White
Write-Host '  https://github.com/Atlas-OS/Atlas/issues' -ForegroundColor Cyan
Write-Host '  -------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

# --- Retry handling ---
# A silent run happens during the playbook, as TrustedInstaller, with no desktop to
# talk to: defer the retry offer to the next interactive logon instead of dropping it.
if ($PromptOnFailure -and $script:FailureCount -gt 0) {
    $prompt = Join-Path $env:windir 'AtlasModules\Scripts\ScriptWrappers\Show-StoreRepairPrompt.ps1'
    if (Test-Path -LiteralPath $prompt -PathType Leaf) {
        if ($Silent) {
            try {
                $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$prompt`""
                $trigger = New-ScheduledTaskTrigger -AtLogOn
                $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                Register-ScheduledTask -TaskName 'Atlas Store Repair Retry' -Action $action -Trigger $trigger `
                    -Settings $set -RunLevel Highest -Force | Out-Null
                Write-Host '  Store repair reported errors; a retry will be offered at next logon.' -ForegroundColor Yellow
            } catch {
                Write-Warning "Could not schedule the Store repair retry: $($_.Exception.Message)"
            }
        } else {
            & $prompt
        }
    }
}

if (-not $Silent) { $null = Read-Host 'Press Enter to exit' }
