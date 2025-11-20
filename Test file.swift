//
//  Test file.swift
//  
//
//  Created by Peter L Scott on 11/20/25.
//

<#
.SYNOPSIS
  Query a computer by IP or hostname and display system details.

.DESCRIPTION
  Prompts for an IP or hostname (or accept via -Target), resolves to an address and name,
  then retrieves:
    - IP Address
    - Computer Name
    - Total RAM (GB)
    - Number of Processors (physical CPUs) and logical processors
    - Local Disk sizes (DriveType=3)

.PARAMETER Target
  IP address or hostname. If omitted, the script will prompt.

.EXAMPLE
  .\Get-HostInventory.ps1
  (prompts for IP/hostname)

.EXAMPLE
  .\Get-HostInventory.ps1 -Target "10.0.0.25"

.EXAMPLE
  .\Get-HostInventory.ps1 -Target "SERVER01"
#>

[CmdletBinding()]
param(
    [string]$Target
)

function Resolve-Computer {
    param([string]$InputValue)

    # If it's an IP, try to reverse-resolve a name; if it's a name, resolve IPs.
    try {
        $isIP = [System.Net.IPAddress]::TryParse($InputValue, [ref]([System.Net.IPAddress]::Any))
        if ($isIP) {
            # Reverse lookup
            try {
                $hostEntry = [System.Net.Dns]::GetHostEntry($InputValue)
                $name = $hostEntry.HostName
            } catch {
                $name = $InputValue # If reverse lookup fails, use IP as name
            }
            $ip = $InputValue
        } else {
            # Resolve name to IP
            $hostEntry = [System.Net.Dns]::GetHostEntry($InputValue)
            $ip = ($hostEntry.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).ToString()
            $name = $hostEntry.HostName
        }
        return [pscustomobject]@{ Name = $name; IP = $ip }
    } catch {
        throw "Unable to resolve '$InputValue'. $_"
    }
}

# Prompt if not provided
if (-not $Target -or [string]::IsNullOrWhiteSpace($Target)) {
    $Target = Read-Host "Enter IP address or hostname"
}

# Resolve to name and IP for display
$resolved = Resolve-Computer -InputValue $Target
$computerName = $resolved.Name
$ipAddress    = $resolved.IP

Write-Host "Querying: $computerName ($ipAddress) ..." -ForegroundColor Cyan

# Attempt to connect via CIM (WinRM/WSMan). If that fails, try DCOM fallback.
$cimSession = $null
try {
    $cimOptions = New-CimSessionOption -Protocol Wsman
    $cimSession = New-CimSession -ComputerName $computerName -SessionOption $cimOptions -ErrorAction Stop
} catch {
    try {
        $cimOptions = New-CimSessionOption -Protocol Dcom
        $cimSession = New-CimSession -ComputerName $computerName -SessionOption $cimOptions -ErrorAction Stop
    } catch {
        Write-Warning "Could not create CIM session to $computerName. Attempting local fallback if target is local."
        if ($env:COMPUTERNAME -ieq $computerName -or $computerName -eq 'localhost' -or $ipAddress -eq '127.0.0.1') {
            $cimSession = $null
        } else {
            throw "Unable to connect to $computerName using CIM. $_"
        }
    }
}

try {
    # Computer name (from Win32_ComputerSystem) and memory
    $cs = if ($cimSession) {
        Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $cimSession
    } else {
        Get-CimInstance -ClassName Win32_ComputerSystem
    }

    # Processor info
    $cpu = if ($cimSession) {
        Get-CimInstance -ClassName Win32_Processor -CimSession $cimSession
    } else {
        Get-CimInstance -ClassName Win32_Processor
    }

    # OS memory detail (for free mem if needed; here we focus on total)
    $os = if ($cimSession) {
        Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $cimSession
    } else {
        Get-CimInstance -ClassName Win32_OperatingSystem
    }

    # Local disks (DriveType=3)
    $disks = if ($cimSession) {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -CimSession $cimSession
    } else {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
    }

    # Compute totals
    $totalRAMBytes = [int64]$cs.TotalPhysicalMemory
    $totalRAMGB = [math]::Round($totalRAMBytes / 1GB, 2)

    $physicalCPUCount = ($cpu | Measure-Object -Property SocketDesignation -Unique).Count
    $logicalProcessorCount = ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

    $diskInfo = $disks | Select-Object `
        @{n='Drive';e={$_.DeviceID}},
        @{n='SizeGB';e={[math]::Round(($_.Size / 1GB), 2)}},
        @{n='FreeGB';e={[math]::Round(($_.FreeSpace / 1GB), 2)}}

    # Output nicely
    Write-Host ""
    Write-Host "System Information" -ForegroundColor Green
    Write-Host "------------------"
    Write-Host ("Computer Name     : {0}" -f $cs.Name)
    Write-Host ("Resolved Hostname : {0}" -f $computerName)
    Write-Host ("IP Address        : {0}" -f $ipAddress)
    Write-Host ("Total RAM (GB)    : {0}" -f $totalRAMGB)
    Write-Host ("Processors        : {0} physical, {1} logical" -f $physicalCPUCount, $logicalProcessorCount)
    Write-Host ""
    Write-Host "Local Disks (DriveType=3)" -ForegroundColor Green
    Write-Host "-------------------------"
    foreach ($d in $diskInfo) {
        Write-Host ("{0} : Size {1} GB, Free {2} GB" -f $d.Drive, $d.SizeGB, $d.FreeGB)
    }

    # Optional: return an object for scripting/automation
    [pscustomobject]@{
        ComputerName           = $cs.Name
        ResolvedHostName       = $computerName
        IPAddress              = $ipAddress
        TotalRAM_GB            = $totalRAMGB
        PhysicalCPUCount       = $physicalCPUCount
        LogicalProcessorCount  = $logicalProcessorCount
        Disks                  = $diskInfo
    }

} catch {
    Write-Error "Failed to query $computerName ($ipAddress): $($_.Exception.Message)"
} finally {
    if ($cimSession) {
        $cimSession | Remove-CimSession -ErrorAction SilentlyContinue
    }
}
