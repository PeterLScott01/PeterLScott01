#!/usr/bin/env bash
set -euo pipefail

# ontap_shutdown_pair.sh
# Minimal CLI to shut down a two-node NetApp HA pair via SSH.
# By default this is a dry-run (prints the commands). Use --confirm to execute.

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --nodes node1,node2    Comma-separated node hostnames or IPs (order matters)
  --node1 NODE --node2 NODE  Alternative to --nodes
  --nodes-file FILE      File with two nodes, one per line
  --ssh-user USER        SSH user (default: admin)
  --ssh-key PATH         SSH private key file (optional)
  --wait SECONDS         Seconds to wait between halting node1 and node2 (default: 10)
  --confirm              Required to actually execute. Without it the script prints the commands.
  --force                Skip interactive YES prompt when executing (implies --confirm)
  --help                 Show this help and exit

Examples:
  Dry-run (print commands):
    $0 --nodes a0-01,a0-02

  Execute (interactive confirmation required):
    $0 --nodes a0-01,a0-02 --ssh-user admin --ssh-key ~/.ssh/id_netapp --confirm

  Execute non-interactively:
    $0 --nodes-file nodes.txt --ssh-user admin --ssh-key ~/.ssh/id_netapp --force

EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

NODES=""
NODE1=""
NODE2=""
NODES_FILE=""
SSH_USER="admin"
SSH_KEY=""
WAIT_SECS=10
CONFIRM=false
FORCE=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --nodes) NODES="$2"; shift 2;;
    --node1) NODE1="$2"; shift 2;;
    --node2) NODE2="$2"; shift 2;;
    --nodes-file) NODES_FILE="$2"; shift 2;;
    --ssh-user) SSH_USER="$2"; shift 2;;
    --ssh-key) SSH_KEY="$2"; shift 2;;
    --wait) WAIT_SECS="$2"; shift 2;;
    --confirm) CONFIRM=true; shift;;
    --force) FORCE=true; CONFIRM=true; shift;;
    --help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

if [ -n "$NODES_FILE" ]; then
  if [ ! -f "$NODES_FILE" ]; then
    echo "Nodes file not found: $NODES_FILE" >&2; exit 2
  fi
  mapfile -t tmp < <(sed '/^\s*#/d;/^\s*$/d' "$NODES_FILE")
  if [ "${#tmp[@]}" -lt 2 ]; then
    echo "Nodes file must contain two nodes (one per line)." >&2; exit 2
  fi
  NODE1="${tmp[0]}"
  NODE2="${tmp[1]}"
fi

if [ -n "$NODES" ]; then
  IFS=',' read -r -a arr <<< "$NODES"
  if [ "${#arr[@]}" -ne 2 ]; then
    echo "--nodes requires exactly two nodes separated by a comma." >&2; exit 2
  fi
  NODE1="${arr[0]}"
  NODE2="${arr[1]}"
fi

if [ -n "$NODE1" ] && [ -n "$NODE2" ]; then
  : # ok
else
  echo "Two nodes must be specified (use --nodes, --node1/--node2, or --nodes-file)." >&2
  exit 2
fi

ONTAP_CMD='system node halt -node {node}'

echo "Node1: $NODE1"
echo "Node2: $NODE2"
echo "SSH user: $SSH_USER"
echo "Wait between nodes: ${WAIT_SECS}s"

if ! $CONFIRM; then
  echo
  echo "DRY-RUN: the following commands would be executed in order:" 
  echo "  ${ONTAP_CMD//\{node\}/$NODE1}"
  echo "  (wait ${WAIT_SECS}s)"
  echo "  ${ONTAP_CMD//\{node\}/$NODE2}"
  echo
  echo "Re-run with --confirm (or --force) to execute."
  exit 0
fi

if [ "$FORCE" = false ]; then
  read -p "Type YES to proceed with halting both nodes: " reply
  if [ "$reply" != "YES" ]; then
    echo "Aborted by user."; exit 1
  fi
fi

run_cmd() {
  local node="$1"
  local cmd=${ONTAP_CMD//\{node\}/$node}
  echo "+ $node: $cmd"
  if [ -n "$SSH_KEY" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=15 -i "$SSH_KEY" "$SSH_USER@$node" "$cmd"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_USER@$node" "$cmd"
  fi
}

echo
echo "Halting node: $NODE1"
if run_cmd "$NODE1"; then
  echo "Node $NODE1 halt command succeeded."
else
  echo "Node $NODE1 halt command failed." >&2
  exit 3
fi

echo "Waiting ${WAIT_SECS}s before halting node $NODE2..."
sleep "$WAIT_SECS"

echo "Halting node: $NODE2"
if run_cmd "$NODE2"; then
  echo "Node $NODE2 halt command succeeded."
else
  echo "Node $NODE2 halt command failed." >&2
  exit 4
fi

echo "Both halt commands completed. Verify cluster status in the management console."
