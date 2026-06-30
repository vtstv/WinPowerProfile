# Copyright (c) 2025 Murr (https://github.com/vtstv)
# Licensed under MIT License

#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 Power Profile Manager — CPU Boost, Thermals & Power Plan Control
.DESCRIPTION
    Safe, menu-driven tool to switch between Economy / Balanced / Performance / Turbo
    presets, and to fine-tune individual power settings. All changes are reversible.
.PARAMETER Toggle
    Toggle between Economy and Balanced presets without showing the menu.
.NOTES
    Run as Administrator. Tested on Windows 10 21H2+ and Windows 11.
    Author  : PowerProfile Manager
    Version : 1.3.0
.EXAMPLE
    PowerProfile.ps1
    Run interactive menu
.EXAMPLE
    PowerProfile.ps1 -Toggle
    Toggle between Economy and Balanced modes
#>

param(
    [Parameter(Position=0)]
    [switch]$Toggle
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Colour palette ────────────────────────────────────────────────────────────
$C = @{
    Title   = 'Cyan'
    Header  = 'Yellow'
    Good    = 'Green'
    Warn    = 'DarkYellow'
    Bad     = 'Red'
    Dim     = 'DarkGray'
    Normal  = 'White'
    Accent  = 'Magenta'
}

# ─── PERFBOOSTMODE constants ────────────────────────────────────────────────────
$BOOST = @{
    Disabled            = 0
    Enabled             = 1   # Default on AC
    Aggressive          = 2
    EfficientEnabled    = 3
    EfficientAggressive = 4
    AggressiveAtGuaranteed = 5
    EfficientAggressiveAtGuaranteed = 6
}

$BOOST_LABEL = @{
    0 = 'Disabled             (coolest / lowest power)'
    1 = 'Enabled              (default AC behaviour)'
    2 = 'Aggressive           (max performance, most heat)'
    3 = 'Efficient Enabled    (boost only when efficient)'
    4 = 'Efficient Aggressive (boost aggressively but efficiently)'
    5 = 'Aggressive At Guaranteed'
    6 = 'Efficient Aggressive At Guaranteed'
}

# ─── Preset definitions ─────────────────────────────────────────────────────────
# Each preset: [BoostAC, BoostDC, MinCpuAC%, MaxCpuAC%, MinCpuDC%, MaxCpuDC%,
#               SystemCoolPolicy(0=passive/1=active), MonitorTimeoutAC(min), SleepTimeoutAC(min)]
$PRESETS = [ordered]@{
    '1' = @{
        Name            = 'Economy / Silent'
        Description     = 'Boost OFF · CPU capped 80% · passive · coolest & quietest'
        BoostAC         = $BOOST.Disabled
        BoostDC         = $BOOST.Disabled
        MinCpuAC        = 5
        MaxCpuAC        = 80
        MinCpuDC        = 5
        MaxCpuDC        = 60
        CoolPolicy      = 0   # passive
        MonitorAC       = 15
        SleepAC         = 30
        UsbSelectiveSuspend = 1
    }
    '2' = @{
        Name            = 'Eco-Balanced'
        Description     = 'Boost OFF · CPU 100% · active cooling · cool & responsive'
        BoostAC         = $BOOST.Disabled
        BoostDC         = $BOOST.Disabled
        MinCpuAC        = 5
        MaxCpuAC        = 100
        MinCpuDC        = 5
        MaxCpuDC        = 80
        CoolPolicy      = 1   # active - prevent thermal throttling
        MonitorAC       = 10
        SleepAC         = 30
        UsbSelectiveSuspend = 1
    }
    '3' = @{
        Name            = 'Balanced'
        Description     = 'Boost Efficient · CPU 100% · passive · Windows default'
        BoostAC         = $BOOST.EfficientEnabled
        BoostDC         = $BOOST.EfficientEnabled
        MinCpuAC        = 5
        MaxCpuAC        = 100
        MinCpuDC        = 5
        MaxCpuDC        = 80
        CoolPolicy      = 0   # passive
        MonitorAC       = 10
        SleepAC         = 30
        UsbSelectiveSuspend = 1
    }
    '4' = @{
        Name            = 'Performance'
        Description     = 'Boost Aggressive · CPU 100% · active · great for workloads'
        BoostAC         = $BOOST.Aggressive
        BoostDC         = $BOOST.Enabled
        MinCpuAC        = 20
        MaxCpuAC        = 100
        MinCpuDC        = 10
        MaxCpuDC        = 100
        CoolPolicy      = 1   # active
        MonitorAC       = 20
        SleepAC         = 0   # never
        UsbSelectiveSuspend = 0
    }
    '5' = @{
        Name            = 'Turbo / Gaming'
        Description     = 'Boost Efficient-Aggressive · CPU 100% · active · max performance'
        BoostAC         = $BOOST.EfficientAggressive
        BoostDC         = $BOOST.Aggressive
        MinCpuAC        = 100
        MaxCpuAC        = 100
        MinCpuDC        = 50
        MaxCpuDC        = 100
        CoolPolicy      = 1   # active
        MonitorAC       = 0   # never
        SleepAC         = 0   # never
        UsbSelectiveSuspend = 0
    }
}

# ─── Helpers ────────────────────────────────────────────────────────────────────

function Require-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = [Security.Principal.WindowsPrincipal]$id
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "`n  [!] This script must be run as Administrator." -ForegroundColor $C.Bad
        Write-Host "      Right-click PowerShell → 'Run as administrator', then try again.`n" -ForegroundColor $C.Warn
        exit 1
    }
}

