#!/bin/bash

# Port Scanner Script for macOS
# Prompts for a host (computer name or IP address) and scans common open ports

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Common ports to scan
declare -a PORTS=(
    "22:SSH"
    "80:HTTP"
    "443:HTTPS"
    "445:SMB"
    "3306:MySQL"
    "5432:PostgreSQL"
    "5984:CouchDB"
    "6379:Redis"
    "8080:HTTP-Alternate"
    "8443:HTTPS-Alternate"
    "9200:Elasticsearch"
    "27017:MongoDB"
    "3389:RDP"
    "1433:MSSQL"
    "5900:VNC"
)

# Function to display usage
usage() {
    echo "Usage: $0"
    echo "Script will prompt you for a host to scan"
    exit 1
}

# Function to check if a port is open
check_port() {
    local host=$1
    local port=$2
    local service=$3
    
    # Use timeout to avoid hanging on unreachable hosts
    if timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Port $port ($service) - ${GREEN}OPEN${NC}"
        return 0
    else
        echo -e "${RED}✗${NC} Port $port ($service) - ${RED}CLOSED${NC}"
        return 1
    fi
}

# Main script
echo ""
echo "=========================================="
echo "       macOS Port Scanner"
echo "=========================================="
echo ""

# Prompt for host
read -p "Enter computer name or IP address: " host

# Validate input
if [ -z "$host" ]; then
    echo -e "${RED}Error: Host cannot be empty${NC}"
    exit 1
fi

# Resolve hostname to IP if needed
echo -e "\n${YELLOW}Resolving host...${NC}"
resolved_ip=$(dig +short "$host" | tail -n1)

if [ -z "$resolved_ip" ]; then
    # If dig fails, try nslookup
    resolved_ip=$(nslookup "$host" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}')
fi

if [ -z "$resolved_ip" ]; then
    echo -e "${YELLOW}Could not resolve hostname. Using provided input as IP address.${NC}"
    resolved_ip="$host"
fi

echo -e "Target: ${YELLOW}$host${NC} ($resolved_ip)"
echo ""
echo "Scanning common ports..."
echo "=========================================="
echo ""

# Initialize counters
open_count=0
closed_count=0

# Scan each port
for port_info in "${PORTS[@]}"; do
    port="${port_info%:*}"
    service="${port_info#*:}"
    
    if check_port "$resolved_ip" "$port"; then
        ((open_count++))
    else
        ((closed_count++))
    fi
done

# Summary
echo ""
echo "=========================================="
echo -e "${GREEN}Open ports: $open_count${NC}"
echo -e "${RED}Closed ports: $closed_count${NC}"
echo "=========================================="
echo ""
