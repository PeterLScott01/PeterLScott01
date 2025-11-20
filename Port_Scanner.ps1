Clear-Host

# Port Scanner Script
# Prompts for an IP address and scans for common open ports

function Test-Port {
    param(
        [string]$IPAddress,
        [int]$Port,
        [int]$Timeout = 1000
    )
    
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $tcpClient.BeginConnect($IPAddress, $Port, $null, $null)
    $wait = $asyncResult.AsyncWaitHandle.WaitOne($Timeout, $false)
    
    if ($wait) {
        try {
            $tcpClient.EndConnect($asyncResult)
            return $true
        } catch {
            return $false
        }
    } else {
        return $false
    }
    finally {
        $tcpClient.Close()
    }
}

# Common ports to scan
$commonPorts = @{
    21   = "FTP"
    22   = "SSH"
    23   = "Telnet"
    25   = "SMTP"
    53   = "DNS"
    80   = "HTTP"
    110  = "POP3"
    143  = "IMAP"
    443  = "HTTPS"
    445  = "SMB"
    3306 = "MySQL"
    3389 = "RDP"
    5432 = "PostgreSQL"
    5900 = "VNC"
    8080 = "HTTP Alt"
    8443 = "HTTPS Alt"
}

# Prompt user for IP address or computer name
$target = Read-Host "Enter the IP address or computer name to scan"

# Resolve computer name to IP address if needed
$ipAddress = $target

if ($target -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
    # Attempt to resolve hostname to IP address
    Write-Host "Resolving hostname '$target'..." -ForegroundColor Gray
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($target) | Select-Object -First 1
        if ($resolved) {
            $ipAddress = $resolved.IPAddressToString
            Write-Host "Resolved to $ipAddress`n" -ForegroundColor Green
        } else {
            Write-Host "Could not resolve hostname '$target' to an IP address." -ForegroundColor Red
            exit
        }
    } catch {
        Write-Host "Error resolving hostname '$target': $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
} else {
    # Validate IP address format
    if ($target -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        Write-Host "Invalid IP address or hostname format." -ForegroundColor Red
        exit
    }
}

Write-Host "`nScanning $ipAddress for open ports..." -ForegroundColor Cyan
Write-Host "This may take a moment...`n" -ForegroundColor Gray

$openPorts = @()

foreach ($port in $commonPorts.Keys) {
    Write-Host "Scanning port $port ($($commonPorts[$port]))..." -NoNewline -ForegroundColor Gray
    
    if (Test-Port -IPAddress $ipAddress -Port $port) {
        Write-Host " OPEN" -ForegroundColor Green
        $openPorts += [PSCustomObject]@{
            Port    = $port
            Service = $commonPorts[$port]
            Status  = "OPEN"
        }
    } else {
        Write-Host " CLOSED" -ForegroundColor Red
    }
}

# Display results
Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
Write-Host "Scan Results for $ipAddress" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan

if ($openPorts.Count -gt 0) {
    Write-Host "`nOpen Ports Found: $($openPorts.Count)" -ForegroundColor Green
    $openPorts | Format-Table -AutoSize
} else {
    Write-Host "`nNo open ports found." -ForegroundColor Yellow
}

Write-Host "Scan completed." -ForegroundColor Cyan

# Prompt to save results to file
$saveToFile = Read-Host "`nWould you like to save the results to a file? (Y/N)"

if ($saveToFile -eq "Y" -or $saveToFile -eq "y") {
    # Generate default filename with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $defaultFilename = "PortScan_${ipAddress}_${timestamp}.txt"
    
    $filepath = Read-Host "Enter the file path to save to (default: $defaultFilename)"
    
    # Use default if user pressed enter without input
    if ([string]::IsNullOrWhiteSpace($filepath)) {
        $filepath = $defaultFilename
    }
    
    try {
        # Create the results content
        $resultsContent = @()
        $resultsContent += "=" * 50
        $resultsContent += "Port Scan Results for $ipAddress"
        $resultsContent += "Scan Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $resultsContent += "=" * 50
        $resultsContent += ""
        
        if ($openPorts.Count -gt 0) {
            $resultsContent += "Open Ports Found: $($openPorts.Count)"
            $resultsContent += ""
            foreach ($port in $openPorts) {
                $resultsContent += "Port: $($port.Port) | Service: $($port.Service) | Status: $($port.Status)"
            }
        } else {
            $resultsContent += "No open ports found."
        }
        
        $resultsContent += ""
        $resultsContent += "Scan completed."
        
        # Write to file
        $resultsContent | Out-File -FilePath $filepath -Encoding UTF8
        Write-Host "`nResults saved to: $filepath" -ForegroundColor Green
    } catch {
        Write-Host "`nError saving to file: $($_.Exception.Message)" -ForegroundColor Red
    }
}