function Get-ActiveScheme {
    $line = powercfg /getactivescheme
    if ($line -match 'Power Scheme GUID:\s+([\w-]+)\s+\((.+)\)') {
        return @{ GUID = $Matches[1]; Name = $Matches[2] }
    }
    return @{ GUID = ''; Name = 'Unknown' }
}

function Get-PowerValue {
    param([string]$Sub, [string]$Setting)
    try {
        $raw = powercfg /query scheme_current $Sub $Setting 2>$null
        $acLine = $raw | Where-Object { $_ -match 'Current AC Power Setting Index' }
        $dcLine = $raw | Where-Object { $_ -match 'Current DC Power Setting Index' }
        
        $acVal = $null
        $dcVal = $null
        
        if ($acLine -and $acLine -match '0x([0-9a-f]+)') { 
            $acVal = [Convert]::ToInt32($Matches[1], 16) 
        }
        if ($dcLine -and $dcLine -match '0x([0-9a-f]+)') { 
            $dcVal = [Convert]::ToInt32($Matches[1], 16) 
        }
        
        return @{ AC = $acVal; DC = $dcVal }
    } catch { 
        return @{ AC = $null; DC = $null } 
    }
}

function Set-PowerValue {
    param([string]$Sub, [string]$Setting, [int]$AC, [int]$DC)
    try {
        powercfg /setacvalueindex scheme_current $Sub $Setting $AC 2>&1 | Out-Null
        powercfg /setdcvalueindex scheme_current $Sub $Setting $DC 2>&1 | Out-Null
    } catch {
        # Silently ignore if setting doesn't exist on this system
    }
}

function Commit-Scheme {
    powercfg /setactive scheme_current | Out-Null
}

function Show-Banner {
    Clear-Host
    $banner = @"

  ╔══════════════════════════════════════════════════════════════╗
  ║     Windows 11  ·  Power Profile Manager  v1.3  ·  By Murr   ║
  ╚══════════════════════════════════════════════════════════════╝
"@
    Write-Host $banner -ForegroundColor $C.Title
}

