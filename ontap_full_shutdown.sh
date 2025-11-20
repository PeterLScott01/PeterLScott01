#!/usr/bin/env bash
set -euo pipefail

# ontap_full_shutdown.sh
# Minimal script to shut down NetApp ONTAP nodes via SSH.
# WARNING: This will halt nodes. Use in maintenance windows only.

usage() {
  cat <<EOF
Usage: $0 --nodes node1,node2 [options]

Options:
  --nodes LIST        Comma-separated list of node hostnames or management IPs
  --nodes-file FILE   File with one node per line (optional)
  --ssh-user USER     SSH user (default: admin)
  --ssh-key PATH      SSH private key file (optional)
  --parallel N        Parallel SSH sessions (default: 4)
  --confirm           Required to actually execute shutdowns
  --help              Show this help and exit

Example:
  $0 --nodes a0-01,a0-02 --ssh-user admin --ssh-key ~/.ssh/id_netapp --confirm

EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

NODES=""
NODES_FILE=""
SSH_USER="admin"
SSH_KEY=""
CONFIRM=false
PARALLEL=4

while [ "$#" -gt 0 ]; do
  case "$1" in
    --nodes) NODES="$2"; shift 2;;
    --nodes-file) NODES_FILE="$2"; shift 2;;
    --ssh-user) SSH_USER="$2"; shift 2;;
    --ssh-key) SSH_KEY="$2"; shift 2;;
    --parallel) PARALLEL="$2"; shift 2;;
    --confirm) CONFIRM=true; shift;;
    --help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

if [ -n "$NODES_FILE" ]; then
  if [ ! -f "$NODES_FILE" ]; then
    echo "Nodes file not found: $NODES_FILE" >&2; exit 2
  fi
  mapfile -t file_nodes < <(sed '/^\s*#/d;/^\s*$/d' "$NODES_FILE")
  NODES=$(IFS=,; echo "${file_nodes[*]}")
fi

if [ -z "$NODES" ]; then
  echo "No nodes specified. Use --nodes or --nodes-file." >&2; exit 2
fi

IFS=',' read -r -a NODE_ARR <<< "$NODES"

# ONTAP node shutdown command (default)
ONTAP_CMD='system node halt -node {node}'

echo "Nodes: ${NODE_ARR[*]}"
echo "Parallel: $PARALLEL"

if ! $CONFIRM; then
  echo
  echo "Dry-run: the following commands would be executed to halt nodes:" 
  for n in "${NODE_ARR[@]}"; do
    echo "${ONTAP_CMD//\{node\}/$n}"
  done
  echo
  echo "To actually execute, re-run with --confirm"
  exit 0
fi

read -p "Type YES to proceed with halting ${#NODE_ARR[@]} nodes: " reply
if [ "$reply" != "YES" ]; then
  echo "Aborted by user."; exit 1
fi

failed=0
sem=""

run_for_node() {
  local node="$1"
  local cmd=${ONTAP_CMD//\{node\}/$node}
  echo "+ $node: $cmd"
  if [ -n "$SSH_KEY" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=15 -i "$SSH_KEY" "$SSH_USER@$node" "$cmd"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_USER@$node" "$cmd"
  fi
}

# simple parallel runner using background jobs
active=0
for n in "${NODE_ARR[@]}"; do
  (
    if run_for_node "$n"; then
      echo "< $n: SUCCESS"
    else
      echo "< $n: FAILED" >&2
      exit 2
    fi
  ) &
  active=$((active+1))
  # throttle
  while [ "$active" -ge "$PARALLEL" ]; do
    wait -n || true
    active=$((active-1))
  done
done

wait
echo "Shutdown commands completed. Verify cluster state in the management console." 

