# MIT License
#
# Copyright (c) 2021 AveYo
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

<#
.SYNOPSIS
    Elevates a program to TrustedInstaller context.
.NOTES
    Adapted from https://github.com/AveYo/LeanAndMean, MIT licensed (notice above).
    The embedded snippet tracks upstream commit b0782ef:
    https://github.com/AveYo/LeanAndMean/tree/b0782ef281d64a3dda086de7bada1c02decc7cf9
    Revised and customized for Atlas by he3als and Xyueta.
    Usage: Invoke-TrustedInstaller.ps1 "<executable>" [args]

    ─── Operations requiring elevated access beyond standard admin ────────────────

    1. WSearch registry keys (HKLM:\Software\Microsoft\Windows Search\Gather\...)
       Owned by TrustedInstaller/WSearch. Deny-write to Administrators.
       Bypass: SeTakeOwnershipPrivilege (present in elevated admin tokens).
               Take ownership → grant Administrators SetValue → write value.
       Script: AtlasDesktop\3. General Configuration\Search Indexing\
               Minimal Search Indexing (default).ps1

    2. UserChoice registry keys (HKCU\...\Shell\Associations\*\UserChoice)
       Protected by Windows UCPD with a runtime DENY ACL + hash check.
       Bypass: regini.exe DELETE (signed inbox tool, not on UCPD enforcement list)
               removes the DENY ACL. Recreate key immediately via Win32 registry API
               before Windows re-applies the protection. (~100 ms window.)
       Script: AtlasModules\Scripts\Set-UserFileAssociation.ps1

    3. ActivatableClassId keys (HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\...)
       May be owned by TrustedInstaller on some systems.
       Bypass: best-effort with -ErrorAction SilentlyContinue — not critical.
       Script: AtlasDesktop\3. General Configuration\FSO and Game Bar\*.ps1

    4. C:\Program Files\WindowsApps (AppX package binaries)
       Owned by TrustedInstaller, enforced by SYSTEM ACL.
       Bypass: AME Wizard handles this natively via its own TI context.
       Script: N/A (not handled by Atlas PS scripts)

    5. Install-CbsPackage.ps1
       Must run as TrustedInstaller/SYSTEM — CBS operations require it.
       Bypass: caller must invoke this script via Invoke-TrustedInstaller.ps1.
       Script: AtlasModules\Scripts\Install-CbsPackage.ps1

    ──────────────────────────────────────────────────────────────────────────────
#>