function Show-CurrentStatus {
    $scheme = Get-ActiveScheme
    $boost  = Get-PowerValue 'sub_processor' 'PERFBOOSTMODE'
    $minAC  = Get-PowerValue 'sub_processor' 'PROCTHROTTLEMIN'
    $maxAC  = Get-PowerValue 'sub_processor' 'PROCTHROTTLEMAX'
    $cool   = Get-PowerValue 'sub_processor' 'SYSCOOLPOL'
    $usb    = Get-PowerValue 'sub_sleep'     '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

    Write-Host "  ── Current Status ──────────────────────────────────────────────" -ForegroundColor $C.Header
    Write-Host ("  Active plan  : {0}  [{1}]" -f $scheme.Name, $scheme.GUID) -ForegroundColor $C.Normal

    $boostAcLabel = if ($null -ne $boost.AC -and $BOOST_LABEL.ContainsKey($boost.AC)) { $BOOST_LABEL[$boost.AC] } else { "n/a" }
    $boostDcLabel = if ($null -ne $boost.DC -and $BOOST_LABEL.ContainsKey($boost.DC)) { $BOOST_LABEL[$boost.DC] } else { "n/a" }

    $boostColor = if ($boost.AC -eq 0) { $C.Warn } elseif ($boost.AC -ge 2) { $C.Good } else { $C.Normal }
    Write-Host ("  CPU Boost AC : {0}"   -f $boostAcLabel) -ForegroundColor $boostColor
    Write-Host ("  CPU Boost DC : {0}"   -f $boostDcLabel) -ForegroundColor $C.Dim
    Write-Host ("  CPU Min  AC  : {0} %  |  DC: {1} %" -f $minAC.AC, $minAC.DC) -ForegroundColor $C.Normal
    Write-Host ("  CPU Max  AC  : {0} %  |  DC: {1} %" -f $maxAC.AC, $maxAC.DC) -ForegroundColor $C.Normal

    $coolLabel = if ($cool.AC -eq 1) { 'Active (fan-first)' } elseif ($cool.AC -eq 0) { 'Passive (throttle-first)' } else { 'n/a' }
    Write-Host ("  Cooling Mode : {0}"   -f $coolLabel) -ForegroundColor $C.Normal

    $usbLabel = if ($usb.AC -eq 0) { 'Disabled (always on)' } elseif ($usb.AC -eq 1) { 'Enabled (power saving)' } else { 'n/a' }
    Write-Host ("  USB Suspend  : {0}"   -f $usbLabel) -ForegroundColor $C.Dim
    Write-Host ""
}

function Apply-Preset {
    param([hashtable]$P, [switch]$Silent)

    if (-not $Silent) {
        Write-Host ("`n  Applying preset: {0} …" -f $P.Name) -ForegroundColor $C.Accent
    }

    # CPU Boost
    Set-PowerValue 'sub_processor' 'PERFBOOSTMODE'   $P.BoostAC  $P.BoostDC

    # CPU throttle min/max
    Set-PowerValue 'sub_processor' 'PROCTHROTTLEMIN' $P.MinCpuAC $P.MinCpuDC
    Set-PowerValue 'sub_processor' 'PROCTHROTTLEMAX' $P.MaxCpuAC $P.MaxCpuDC

    # Cooling policy
    Set-PowerValue 'sub_processor' 'SYSCOOLPOL'      $P.CoolPolicy $P.CoolPolicy

    # Monitor timeout (0 = never)
    Set-PowerValue 'sub_video' '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' ($P.MonitorAC * 60) ($P.MonitorAC * 60)

    # Sleep timeout (0 = never)
    Set-PowerValue 'sub_sleep' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' ($P.SleepAC * 60) ($P.SleepAC * 60)

    # USB Selective Suspend
    Set-PowerValue 'sub_sleep' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' $P.UsbSelectiveSuspend $P.UsbSelectiveSuspend

    Commit-Scheme

    if (-not $Silent) {
        Write-Host ("  ✔  {0} applied successfully." -f $P.Name) -ForegroundColor $C.Good
        Start-Sleep -Milliseconds 800
    }
}

function Menu-Presets {
    Show-Banner
    Show-CurrentStatus
    Write-Host "  ── Quick Presets ───────────────────────────────────────────────" -ForegroundColor $C.Header
    foreach ($key in $PRESETS.Keys) {
        $p = $PRESETS[$key]
        Write-Host ("  [{0}]  {1,-22}  {2}" -f $key, $p.Name, $p.Description) -ForegroundColor $C.Normal
    }
    Write-Host "  [B]  Back to main menu" -ForegroundColor $C.Dim
    Write-Host ""
    $choice = Read-Host "  Select preset"
    if ($PRESETS.Contains($choice)) {
        Apply-Preset -P $PRESETS[$choice]
    }
}

