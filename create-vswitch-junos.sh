#!/bin/bash

VMSTORAGE="local-lvm"
GATEWAY="10.250.249.254"
QCOW2_PATH="/root/download/vJunos-switch-25.2R1.9.qcow2"
MAKESCRIPT_PATH="./make-config-25.2R1.9.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$#" -ne 4 ]; then
    echo -e "${YELLOW}Error: Invalid number of arguments.${NC}"
    echo "Usage: $0 <VM_ID> <VM_NAME> <IP_ADDRESS> <SSH_PASSWORD>"
    echo "Example: $0 400 vjunos-switch-1 10.250.249.175 example_password"
    exit 1
fi

VMID=$1
VMNAME=$2
IP_ADDR=$3
PASSWORD=$4

SALT=$(openssl rand -base64 6 | tr -dc 'a-zA-Z0-9' | cut -c1-8)
HASH=$(python3 -c "import crypt; print(crypt.crypt('${PASSWORD}', '\$6\$${SALT}'))")


if [ ! -f "$QCOW2_PATH" ]; then
    echo -e "${RED}Error: qcow2 image not found at path: $QCOW2_PATH${NC}"
    exit 1
fi
if [ ! -f "$MAKESCRIPT_PATH" ]; then
    echo -e "${RED}Error: make-config.sh script not found in the current directory.${NC}"
    exit 1
fi

echo -e "${GREEN}>>> Starting creation of VM: ${VMNAME} (ID: ${VMID}) with IP: ${IP_ADDR}${NC}"


echo -e "${GREEN}>>> Generating juniper.conf file...${NC}"
cat <<EOF > juniper.conf
system {
    host-name ${VMNAME};
    root-authentication {
        encrypted-password "${HASH}";
    }
    services {
        ssh {
            root-login allow;
        }
    }
    management-instance;
    name-server {
        8.8.8.8;
    }
}
interfaces {
    fxp0 {
        unit 0 {
            family inet {
                address ${IP_ADDR}/24;
            }
        }
    }
}
routing-instances {
    mgmt_junos {
        routing-options {
            static {
                route 0.0.0.0/0 next-hop ${GATEWAY};
            }
        }
    }
}
protocols {
    lldp {
        interface all;
    }
}
EOF

chmod 777 ${MAKESCRIPT_PATH}
./${MAKESCRIPT_PATH} juniper.conf myconfig.img



echo -e "${GREEN}>>> Creating new VM...${NC}"
qm create ${VMID} --name ${VMNAME} --memory 5120 --cores 4 \
--args "-machine accel=kvm:tcg -smbios type=1,product=VM-VEX -cpu 'host,kvm=on'" \
--boot order=virtio0 --serial0 socket \
--net0 virtio,bridge=vmbr0 \
--net1 virtio,bridge=ge000,firewall=0 \
--net2 virtio,bridge=ge001,firewall=0 \
--net3 virtio,bridge=ge002,firewall=0 

echo -e "${GREEN}>>> Importing the vJunos image...${NC}"
qm disk import ${VMID} ${QCOW2_PATH} ${VMSTORAGE} --format qcow2
VMIMAGE=$(qm config ${VMID} | grep "unused0:" | awk '{print $2}')
qm set ${VMID} --virtio0 ${VMIMAGE},iothread=1,size=32G


echo -e "${GREEN}>>> Importing the junos config image to proxmox storage...${NC}"
qm disk import ${VMID} myconfig.img ${VMSTORAGE} --format raw
VMIMAGE_CONF=$(qm config ${VMID} | grep "unused0:" | awk '{print $2}')
qm set ${VMID} --ide0 ${VMIMAGE_CONF},size=16M

echo -e "${GREEN}>>> Starting VM ${VMNAME}...${NC}"
qm start ${VMID}

echo -e "${YELLOW}>>> Waiting 15 seconds for network interfaces to initialize...${NC}"
sleep 15

echo -e "${YELLOW}>>> Applying post-boot network tweaks (LLDP/LACP)...${NC}"


cat <<'EOF' > vm-bridge-update.sh
#!/bin/bash
# use API to get first nodename
pvesh get /nodes --output-format json | jq -r '.[].node' >nodes.txt
VMNODE=`cat nodes.txt | head -1`
echo 'We run this on node: '$VMNODE
# use API to get nic interfaces of our VM
pvesh get /nodes/$VMNODE/qemu/$1/status/current --output-format json | jq -r '.nics | keys[]' >/tmp/vminterfacelist.txt
# ignore first interface fxp0
cat /tmp/vminterfacelist.txt | tail -n +2 >/tmp/vminterfacelist2.txt
#cat /tmp/vminterfacelist2.txt
while IFS= read -r line
do
  INTERFACE="$line"
  #echo $INTERFACE
  BRIDGE=`find /sys/devices/virtual/net -name $INTERFACE | grep '/brif/' | sed 's/\// /g' | awk '{print $5}'`
  # change MTU to higher value
  RUNME="ip link set dev "$INTERFACE" mtu 9200"
  echo $RUNME
  eval $RUNME
  # enable LLDP and 802.1x on bridge
  RUNME="echo 65528 > /sys/class/net/"$BRIDGE"/bridge/group_fwd_mask"
  echo $RUNME
  eval $RUNME
  # enable LACP on link
  RUNME="echo 16388 > /sys/class/net/"$INTERFACE"/brport/group_fwd_mask"
  echo $RUNME
  eval $RUNME
done < /tmp/vminterfacelist2.txt
num=0
while IFS= read -r line
do
  INTERFACE="$line"
  BRIDGE=`find /sys/devices/virtual/net -name $INTERFACE | grep '/brif/' | sed 's/\// /g' | awk '{print $5}'`
  MTU=`cat /sys/class/net/$BRIDGE/mtu`
  if [ "$MTU" != "9200" ]; then
    echo 'Warning! Bridge:'$BRIDGE' did not follow new MTU setting of interface:'$INTERFACE' check other interfaces attached to same bridge and correct please!'
    num=1
  fi
done < /tmp/vminterfacelist2.txt
exit $num
EOF


chmod +x vm-bridge-update.sh
./vm-bridge-update.sh ${VMID}


echo -e "${GREEN}>>> Cleaning up temporary files...${NC}"
rm juniper.conf myconfig.img vm-bridge-update.sh

echo -e "${GREEN}>>> Finished! Machine ${VMNAME} (ID: ${VMID}) has been started.${NC}"

