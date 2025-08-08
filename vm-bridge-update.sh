#!/bin/bash
[ -z "$1" ] && { echo "Usage: $0 <vmid>"; exit 1; }

for cmd in jq pvesh ip; do
  command -v "$cmd" >/dev/null || { echo "Error: $cmd not found"; exit 1; }
done

VMID="$1"
VMNODE=$(pvesh get /nodes --output-format json | jq -r '.[].node' | head -1)

pvesh get /nodes/$VMNODE/qemu/$VMID/status/current --output-format json | \
jq -r '.nics | keys[]' | tail -n +2 | \
while IFS= read -r INTERFACE; do
  BRIDGE=$(find /sys/devices/virtual/net -name "$INTERFACE" | grep '/brif/' | sed 's/\// /g' | awk '{print $5}')
  
  echo "Tweaking interface: $INTERFACE (bridge: $BRIDGE)"
  ip link set dev "$INTERFACE" mtu 9200
  
  [[ -f /sys/class/net/"$BRIDGE"/bridge/group_fwd_mask ]] && echo 65528 > /sys/class/net/"$BRIDGE"/bridge/group_fwd_mask
  [[ -f /sys/class/net/"$INTERFACE"/brport/group_fwd_mask ]] && echo 16388 > /sys/class/net/"$INTERFACE"/brport/group_fwd_mask
done
echo "All interfaces updated to MTU 9200 and group_fwd_mask set."