function Menu-BoostOnly {
    Show-Banner
    Show-CurrentStatus
    Write-Host "  ── CPU Boost Mode (AC) ─────────────────────────────────────────" -ForegroundColor $C.Header
    foreach ($k in ($BOOST_LABEL.Keys | Sort-Object)) {
        Write-Host ("  [{0}]  {1}" -f $k, $BOOST_LABEL[$k]) -ForegroundColor $C.Normal
    }
    Write-Host "  [B]  Back" -ForegroundColor $C.Dim
    Write-Host ""
    $choice = Read-Host "  Select boost mode"
    if ($choice -match '^\d+$' -and $BOOST_LABEL.ContainsKey([int]$choice)) {
        $val = [int]$choice
        # Same value for DC unless it's Aggressive — protect battery
        $dcVal = if ($val -ge 2) { [math]::Min($val, $BOOST.Enabled) } else { $val }
        Set-PowerValue 'sub_processor' 'PERFBOOSTMODE' $val $dcVal
        Commit-Scheme
        Write-Host ("  ✔  Boost set to: {0}" -f $BOOST_LABEL[$val]) -ForegroundColor $C.Good
        Start-Sleep -Milliseconds 800
    }
}

function Menu-CoolingPolicy {
    Show-Banner
    Show-CurrentStatus
    Write-Host "  ── System Cooling Policy ───────────────────────────────────────" -ForegroundColor $C.Header
    Write-Host "  [0]  Passive — throttle CPU first, then spin fans (quieter)"    -ForegroundColor $C.Normal
    Write-Host "  [1]  Active  — spin fans first, throttle later (cooler CPU)"    -ForegroundColor $C.Normal
    Write-Host "  [B]  Back"                                                       -ForegroundColor $C.Dim
    Write-Host ""
    $choice = Read-Host "  Select"
    if ($choice -in '0','1') {
        Set-PowerValue 'sub_processor' 'SYSCOOLPOL' ([int]$choice) ([int]$choice)
        Commit-Scheme
        $label = if ($choice -eq '1') { 'Active' } else { 'Passive' }
        Write-Host ("  ✔  Cooling policy set to: {0}" -f $label) -ForegroundColor $C.Good
        Start-Sleep -Milliseconds 800
    }
}

function Menu-SleepDisplay {
    Show-Banner
    Show-CurrentStatus
    Write-Host "  ── Monitor & Sleep Timeouts (AC) ───────────────────────────────" -ForegroundColor $C.Header
    Write-Host "  Enter 0 to disable (never sleep / never turn off display)." -ForegroundColor $C.Dim
    Write-Host ""

    $monRaw   = Read-Host "  Monitor off after  (minutes, Enter to skip)"
    $sleepRaw = Read-Host "  System sleep after (minutes, Enter to skip)"

    $changed = $false
    if ($monRaw -match '^\d+$') {
        $sec = [int]$monRaw * 60
        Set-PowerValue 'sub_video' '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' $sec $sec
        $changed = $true
    }
    if ($sleepRaw -match '^\d+$') {
        $sec = [int]$sleepRaw * 60
        Set-PowerValue 'sub_sleep' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' $sec $sec
        $changed = $true
    }
    if ($changed) {
        Commit-Scheme
        Write-Host "  ✔  Timeouts updated." -ForegroundColor $C.Good
    } else {
        Write-Host "  No changes made." -ForegroundColor $C.Dim
    }
    Start-Sleep -Milliseconds 800
}

