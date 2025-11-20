#!/usr/bin/env pwsh
# Resolve-HostnameIP.ps1
# Prompts for a hostname or IP address and resolves to the opposite.

function Test-ValidIP {
    param([string]$InputString)
    
    if ($InputString -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        return $true
    }
    return $false
}

Write-Host "Hostname/IP Resolver" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan
Write-Host ""

$userInput = Read-Host "Enter a computer name or IP address"
$userInput = $userInput.Trim()

if ([string]::IsNullOrEmpty($userInput)) {
    Write-Host "Error: Input cannot be empty." -ForegroundColor Red
    exit 1
}

if (Test-ValidIP $userInput) {
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
            exit 1
        }
    } catch {
        Write-Host "Unable to resolve $userInput to a hostname: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
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
            exit 1
        }
    } catch {
        Write-Host "Unable to resolve $userInput to an IP address: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
