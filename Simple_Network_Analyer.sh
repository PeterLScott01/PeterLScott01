#!/bin/bash

clear

# Description: Cross-platform script for Hostname/IP resolution, path tracing, and local AD context.
# Compatibility: macOS (Darwin), Linux, and Windows (via Git Bash/WSL/MSYS2).

# Define global variables
OS_NAME=$(uname -s)
IP_ADDRESS="N/A"
HOSTNAME_R="N/A"
INPUT_VALUE=""

# Local Network Details
LOCAL_IP="N/A"
SUBNET_MASK="N/A"
GATEWAY="N/A"
DNS_SERVERS=""
DOMAIN_NAME="N/A"

# --- 1. Remote Resolution (IP <=> Hostname) ---

resolve_host_ip() {
    local input_value=$1

    # Check if the input is an IP address using a basic regex match
    if [[ $input_value =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Input is IP, perform reverse lookup for Hostname
        HOSTNAME_R=$(host -r "$input_value" | awk '/name/ {print $NF}' | sed 's/\.$//')
        IP_ADDRESS="$input_value"
        
        # Handle cases where reverse lookup fails
        if [ "$HOSTNAME_R" == "3(PTR)?" ] || [ -z "$HOSTNAME_R" ]; then
            echo "Warning: No reverse DNS (PTR record) found for IP."
            HOSTNAME_R="[No reverse DNS record found]"
        fi
    else
        # Input is Hostname, perform forward lookup for IP
        IP_ADDRESS=$(host "$input_value" | awk '/has address/ {print $4; exit}')
        HOSTNAME_R="$input_value"
        
        if [ -z "$IP_ADDRESS" ]; then
            echo "Error: Could not resolve Hostname to IP. Check spelling or connectivity."
            return 1 # Return non-zero to indicate resolution failure
        fi
    fi
    echo "Resolution Successful!"
    return 0
}

# --- 2. Local Machine Context (Subnet, Gateway, DNS, Domain) ---

get_local_machine_details() {
    echo "Gathering local system and network configuration..."

    if [[ "$OS_NAME" == "Darwin" ]]; then
        # --- macOS (Darwin) ---
        
        # Default Gateway & Local IP
        GATEWAY=$(netstat -rn | awk '/default/ {print $2; exit}')
        LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
        
        # DNS Servers
        DNS_SERVERS=$(scutil --dns | grep 'nameserver\[[0-9]\]' | awk '{print $NF}' | sort -u | tr '\n' ' ')

        # Subnet Mask (Requires Python for hex conversion on macOS)
        local active_interface=$(netstat -rn | awk '/default/ {print $6; exit}')
        if [ -n "$active_interface" ]; then
            local hex_mask=$(ifconfig "$active_interface" 2>/dev/null | awk '/netmask/ {print $4}')
            if [ -n "$hex_mask" ] && command -v python3 &> /dev/null; then
                # Convert hex mask to dotted decimal using Python
                SUBNET_MASK=$(echo "$hex_mask" | xargs python3 -c 'import sys; print(".".join([str(int(h, 16)) for h in sys.argv[1][2:].zfill(8)]))' 2>/dev/null)
            fi
        fi

        # AD Domain Name (using dsconfigad)
        DOMAIN_NAME=$(dsconfigad -show 2>/dev/null | awk '/Domain Name/ {print $NF}')
        
    elif [[ "$OS_NAME" == "MINGW"* || "$OS_NAME" == "MSYS"* ]]; then
        # --- Windows (Running via Git Bash/MSYS2) ---
        echo "Detected Windows-like environment. Using ipconfig.exe and net config..."
        
        local IPCONFIG_OUTPUT=$(ipconfig.exe /all 2>/dev/null)
        
        # Parse for Local IP, Gateway, Subnet, and DNS
        LOCAL_IP=$(echo "$IPCONFIG_OUTPUT" | grep -i "IPv4 Address" | awk -F': ' '{print $2}' | tr -d '\r' | cut -d'(' -f1 | head -n 1)
        GATEWAY=$(echo "$IPCONFIG_OUTPUT" | grep -i "Default Gateway" | awk -F': ' '{print $2}' | tr -d '\r' | head -n 1)
        SUBNET_MASK=$(echo "$IPCONFIG_OUTPUT" | grep -i "Subnet Mask" | awk -F': ' '{print $2}' | tr -d '\r' | head -n 1)
        # Handle multi-line DNS output
        DNS_SERVERS=$(echo "$IPCONFIG_OUTPUT" | grep -i "DNS Servers" | awk '{print $NF}' | tr '\n' ' ')
        
        # AD Domain Name (using net config workstation)
        DOMAIN_NAME=$(net config workstation 2>/dev/null | awk -F': ' '/Workstation domain name/ {print $2}' | tr -d '\r')

    elif [[ "$OS_NAME" == "Linux" ]]; then
        # --- Linux (General/WSL) ---
        
        # Default Gateway
        GATEWAY=$(ip route | awk '/default/ {print $3; exit}')
        
        # Local IP (First available IP for default interface)
        LOCAL_IP=$(ip addr | awk '/inet / {print $2}' | head -n 1 | cut -d'/' -f1)

        # DNS Servers
        DNS_SERVERS=$(grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
        
        # Domain Name (Checking /etc/resolv.conf search entry, common in Linux domain joins)
        DOMAIN_NAME=$(grep search /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -n 1)
    fi

    # Set N/A if variables are still empty
    LOCAL_IP=${LOCAL_IP:-N/A}
    GATEWAY=${GATEWAY:-N/A}
    SUBNET_MASK=${SUBNET_MASK:-N/A}
    DOMAIN_NAME=${DOMAIN_NAME:-N/A}
    DNS_SERVERS=${DNS_SERVERS:-N/A}
}

# --- 3. Remote Path Diagnostics (Traceroute) ---

run_traceroute() {
    local target_ip=$1
    echo ""
    echo "--- Remote Path Trace (Traceroute) ---"
    
    # Use 'tracert' on Windows environments and 'traceroute' elsewhere
    if [[ "$OS_NAME" == "MINGW"* || "$OS_NAME" == "MSYS"* ]]; then
        echo "Running tracert.exe..."
        tracert.exe "$target_ip"
    else
        echo "Running traceroute..."
        # Limit the number of hops to 20 for faster output
        traceroute -m 20 "$target_ip"
    fi
    echo "--- End Path Trace ---"
}

# --- 4. Remote Port Diagnostics (TCP Check) ---

check_remote_ports() {
    local target_ip=$1
    echo ""
    echo "--- Remote Port Check (Common AD/Corporate TCP Ports) ---"
    
    # Disclaimer for the user
    echo "NOTE: Scanning all 65535 ports on a remote machine is impractical/blocked."
    echo "We are checking a targeted list of common corporate/AD TCP ports using 'nc'."
    echo "UDP ports are not checked, as their status is difficult to determine reliably."
    
    # List of common AD/corporate related TCP ports
    # 21: FTP, 22: SSH, 23: Telnet, 80: HTTP, 135: RPC, 139: NetBIOS-SSN, 389: LDAP,
    # 443: HTTPS, 445: SMB/AD, 636: LDAPS, 3389: RDP, 5985: WinRM (HTTP), 5986: WinRM (HTTPS)
    local common_ports=( 21 22 23 80 135 139 389 443 445 636 3389 5985 5986 )
    local open_ports=""

    # Check for netcat (nc) availability
    if ! command -v nc &> /dev/null; then
        echo "Error: 'nc' (netcat) not found. Skipping remote port check."
        return 1
    fi

    for port in "${common_ports[@]}"; do
        # Use nc with zero-I/O (-z), verbose (-v), and a short timeout (-w 1)
        # nc exit code 0 usually means success/open.
        if nc -z -w 1 "$target_ip" "$port" &> /dev/null; then
            open_ports+="$port, "
        fi
    done

    echo "Status for: $target_ip"
    echo "----------------------------------------"
    if [ -n "$open_ports" ]; then
        # Remove trailing comma and space
        open_ports="${open_ports%, }"
        echo "Open TCP Ports: ${open_ports}"
    else
        echo "Open Ports: None found in the common list (or they are filtered)."
    fi
    echo "----------------------------------------"
    echo "Ports checked: ${common_ports[*]}"
}

# --- 5. Main Logic ---

main() {
    # Check for required tools (host is crucial for resolution)
    if ! command -v host &> /dev/null; then
        echo "Error: The 'host' command is required but not found (part of dnsutils/bind-utils)."
        exit 1
    fi
    
    # Check for netcat (nc) availability to provide a warning early
    if ! command -v nc &> /dev/null; then
        echo "Warning: 'nc' (netcat) not found. Remote port checking will be skipped."
    fi

    echo "--------------------------------------------------------"
    echo "   Cross-Platform Network & AD Context Analyzer (BASH)  "
    echo "--------------------------------------------------------"
    
    while true; do
        # Reset resolution variables for the new run
        IP_ADDRESS="N/A"
        HOSTNAME_R="N/A"
        
        # Prompt for input (Clear previous argument if it exists, use interactive prompt)
        if [ -n "$1" ]; then
            INPUT_VALUE="$1"
            # Clear argument after first run so subsequent runs use the interactive prompt
            set --
        else
            read -rp "Enter a Hostname (e.g., remote-server.local) or an IP Address: " INPUT_VALUE
        fi

        if [ -z "$INPUT_VALUE" ]; then
            echo "No input provided. Exiting."
            break
        fi
        
        # 1. Resolve Hostname/IP
        if ! resolve_host_ip "$INPUT_VALUE"; then
            # If resolution failed, skip the rest of the loop content and prompt again
            echo "Skipping further analysis due to resolution failure."
            continue
        fi
        
        # 2. Final Output Summary (Remote Target)
        echo ""
        echo "--- Remote Target Resolution ---"
        echo "Input Value:       $INPUT_VALUE"
        echo "Input Type:        $(if [[ "$INPUT_VALUE" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then echo "IP Address"; else echo "Hostname"; fi)"
        echo "----------------------------------------"
        echo "Resolved Hostname: ${HOSTNAME_R}"
        echo "Resolved IP:       ${IP_ADDRESS}"
        echo "----------------------------------------"
        
        # 3. Get and Display Local Machine Context
        get_local_machine_details
        echo ""
        echo "--- Local Machine & AD Context (Machine Running Script) ---"
        echo "OS Detected:       $OS_NAME"
        echo "Local IP Address:  ${LOCAL_IP}"
        echo "Domain Joined:     ${DOMAIN_NAME}"
        echo "Subnet Mask:       ${SUBNET_MASK}"
        echo "Default Gateway:   ${GATEWAY}"
        echo "DNS Servers:       ${DNS_SERVERS}"
        echo "-----------------------------------------------------------"

        # 4. Run Remote Diagnostic
        if [ "$IP_ADDRESS" != "N/A" ] && [ -n "$IP_ADDRESS" ]; then
            run_traceroute "$IP_ADDRESS"
            check_remote_ports "$IP_ADDRESS"
        fi
        
        # 5. Prompt for Re-run
        echo ""
        read -rp "Analysis complete. Run again for a different computer (y/n)? " choice
        case "$choice" in
            [Yy]* )
                clear
                echo "--------------------------------------------------------"
                echo "   Cross-Platform Network & AD Context Analyzer (BASH)  "
                echo "--------------------------------------------------------"
                continue
                ;;
            [Nn]* ) break;;
            * ) echo "Invalid choice. Exiting."; break;;
        esac
    done
}

# Execute main function with arguments
main "$@"
