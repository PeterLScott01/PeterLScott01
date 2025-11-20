#!/usr/bin/env pwsh
# Resolve-HostnameIP.ps1
# Prompts for a hostname or IP address and resolves to the opposite.

Clear-Host

function Test-ValidIP {
    param([string]$InputString)
    
    if ($InputString -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        return $true
    }
    return $false
}

while ($true) {
    Clear-Host
    Write-Host "Hostname/IP Resolver" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    Write-Host ""

    $userInput = Read-Host "Enter a computer name or IP address (or 'q' to quit)"
    if ($null -eq $userInput) { $userInput = "" }
    $userInput = $userInput.Trim()

    if ([string]::IsNullOrEmpty($userInput)) {
        Write-Host "Error: Input cannot be empty." -ForegroundColor Red
    } elseif ($userInput -eq 'q' -or $userInput -eq 'Q') {
        break
    } elseif (Test-ValidIP $userInput) {
        Write-Host "Input detected as IP address: $userInput" -ForegroundColor Green
        Write-Host ""
        Write-Host "Resolving to hostname..."
        
        try {
            $hostEntry = [System.Net.Dns]::GetHostEntry($userInput)
            $hostname = $hostEntry.HostName
            
            if ($hostname) {
                Write-Host "Result: $hostname" -ForegroundColor Yellow
            } else {
                Write-Host "No hostname found for $userInput" -ForegroundColor Yellow
            }
        } catch {
            $origMsg = $_.Exception.Message
            Write-Host "Primary reverse lookup failed: $origMsg" -ForegroundColor DarkYellow

            if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
                try {
                    $octets = $userInput.Split('.')
                    [array]::Reverse($octets)
                    $arpa = ($octets -join '.') + '.in-addr.arpa'
                    $ptr = (Resolve-DnsName -Name $arpa -Type PTR -ErrorAction Stop | Select-Object -First 1).NameHost
                    if ($ptr) {
                        Write-Host "PTR Result: $ptr" -ForegroundColor Yellow
                    } else {
                        Write-Host "No PTR record found for $userInput" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "PTR lookup also failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                try {
                    $nsOutput = (nslookup -type=ptr $userInput 2>&1) -join "`n"
                    if ($nsOutput -match 'name =\s*(\S+)') {
                        $ptrName = $Matches[1]
                        Write-Host "PTR Result: $ptrName" -ForegroundColor Yellow
                    } elseif ($nsOutput -match 'NXDOMAIN' -or $nsOutput -match "can't find" -or $nsOutput -match 'Non-existent domain') {
                        Write-Host "No PTR record found for $userInput" -ForegroundColor Yellow
                    } else {
                        Write-Host "nslookup output:" -ForegroundColor Yellow
                        Write-Host $nsOutput -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "Unable to run nslookup for PTR lookup: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "Input detected as hostname: $userInput" -ForegroundColor Green
        Write-Host ""
        Write-Host "Resolving to IP address..."
        
        try {
            $hostEntry = [System.Net.Dns]::GetHostAddresses($userInput)
            
            if ($hostEntry -and $hostEntry.Count -gt 0) {
                $ip = $hostEntry[0].IPAddressToString
                Write-Host "Result: $ip" -ForegroundColor Yellow
            } else {
                Write-Host "No IP address found for $userInput" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Unable to resolve $userInput to an IP address: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    $choice = Read-Host "Press Enter to run again, or type 'q' then Enter to quit"
    if ($choice -eq 'q' -or $choice -eq 'Q') { break }
}