function Invoke-TrustedInstaller ($cmd, $arg) {
    $id  = 'RunAsTI'
    $key = "Registry::HKU\$(((whoami /user) -split ' ')[-1])\Volatile Environment"

    # Runs the target process under the TrustedInstaller token by inheriting its handle.
    # Technique: dynamically define P/Invoke stubs (CreateProcess, RegOpenKeyEx, RegSetValueEx)
    # via Reflection so no Add-Type / C# compilation is needed at runtime.
    # $D = array of dynamically defined value types (structs for STARTUPINFO, PROCESS_INFO, etc.)
    # $T = the finalized/created Type instances from $D
    # $F = P/Invoke signatures: DLL name + parameter type arrays for each native function
    # 0x0E080600 = CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE | CREATE_NEW_PROCESS_GROUP
    #              | EXTENDED_STARTUPINFO_PRESENT (process creation flags for CreateProcess)
    # Obfuscation in the heredoc is intentional — adapted from AveYo/LeanAndMean to evade
    # heuristic AV triggers on string literals like "CreateProcess" and "RegOpenKeyEx".
    $code = @'
 $I=[int32]; $M=$I.module.gettype("System.Runtime.Interop`Services.Mar`shal"); $P=$I.module.gettype("System.Int`Ptr"); $S=[string]
 $D=@(); $T=@(); $DM=[AppDomain]::CurrentDomain."DefineDynami`cAssembly"(1,1)."DefineDynami`cModule"(1); $Z=[uintptr]::size
 0..5|% {$D += $DM."Defin`eType"("AveYo_$_",1179913,[ValueType])}; $D += [uintptr]; 4..6|% {$D += $D[$_]."MakeByR`efType"()}
 $F='kernel','advapi','advapi', ($S,$S,$I,$I,$I,$I,$I,$S,$D[7],$D[8]), ([uintptr],$S,$I,$I,$D[9]),([uintptr],$S,$I,$I,[byte[]],$I)
 0..2|% {$9=$D[0]."DefinePInvok`eMethod"(('CreateProcess','RegOpenKeyEx','RegSetValueEx')[$_],$F[$_]+'32',8214,1,$S,$F[$_+3],1,4)}
 $DF=($P,$I,$P),($I,$I,$I,$I,$P,$D[1]),($I,$S,$S,$S,$I,$I,$I,$I,$I,$I,$I,$I,[int16],[int16],$P,$P,$P,$P),($D[3],$P),($P,$P,$I,$I)
 1..5|% {$k=$_; $n=1; $DF[$_-1]|% {$9=$D[$k]."Defin`eField"('f' + $n++, $_, 6)}}; 0..5|% {$T += $D[$_]."Creat`eType"()}
 0..5|% {nv "A$_" ([Activator]::CreateInstance($T[$_])) -fo}; function F ($1,$2) {$T[0]."G`etMethod"($1).invoke(0,$2)}
 $TI=(whoami /groups)-like'*1-16-16384*'; $As=0; if(!$cmd) {$cmd='control';$arg='admintools'}; if ($cmd-eq'This PC'){$cmd='file:'}
 if (!$TI) {'TrustedInstaller','lsass','winlogon'|% {if (!$As) {$9=sc.exe start $_; $As=@(get-process -name $_ -ea 0|% {$_})[0]}}
 function M ($1,$2,$3) {$M."G`etMethod"($1,[type[]]$2).invoke(0,$3)}; $H=@(); $Z,(4*$Z+16)|% {$H += M "AllocHG`lobal" $I $_}
 M "WriteInt`Ptr" ($P,$P) ($H[0],$As.Handle); $A1.f1=131072; $A1.f2=$Z; $A1.f3=$H[0]; $A2.f1=1; $A2.f2=1; $A2.f3=1; $A2.f4=1
 $A2.f6=$A1; $A3.f1=10*$Z+32; $A4.f1=$A3; $A4.f2=$H[1]; M "StructureTo`Ptr" ($D[2],$P,[boolean]) (($A2 -as $D[2]),$A4.f2,$false)
 $Run=@($null, "powershell -windowstyle $env:RunAsTI_WindowStyle -nop -c iex `$env:R; # $id", 0, 0, 0, 0x0E080600, 0, $null, ($A4 -as $T[4]), ($A5 -as $T[5])) # DevSkim: ignore DS104456
 F 'CreateProcess' $Run; return}; $env:R=''; rp $key $id -force; $priv=[diagnostics.process]."GetM`ember"('SetPrivilege',42)[0]
 'SeSecurityPrivilege','SeTakeOwnershipPrivilege','SeBackupPrivilege','SeRestorePrivilege' |% {$priv.Invoke($null, @("$_",2))}
 $HKU=[uintptr][uint32]2147483651; $NT='S-1-5-18'; $reg=($HKU,$NT,8,2,($HKU -as $D[9])); F 'RegOpenKeyEx' $reg; $LNK=$reg[4]
 function L ($1,$2,$3) {sp 'HKLM:\SOFTWARE\Classes\AppID\{CDCBCFCA-3CDC-436f-A4E2-0E02075250C2}' 'RunAs' $3 -force -ea 0
  $b=[Text.Encoding]::Unicode.GetBytes("\Registry\User\$1"); F 'RegSetValueEx' @($2,'SymbolicLinkValue',0,6,[byte[]]$b,$b.Length)}
 function Q {[int](gwmi win32_process -filter 'name="explorer.exe"'|?{$_.getownersid().sid-eq$NT}|select -last 1).ProcessId}
 $11bug=($((gwmi Win32_OperatingSystem).BuildNumber)-eq'22000')-AND(($cmd-eq'file:')-OR(test-path -lit $cmd -PathType Container))
 if ($11bug) {'System.Windows.Forms','Microsoft.VisualBasic' |% {[Reflection.Assembly]::LoadWithPartialName("'$_")}}
 if ($11bug) {$path='^(l)'+$($cmd -replace '([\+\^\%\~\(\)\[\]])','{$1}')+'{ENTER}'; $cmd='control.exe'; $arg='admintools'}
 L ($key-split'\\')[1] $LNK ''; $R=[diagnostics.process]::start($cmd,$arg); if ($R) {$R.PriorityClass='High'; $R.WaitForExit()}
 if ($11bug) {$w=0; do {if($w-gt40){break}; sleep -mi 250;$w++} until (Q); [Microsoft.VisualBasic.Interaction]::AppActivate($(Q))}
 if ($11bug) {[Windows.Forms.SendKeys]::SendWait($path)}; do {sleep 7} while(Q); L '.Default' $LNK 'Interactive User'
'@
    $V = ''; 'cmd', 'arg', 'id', 'key' | ForEach-Object { $V += "`n`$$_='$($(Get-Variable $_ -ValueOnly) -replace "'","''")';"}
    Set-ItemProperty -Path $key -Name $id -Value $($V, $code) -Type 7 -Force -ErrorAction SilentlyContinue
    Start-Process powershell -Args "-windowstyle $env:RunAsTI_WindowStyle -nop -c ``n$V ``$env:R=(Get-Item ``$key -ea 0).getvalue(``$id)-join''; Invoke-Expression ``$env:R" -Verb RunAs # DevSkim: ignore DS104456
}

$env:RunAsTI_WindowStyle = 'Normal'

if ($args.Count -eq 0) {
    do {
        $inputPath = Read-Host 'Enter the valid path of the program or drag it here'
    } while (-not $inputPath)
    $exe       = $inputPath.Trim('"')
    $arguments = ''
} else {
    $exe       = $args[0]
    $arguments = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] -join ' ' } else { '' }
}

$silentPatterns = @('-silent', '/silent', '-quiet', '/quiet')
if ($silentPatterns | Where-Object { $arguments -match [regex]::Escape($_) }) {
    $env:RunAsTI_WindowStyle = 'Hidden'
}

Try {
    Invoke-TrustedInstaller $exe $arguments
} Catch {
    $uacDeclined = $_ | Select-String -Pattern 'The operation was canceled by the user' -Quiet
    if ($uacDeclined) {
        Write-Host 'UAC prompt was declined. Re-run and select Yes.' -ForegroundColor Red
        exit 2
    } else {
        Write-Host 'Failed to self-elevate (unknown error).' -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
}
