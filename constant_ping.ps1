<#
.SYNOPSIS
Continuously ping a host and optionally log results.

.DESCRIPTION
Pings the given host at a configurable interval, prints timestamped results,
and optionally writes them to a log file. Press 'q' to quit interactively.

.EXAMPLE
pwsh ./constant_ping.ps1

.EXAMPLE
pwsh ./constant_ping.ps1 -HostName LEXPORTPRC13.psihq.local -Interval 2 -LogFile ping.log
#>

param(
    [Parameter(Position=0,Mandatory=$false)]
    [string]$HostName,

    [Parameter(Mandatory=$false)]
    [int]$Interval = 1,

    [Parameter(Mandatory=$false)]
    [string]$LogFile
)

function Write-Log {
    param([string]$Line)
    Write-Host $Line
    if ($LogFile) { Add-Content -Path $LogFile -Value $Line }
}

Clear-Host

if (-not $HostName) {
    $HostName = Read-Host "Enter the IP address or hostname to ping"
}

if ([string]::IsNullOrWhiteSpace($HostName)) {
    Write-Host "Error: No host specified." -ForegroundColor Red
    exit 1
}

Write-Host "Starting continuous ping to: $HostName (interval: $Interval s)" -ForegroundColor Cyan
if ($LogFile) { Write-Host "Logging to: $LogFile" -ForegroundColor Cyan }
Write-Host "Press 'q' to quit." -ForegroundColor Yellow

try {
    while ($true) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        try {
            $reply = Test-Connection -ComputerName $HostName -Count 1 -ErrorAction Stop
            # Test-Connection returns objects; use first reply
            if ($reply) {
                $addr = $reply.Address
                $rtt = $reply.ResponseTime
                $line = "$timestamp`tReply from ${addr}: time=${rtt}ms"
            } else {
                $line = "$timestamp`tNo reply from $HostName"
            }
        } catch {
            $line = "$timestamp\tNo reply from $HostName ($($_.Exception.Message))"
        }

        Write-Log $line

        # Check for 'q' keypress without blocking
        if ([console]::KeyAvailable) {
            $key = [console]::ReadKey($true)
            if ($key.Key -eq 'Q') { break }
        }

        Start-Sleep -Seconds $Interval
    }
} catch [System.Exception] {
    Write-Host "Ping loop interrupted: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host "Stopped pinging $HostName" -ForegroundColor Cyan
}