function Menu-UsbSuspend {
    Show-Banner
    Show-CurrentStatus
    Write-Host "  ── USB Selective Suspend ───────────────────────────────────────" -ForegroundColor $C.Header
    Write-Host "  [0]  Disabled — USB devices always powered (gaming/audio gear)"  -ForegroundColor $C.Normal
    Write-Host "  [1]  Enabled  — Windows may suspend idle USB ports (save power)" -ForegroundColor $C.Normal
    Write-Host "  [B]  Back"                                                        -ForegroundColor $C.Dim
    Write-Host ""
    $choice = Read-Host "  Select"
    if ($choice -in '0','1') {
        # USB Selective Suspend GUID
        Set-PowerValue 'sub_sleep' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' ([int]$choice) ([int]$choice)
        Commit-Scheme
        $label = if ($choice -eq '0') { 'Disabled' } else { 'Enabled' }
        Write-Host ("  ✔  USB Selective Suspend: {0}" -f $label) -ForegroundColor $C.Good
        Start-Sleep -Milliseconds 800
    }
}

function Restore-WindowsDefaults {
    Show-Banner
    Write-Host ""
    Write-Host "  This will restore the 'Balanced' Windows defaults on the active scheme." -ForegroundColor $C.Warn
    $confirm = Read-Host "  Type YES to confirm"
    if ($confirm -eq 'YES') {
        # Boost: Enabled on AC, Enabled on DC
        Set-PowerValue 'sub_processor' 'PERFBOOSTMODE'   1   1
        # CPU min/max defaults
        Set-PowerValue 'sub_processor' 'PROCTHROTTLEMIN' 5   5
        Set-PowerValue 'sub_processor' 'PROCTHROTTLEMAX' 100 100
        # Cooling: passive
        Set-PowerValue 'sub_processor' 'SYSCOOLPOL'      0   0
        # Monitor: 10 min AC, 5 min DC
        Set-PowerValue 'sub_video' '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' 600 300
        # Sleep: 30 min AC, 15 min DC
        Set-PowerValue 'sub_sleep' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' 1800 900
        # USB suspend: enabled
        Set-PowerValue 'sub_sleep' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 1 1
        Commit-Scheme
        Write-Host "  ✔  Windows defaults restored." -ForegroundColor $C.Good
    } else {
        Write-Host "  Cancelled." -ForegroundColor $C.Dim
    }
    Start-Sleep -Milliseconds 800
}

function Export-CurrentSettings {
    $scheme = Get-ActiveScheme
    $exportDir = "$env:USERPROFILE\Documents\PowerProfiles"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }
    
    $outFile = "$exportDir\PowerProfile_Backup_$(Get-Date -f 'yyyyMMdd_HHmmss').pow"
    try {
        powercfg /export $outFile $scheme.GUID | Out-Null
        Write-Host ("  ✔  Plan exported to:`n     {0}" -f $outFile) -ForegroundColor $C.Good
    } catch {
        Write-Host "  Export failed: $_" -ForegroundColor $C.Bad
    }
    Start-Sleep -Milliseconds 1200
}

