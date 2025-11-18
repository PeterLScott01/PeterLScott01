#!/bin/bash

CLEAR

echo "--- 🕵️ Full Subnet Scanner (IP to MAC & Hostname) ---"

# --- Configuration ---
PING_COUNT=1  # Number of pings to send to each address
PING_TIMEOUT=1 # Timeout in seconds for each ping

# --- 1. Prompt for Input IP Address ---
read -r -p "Enter the IP address of any device on the network (e.g., 192.168.1.5): " INPUT_IP

# --- Input Validation and Subnet Extraction ---
if [ -z "$INPUT_IP" ]; then
    echo "Error: IP address cannot be empty."
    exit 1
fi

# Extract the base subnet (e.g., 192.168.1.)
SUBNET=$(echo "$INPUT_IP" | awk -F'.' '{print $1"."$2"."$3"."}')

if [ "$SUBNET" == ".." ] || [ -z "$SUBNET" ]; then
    echo "Error: Invalid IP address format. Please use standard dotted-decimal notation."
    exit 1
fi

echo "Detected Subnet Base: **$SUBNET**"
echo "--- ⏱️ Pinging all 254 possible addresses. Requires sudo/root... ---"

# --- 2. Preparation (Requires sudo) ---
# Clear the existing ARP cache to ensure a fresh scan
sudo arp -d -a > /dev/null 2>&1

# --- 3. Concurrent Ping Sweep ---
# Loop through all possible host addresses (1 to 254)
for i in {1..254}; do
    IP="$SUBNET$i"
    # Send a single, fast ping to the IP address and discard the output
    # Running in the background (&) significantly speeds up the process.
    ping -c $PING_COUNT -t $PING_TIMEOUT "$IP" > /dev/null 2>&1 &
done

# Wait for all background ping processes to finish
wait

echo "--- ✅ Ping Sweep Complete. Analyzing ARP table and performing reverse lookups... ---"

# --- 4. ARP Table Analysis and Reverse DNS Lookup ---
echo "## 🎯 Active Devices Found on Subnet $SUBNET"

# Create a header
printf "%-15s | %-17s | %s\n" "IP ADDRESS" "MAC ADDRESS" "HOSTNAME"
printf "%s\n" "------------------------------------------------------------------"

# Use the 'arp -a' command to list all devices that responded to the ping.
arp -a | grep -v 'incomplete' | grep -v 'permanent' | grep -v 'localhost' | while read -r LINE; do
    # Extract IP and MAC address
    IP_FOUND=$(echo "$LINE" | awk '{print $2}' | tr -d '()')
    MAC_FOUND=$(echo "$LINE" | awk '{print $4}')

    # Perform Reverse DNS Lookup for the Hostname
    # dig -x is the standard, cross-platform reverse lookup tool
    HOSTNAME_FOUND=$(dig -x "$IP_FOUND" +short | sed 's/\.$//' | head -n 1) # Strip trailing dot

    # Handle empty hostname result
    if [ -z "$HOSTNAME_FOUND" ]; then
        HOSTNAME_FOUND="N/A (No PTR record)"
    fi

    # Display the result in a formatted table row
    if [ -n "$IP_FOUND" ] && [ "$IP_FOUND" != "Address" ]; then
        printf "%-15s | %-17s | %s\n" "$IP_FOUND" "$MAC_FOUND" "$HOSTNAME_FOUND"
    fi
done

echo ""
echo "--- 🏁 Scan Finished ---"
