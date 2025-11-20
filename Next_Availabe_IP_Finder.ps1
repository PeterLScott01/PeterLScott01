# IP Range Finder Script
# Finds available IP addresses in a specified range and returns the count requested

Clear-Host

function ConvertIPtoInteger {
    param([string]$IP)
    $parts = $IP.Split('.')
    return ([long][int]$parts[0] * 16777216) + ([long][int]$parts[1] * 65536) + ([long][int]$parts[2] * 256) + [long][int]$parts[3]
}

function ConvertIntegertoIP {
    param([long]$Integer)
    $octet1 = [int]($Integer / 16777216) % 256
    $octet2 = [int]($Integer / 65536) % 256
    $octet3 = [int]($Integer / 256) % 256
    $octet4 = [int]$Integer % 256
    return "$octet1.$octet2.$octet3.$octet4"
}

function Test-IPAddress {
    param([string]$IP)
    
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $timeout = 500
        $result = $ping.Send($IP, $timeout)
        
        # Only return true if we get a Success response
        # TimedOut, Unreachable, etc. mean the IP is available for use
        if ($result.Status -eq "Success") {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        # If there's any exception, the IP is not responding (available)
        return $false
    }
}

# Main Script Logic
Write-Host "IP Range Finder - Find Available IPs Based on Ping Results" -ForegroundColor Cyan
Write-Host "=========================================================`n" -ForegroundColor Cyan

# Get number of IPs needed
$countNeeded = Read-Host "How many available IP addresses do you need?"

# Validate input
while (-not [int]::TryParse($countNeeded, [ref]$null) -or [int]$countNeeded -le 0) {
    Write-Host "Please enter a valid positive number." -ForegroundColor Red
    $countNeeded = Read-Host "How many available IP addresses do you need?"
}

$countNeeded = [int]$countNeeded

# Get IP range
$startIP = Read-Host "Enter the start IP address"
$endIP = Read-Host "Enter the end IP address"

# Validate IP format
function Test-IPFormat {
    param([string]$IP)
    return $IP -match '^(\d{1,3}\.){3}\d{1,3}$' -and ($IP.Split('.') | ForEach-Object { [int]$_ -le 255 })
}

while (-not (Test-IPFormat $startIP)) {
    Write-Host "Invalid IP format. Please enter a valid IP address (e.g., 192.168.1.1)" -ForegroundColor Red
    $startIP = Read-Host "Enter the start IP address"
}

while (-not (Test-IPFormat $endIP)) {
    Write-Host "Invalid IP format. Please enter a valid IP address (e.g., 192.168.1.254)" -ForegroundColor Red
    $endIP = Read-Host "Enter the end IP address"
}

# Extract network info from start IP (treat as /24)
$startParts = $startIP.Split('.')
# Removed unused $networkPrefix variable since it was assigned but never used

# Convert IPs to integers for range calculation
$startInt = ConvertIPtoInteger $startIP
$endInt = ConvertIPtoInteger $endIP

# Ensure start is before end
if ($startInt -gt $endInt) {
    $temp = $startInt
    $startInt = $endInt
    $endInt = $temp
    Write-Host "Start IP was greater than end IP. Swapped the values.`n" -ForegroundColor Yellow
}

Write-Host "`nScanning IP range from $startIP to $endIP..." -ForegroundColor Green
Write-Host "Looking for $countNeeded available IP(s)...`n" -ForegroundColor Green

$availableIPs = @()
$checkedCount = 0

# Scan through the range sequentially
for ($current = $startInt; $current -le $endInt; $current++) {
    # Stop if we've found enough IPs
    if ($availableIPs.Count -ge $countNeeded) {
        break
    }
    
    $ip = ConvertIntegertoIP $current
    
    Write-Host "Checking $ip..." -ForegroundColor Gray -NoNewline
    
    if (-not (Test-IPAddress $ip)) {
        Write-Host " [AVAILABLE - No Response]" -ForegroundColor Green
        $availableIPs += $ip
    }
    else {
        Write-Host " [In Use]" -ForegroundColor Red
    }
    
    $checkedCount++
    
    # Progress indicator
    if ($checkedCount % 10 -eq 0) {
        Write-Host "  (Checked $checkedCount IPs, Found $($availableIPs.Count) available)`n" -ForegroundColor Cyan
    }
}

# Display Results
Write-Host "`n=========================================================`n" -ForegroundColor Cyan
Write-Host "RESULTS:" -ForegroundColor Cyan
Write-Host "---------" -ForegroundColor Cyan

if ($availableIPs.Count -gt 0) {
    Write-Host "Found $($availableIPs.Count) available IP address(es):" -ForegroundColor Green
    $availableIPs | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
}
else {
    Write-Host "No available IP addresses found in the specified range." -ForegroundColor Red
}

Write-Host "`nTotal IPs checked: $checkedCount" -ForegroundColor Cyan
Write-Host "Total IPs available: $($availableIPs.Count)" -ForegroundColor Cyan

if ($availableIPs.Count -lt $countNeeded) {
    Write-Host "Note: Only found $($availableIPs.Count) of $countNeeded requested IP(s)" -ForegroundColor Yellow
}

# Export option
Write-Host "`n=========================================================`n" -ForegroundColor Cyan
$exportChoice = Read-Host "Would you like to export results to a text file? (Y/N)"

if ($exportChoice -eq "Y" -or $exportChoice -eq "y") {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "Available_IPs_$timestamp.txt"
    $filePath = Join-Path (Get-Location) $fileName
    
    # Create the export content
    $exportContent = @()
    $exportContent += "IP Range Finder - Results Export"
    $exportContent += "=================================="
    $exportContent += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $exportContent += "Scan Range: $startIP to $endIP"
    $exportContent += "IPs Requested: $countNeeded"
    $exportContent += "Total IPs Checked: $checkedCount"
    $exportContent += "Total IPs Available: $($availableIPs.Count)"
    $exportContent += ""
    $exportContent += "Available IP Addresses:"
    $exportContent += "----------------------"
    
    if ($availableIPs.Count -gt 0) {
        $exportContent += $availableIPs
    }
    else {
        $exportContent += "No available IP addresses found."
    }
    
    # Write to file
    $exportContent | Out-File -FilePath $filePath -Encoding UTF8
    
    Write-Host "Results exported to: $filePath" -ForegroundColor Green
}
else {
    Write-Host "Export cancelled." -ForegroundColor Yellow
}
