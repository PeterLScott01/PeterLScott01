#!/usr/bin/env bash
set -euo pipefail

# hostname_ip_resolver.sh
# Prompts for a hostname or IP address and resolves to the opposite.

is_valid_ip() {
  local ip="$1"
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    return 0
  fi
  return 1
}

echo "Hostname/IP Resolver"
echo "===================="
echo

read -p "Enter a computer name or IP address: " input
input=$(echo "$input" | xargs)  # trim whitespace

if [ -z "$input" ]; then
  echo "Error: Input cannot be empty." >&2
  exit 1
fi

if is_valid_ip "$input"; then
  echo "Input detected as IP address: $input"
  echo
  echo "Resolving to hostname..."
  if hostname=$(host "$input" 2>/dev/null | grep -oP '(?<=pointer )\S+' | sed 's/\.$//' | head -1); then
    if [ -n "$hostname" ]; then
      echo "Result: $hostname"
    else
      echo "No hostname found for $input"
      exit 1
    fi
  else
    echo "Unable to resolve $input to a hostname (reverse DNS lookup failed)."
    exit 1
  fi
else
  echo "Input detected as hostname: $input"
  echo
  echo "Resolving to IP address..."
  if ip=$(getent hosts "$input" 2>/dev/null | awk '{print $1}' | head -1); then
    if [ -n "$ip" ]; then
      echo "Result: $ip"
    else
      echo "No IP address found for $input"
      exit 1
    fi
  else
    echo "Unable to resolve $input to an IP address."
    exit 1
  fi
fi
