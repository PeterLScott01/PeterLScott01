<#
.SYNOPSIS
Prompt for a computer name or IP address and return the opposite lookup.

.DESCRIPTION
This script asks the user for either a hostname or an IP address. If a
hostname is provided it performs a forward DNS lookup and prints IP
addresses. If an IP is provided it performs a reverse lookup and prints
the resolved hostname(s).

.EXAMPLE
.
Run the script and enter either a hostname (e.g. myhost.example.com)
or an IP address (e.g. 10.0.0.5). The script prints the corresponding
addresses or hostnames.
#>

function Resolve-NameOrIP {
	param(
		[Parameter(Position=0, Mandatory=$false)]
		[string]$InputValue
	)

	if (-not $InputValue) {
		$InputValue = Read-Host -Prompt 'Enter a computer name or IP address'
	}

	$ipObj = $null
	$isIp = [System.Net.IPAddress]::TryParse($InputValue, [ref]$ipObj)

	if ($isIp) {
		# Reverse lookup: IP -> Hostname
		try {
			$entry = [System.Net.Dns]::GetHostEntry($InputValue)
			if ($entry -and $entry.HostName) {
				Write-Output "Input detected as IP: $InputValue"
				Write-Output "Resolved Hostname: $($entry.HostName)"
				if ($entry.Aliases -and $entry.Aliases.Length -gt 0) {
					Write-Output "Aliases:"
					$entry.Aliases | ForEach-Object { Write-Output " - $_" }
				}
				if ($entry.AddressList -and $entry.AddressList.Length -gt 0) {
					Write-Output "Address list:"
					$entry.AddressList | ForEach-Object { Write-Output " - $_" }
				}
			}
			else {
				Write-Warning "Reverse lookup returned no hostname for $InputValue"
			}
		}
		catch {
			Write-Warning "Reverse lookup failed for $InputValue : $($_.Exception.Message)"
		}
	}
	else {
		# Forward lookup: Hostname -> IP(s)
		try {
			$addresses = [System.Net.Dns]::GetHostAddresses($InputValue)
			if ($addresses -and $addresses.Length -gt 0) {
				Write-Output "Input detected as Hostname: $InputValue"
				Write-Output "Resolved Addresses:"
				$addresses | ForEach-Object { Write-Output " - $_" }
			}
			else {
				Write-Warning "Forward lookup returned no addresses for $InputValue"
			}
		}
		catch {
			Write-Warning "Forward lookup failed for $InputValue : $($_.Exception.Message)"
		}
	}
}

# Clear the console when the script runs interactively.
Clear-Host

# If the script is dot-sourced we avoid prompting; otherwise call the function.
if ($MyInvocation.InvocationName -eq '.') {
	Write-Verbose 'Script was dot-sourced; running prompt anyway.'
}

Resolve-NameOrIP