function Import-PowerPlan {
    $exportDir = "$env:USERPROFILE\Documents\PowerProfiles"
    
    Show-Banner
    Write-Host ""
    Write-Host "  ── Import Power Plan (.pow) ────────────────────────────────────" -ForegroundColor $C.Header
    Write-Host ""
    
    # Check if directory exists and has .pow files
    if (Test-Path $exportDir) {
        $powFiles = @(Get-ChildItem -Path $exportDir -Filter "*.pow" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        
        if ($powFiles.Count -gt 0) {
            Write-Host "  Available power plans in Documents\PowerProfiles:" -ForegroundColor $C.Normal
            Write-Host ""
            
            for ($i = 0; $i -lt $powFiles.Count; $i++) {
                $file = $powFiles[$i]
                $date = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                Write-Host ("  [{0}]  {1,-50}  ({2})" -f ($i+1), $file.Name, $date) -ForegroundColor $C.Normal
            }
            Write-Host ""
            Write-Host "  [C]  Choose custom file path" -ForegroundColor $C.Dim
            Write-Host "  [B]  Back to main menu" -ForegroundColor $C.Dim
            Write-Host ""
            
            $choice = Read-Host "  Select file to import"
            
            if ($choice -match '^\d+$') {
                $index = [int]$choice - 1
                if ($index -ge 0 -and $index -lt $powFiles.Count) {
                    $selectedFile = $powFiles[$index].FullName
                    Import-PowerPlanFile $selectedFile
                } else {
                    Write-Host "  Invalid selection." -ForegroundColor $C.Warn
                    Start-Sleep -Milliseconds 800
                }
            } elseif ($choice -eq 'C') {
                $customPath = Read-Host "  Enter full path to .pow file"
                if (Test-Path $customPath) {
                    Import-PowerPlanFile $customPath
                } else {
                    Write-Host "  File not found." -ForegroundColor $C.Bad
                    Start-Sleep -Milliseconds 800
                }
            }
        } else {
            Write-Host "  No .pow files found in Documents\PowerProfiles." -ForegroundColor $C.Warn
            Write-Host ""
            $customPath = Read-Host "  Enter full path to .pow file (or press Enter to cancel)"
            if ($customPath -and (Test-Path $customPath)) {
                Import-PowerPlanFile $customPath
            } else {
                Write-Host "  Import cancelled." -ForegroundColor $C.Dim
                Start-Sleep -Milliseconds 800
            }
        }
    } else {
        Write-Host "  Documents\PowerProfiles folder not found." -ForegroundColor $C.Warn
        Write-Host ""
        $customPath = Read-Host "  Enter full path to .pow file (or press Enter to cancel)"
        if ($customPath -and (Test-Path $customPath)) {
            Import-PowerPlanFile $customPath
        } else {
            Write-Host "  Import cancelled." -ForegroundColor $C.Dim
            Start-Sleep -Milliseconds 800
        }
    }
}

function Import-PowerPlanFile {
    param([string]$FilePath)
    
    Write-Host ""
    Write-Host "  Importing power plan from:" -ForegroundColor $C.Accent
    Write-Host ("  {0}" -f $FilePath) -ForegroundColor $C.Dim
    Write-Host ""
    
    try {
        # Import the power plan
        $output = powercfg /import $FilePath 2>&1
        
        # Extract the GUID from the output
        if ($output -match 'GUID:\s+([\w-]+)') {
            $newGuid = $Matches[1]
            Write-Host "  ✔  Power plan imported successfully." -ForegroundColor $C.Good
            Write-Host ("     GUID: {0}" -f $newGuid) -ForegroundColor $C.Dim
            Write-Host ""
            
            $activate = Read-Host "  Activate this plan now? (Y/N)"
            if ($activate -eq 'Y' -or $activate -eq 'y') {
                powercfg /setactive $newGuid | Out-Null
                Write-Host "  ✔  Power plan activated." -ForegroundColor $C.Good
            } else {
                Write-Host "  Plan imported but not activated. Use Windows Power Options to activate it." -ForegroundColor $C.Dim
            }
        } else {
            Write-Host "  ✔  Power plan imported (GUID not detected in output)." -ForegroundColor $C.Good
        }
    } catch {
        Write-Host "  Import failed: $_" -ForegroundColor $C.Bad
    }
    
    Start-Sleep -Milliseconds 1500
}

function Show-MainMenu {
    Show-Banner
    Show-CurrentStatus
    Write-Host "  ── Main Menu ───────────────────────────────────────────────────" -ForegroundColor $C.Header
    Write-Host "  [1]  Apply Quick Preset      (Economy / Eco-Balanced / Balanced / Performance / Turbo)" -ForegroundColor $C.Normal
    Write-Host "  [2]  Change CPU Boost Mode   (fine-grained boost control)"               -ForegroundColor $C.Normal
    Write-Host "  [3]  Cooling Policy          (passive / active)"                         -ForegroundColor $C.Normal
    Write-Host "  [4]  Monitor & Sleep Timeouts"                                           -ForegroundColor $C.Normal
    Write-Host "  [5]  USB Selective Suspend"                                              -ForegroundColor $C.Normal
    Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor $C.Dim
    Write-Host "  [R]  Restore Windows Balanced Defaults"                                  -ForegroundColor $C.Warn
    Write-Host "  [E]  Export current power plan (Documents\PowerProfiles)"                -ForegroundColor $C.Dim
    Write-Host "  [I]  Import power plan from .pow file"                                   -ForegroundColor $C.Dim
    Write-Host "  [Q]  Quit"                                                               -ForegroundColor $C.Dim
    Write-Host ""
}

function Detect-CurrentPreset {
    <#
    .SYNOPSIS
        Attempts to detect which preset is currently active based on power settings.
    .DESCRIPTION
        Compares current power settings with preset definitions to identify the active preset.
        Returns '1' for Economy, '2' for Eco-Balanced, '3' for Balanced, etc.
    #>
    
    $maxAC  = Get-PowerValue 'sub_processor' 'PROCTHROTTLEMAX'
    $minAC  = Get-PowerValue 'sub_processor' 'PROCTHROTTLEMIN'
    
    # Detect based on CPU limits
    if ($maxAC.AC -eq 80 -and $minAC.AC -eq 5) { 
        return '1'  # Economy
    }
    
    if ($maxAC.AC -eq 100 -and $minAC.AC -eq 5) { 
        $boost = Get-PowerValue 'sub_processor' 'PERFBOOSTMODE'
        if ($null -ne $boost.AC -and $boost.AC -eq 0) {
            return '2'  # Eco-Balanced (boost disabled)
        }
        return '3'  # Balanced (boost enabled or default behavior)
    }
    
    # Fallback: if max CPU is 80% or less, assume Economy
    if ($maxAC.AC -le 80) { 
        return '1'
    }
    
    # Default to Balanced if uncertain
    return '3'
}

function Switch-EconomyBalanced {
    <#
    .SYNOPSIS
        Toggle between Economy and Balanced presets.
    #>
    
    $current = Detect-CurrentPreset
    
    if ($current -eq '1') {
        # Currently Economy, switch to Balanced
        $target = $PRESETS['3']
        Write-Host "`n  Switching from Economy to Balanced..." -ForegroundColor $C.Accent
    } else {
        # Currently Balanced (or other), switch to Economy
        $target = $PRESETS['1']
        Write-Host "`n  Switching from Balanced to Economy..." -ForegroundColor $C.Accent
    }
    
    Apply-Preset -P $target -Silent
    
    Write-Host ("  ✔  Switched to: {0}" -f $target.Name) -ForegroundColor $C.Good
    Write-Host ""
    
    Start-Sleep -Milliseconds 1500
}

# ─── Entry point ────────────────────────────────────────────────────────────────

Require-Admin

# Check for toggle mode via flag file or parameter
$toggleFlagFile = "$env:TEMP\PowerProfile_ToggleMode.flag"
$shouldToggle = $Toggle -or (Test-Path $toggleFlagFile)

if ($shouldToggle) {
    # Remove flag file if it exists
    if (Test-Path $toggleFlagFile) {
        Remove-Item $toggleFlagFile -Force -ErrorAction SilentlyContinue
    }
    
    Switch-EconomyBalanced
    exit 0
}

while ($true) {
    Show-MainMenu
    $choice = (Read-Host "  Select option").Trim().ToUpper()
    
    # Process menu choice
    if ($choice -eq '1') { Menu-Presets }
    elseif ($choice -eq '2') { Menu-BoostOnly }
    elseif ($choice -eq '3') { Menu-CoolingPolicy }
    elseif ($choice -eq '4') { Menu-SleepDisplay }
    elseif ($choice -eq '5') { Menu-UsbSuspend }
    elseif ($choice -eq 'R') { Restore-WindowsDefaults }
    elseif ($choice -eq 'E') { Export-CurrentSettings }
    elseif ($choice -eq 'I') { Import-PowerPlan }
    elseif ($choice -eq 'Q') { Write-Host "`n  Goodbye.`n" -ForegroundColor $C.Dim; exit 0 }
    else { Write-Host "  Invalid option." -ForegroundColor $C.Warn; Start-Sleep -Milliseconds 500 }
}