<#
.SYNOPSIS
    Automates the network stack reset procedure documented in Case #002.

.DESCRIPTION
    Resets the Winsock catalog and TCP/IP stack, releases and renews the DHCP
    lease, and flushes the DNS resolver cache. Based on the manual troubleshooting
    steps validated in cases/002-reset-network-settings.md.

    Known issue handled: 'netsh int ip reset' may return "Access is denied" on
    the HKLM\SYSTEM\CurrentControlSet\Control\Nsi registry key even when running
    elevated. This is expected Windows behavior and does not affect the reset of
    the remaining components, so the script logs it as a warning and continues.

.PARAMETER Reboot
    If specified, restarts the computer automatically after the reset completes.

.PARAMETER LogPath
    Path to the log file. Defaults to the user's Desktop.

.EXAMPLE
    .\Reset-NetworkStack.ps1
    Runs the reset and reports the result without rebooting.

.EXAMPLE
    .\Reset-NetworkStack.ps1 -Reboot
    Runs the reset and restarts the machine automatically after 10 seconds.

.NOTES
    Author: Ruben Rocha
    Related case: cases/002-reset-network-settings.md
#>

[CmdletBinding()]
param(
    [switch]$Reboot,
    [string]$LogPath = "$env:USERPROFILE\Desktop\network-reset-log.txt"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogPath -Value $line
    switch ($Level) {
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        default   { Write-Host $Message }
    }
}

# --- Pre-flight: confirm elevation ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "Script must be run as Administrator. Aborting." "ERROR"
    exit 1
}

Write-Log "=== Starting network stack reset (Case #002 procedure) ===" "INFO"

$steps = @(
    @{ Name = "Release IP configuration";  Command = { ipconfig /release } },
    @{ Name = "Flush DNS resolver cache";  Command = { ipconfig /flushdns } },
    @{ Name = "Reset Winsock catalog";     Command = { netsh winsock reset } },
    @{ Name = "Reset TCP/IP stack";        Command = { netsh int ip reset } },
    @{ Name = "Renew IP configuration";    Command = { ipconfig /renew } }
)

foreach ($step in $steps) {
    Write-Log "Running: $($step.Name)" "INFO"
    try {
        $output = & $step.Command 2>&1
        if ($output -match "Access is denied") {
            Write-Log "$($step.Name) completed with a known, non-blocking warning (Access is denied on Nsi registry key). Continuing." "WARNING"
        } else {
            Write-Log "$($step.Name) completed successfully." "SUCCESS"
        }
    }
    catch {
        Write-Log "$($step.Name) failed unexpectedly: $_" "ERROR"
    }
}

# --- Verification: does it actually work now? ---
Write-Log "Verifying connectivity..." "INFO"
$pingResult = Test-Connection -ComputerName 8.8.8.8 -Count 2 -Quiet -ErrorAction SilentlyContinue

if ($pingResult) {
    Write-Log "Verification passed: 8.8.8.8 is reachable. Issue resolved." "SUCCESS"
}
else {
    Write-Log "Verification failed: 8.8.8.8 is still unreachable. A restart is required to fully apply the TCP/IP reset, or escalate the case." "WARNING"
}

Write-Log "=== Network stack reset finished. Log saved to $LogPath ===" "INFO"

if ($Reboot) {
    Write-Log "Restarting in 10 seconds to finalize the reset..." "WARNING"
    shutdown /r /t 10
}
else {
    Write-Host "`nA restart is recommended to fully apply the reset. Re-run with -Reboot to do this automatically." -ForegroundColor Cyan
}