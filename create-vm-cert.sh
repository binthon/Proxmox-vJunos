#!/bin/bash

# ==============================================================================
# Proxmox vJunos VM Creation Script
# ==============================================================================
# This script automates the creation and configuration of a vJunos VM
# on Proxmox VE, based on provided arguments and a default configuration file.
# Addictionally, it handles network interface setup, gRPC/gNMI configuration (certifiations generations and settings) and SNMP settings.

# --- Default Configuration File Path ---
CONFIG_FILE="./config.sh"

# --- Load Default Configuration ---
# Source the configuration file if it exists.
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "\033[0;31mError: Configuration file not found at $CONFIG_FILE\033[0m"
    exit 1
fi

# --- Color Definitions ---
# For formatted output messages.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Help and Usage Function ---
# Displays how to use the script and exits.
usage() {
    echo "Usage: $0 --type <switch|router> --vmid <ID> --name <NAME> --ip <IP> --bridges <LIST> [OPTIONS]"
    echo ""
    echo "Required Arguments:"
    echo "  --type    <type>    Specify the VM type: 'switch' or 'router'."
    echo "  --vmid    <id>      Numeric ID for the new VM."
    echo "  --name    <name>    Hostname for the new VM."
    echo "  --ip      <address> Management IP address for the VM."
    echo "  --bridges <list>    Comma-separated list of Proxmox bridges (e.g., 'ge000,ge002')."
    echo ""
    echo "Optional Arguments:"
    echo "  --ge003-ip <IP>     IP address for ge-0/0/3 (example 192.168.1.175) connections to the metrics server."
    echo "  --ge000-ip <IP>     IP address for ge-0/0/0 (example 192.168.10.175)"
    echo "  --ge001-ip <IP>     IP address for ge-0/0/1 (example 192.168.20.175)"
    echo "  --ge002-ip <IP>     IP address for ge-0/0/2 (example 192.168.30.175)"
    echo "  --memory  <MB>      RAM for the VM in MB (Default from config: ${MEMORY:-N/A})."
    echo "  --cores   <num>     Number of CPU cores (Default from config: ${CORES:-N/A})."
    echo "  --storage <id>      Proxmox storage ID for disks (Default from config: ${VMSTORAGE:-N/A})."
    echo "  -h, --help          Show this help message."
    exit 1
}

# --- Argument Parsing ---
# Initialize variables to be captured from command-line arguments.
TYPE=""
VMID=""
VMNAME=""
IP_ADDR=""
BRIDGES_LIST=""
GE003_IP3=""
GE000_IP=""
GE001_IP=""
GE002_IP=""
# Loop through all provided arguments and assign them to variables.
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --type)     TYPE="$2"; shift ;;
        --vmid)     VMID="$2"; shift ;;
        --name)     VMNAME="$2"; shift ;;
        --ip)       IP_ADDR="$2"; shift ;;
        --bridges)  BRIDGES_LIST="$2"; shift ;;
        --memory)   MEMORY="$2"; shift ;;
        --cores)    CORES="$2"; shift ;;
        --storage)  VMSTORAGE="$2"; shift ;;
        --ge003-ip) GE003_IP="$2"; shift ;;
        --ge000-ip) GE000_IP="$2"; shift ;;
        --ge001-ip) GE001_IP="$2"; shift ;;
        --ge002-ip) GE002_IP="$2"; shift ;;
        -h|--help)  usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done


# --- 0. Validate IP Address Format ---
echo "--> Checking IP address format for ${IP_ADDR}..."
validate_ip() {
    local label="$1"
    local ip="$2"

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                echo -e "${RED}Error: Invalid IP in $label: $ip${NC}"
                exit 1
            fi
        done
        echo "--> IP ($label) is valid: $ip"
    else
        echo -e "${RED}Error: Invalid format for $label: '$ip'. Expected format: 192.168.1.100${NC}"
        exit 1
    fi
}

echo "--> Validating IP addresses..."
validate_ip "Management IP" "$IP_ADDR"

[ -n "$GE000_IP" ] && validate_ip "ge-0/0/0 IP" "$GE000_IP"
[ -n "$GE001_IP" ] && validate_ip "ge-0/0/1 IP" "$GE001_IP"
[ -n "$GE002_IP" ] && validate_ip "ge-0/0/2 IP" "$GE002_IP"
[ -n "$GE003_IP" ] && validate_ip "ge-0/0/3 IP" "$GE003_IP"



# --- 1. Initial Argument Check ---
# Check if all required arguments have been provided.
if [ -z "$TYPE" ] || [ -z "$VMID" ] || [ -z "$VMNAME" ] || [ -z "$IP_ADDR" ] || [ -z "$BRIDGES_LIST" ]; then
    echo -e "${RED}Error: Missing one or more required arguments.${NC}"
    usage
fi

# ==============================================================================
#                      VALIDATION & PREPARATION
# ==============================================================================
echo -e "${YELLOW}>>> Performing validation and preparation...${NC}"

# --- 2. Validate VMID ---
# Check if the VMID is already in use.
echo "--> Checking if VMID ${VMID} is available..."
if qm list | grep -q "^\s*${VMID}\s"; then
    echo -e "${RED}Error: VMID '${VMID}' is already in use.${NC}"
    exit 1
fi


# --- 4. Validate Network Bridges ---
# Check if the provided bridge interfaces exist on the host.
echo "--> Checking if bridges '${BRIDGES_LIST}' exist..."
declare -a bridges_array
OLD_IFS=$IFS; IFS=','; read -ra bridges_array <<< "$BRIDGES_LIST"; IFS=$OLD_IFS
for bridge in "${bridges_array[@]}"; do
    if [ ! -d "/sys/class/net/$bridge" ]; then
        echo -e "${RED}Error: Network bridge '${bridge}' does not exist on this Proxmox host.${NC}"
        exit 1
    fi
done

# --- 5. Select Image & Validate Files ---
# Check for required files based on the specified VM type.
echo "--> Checking for required files for type '${TYPE}'..."
QCOW2_TO_USE=""
if [ "$TYPE" = "switch" ]; then
    QCOW2_TO_USE="$SWITCH_QCOW2_PATH"
elif [ "$TYPE" = "router" ]; then
    QCOW2_TO_USE="$ROUTER_QCOW2_PATH"
else
    echo -e "${RED}Error: Invalid type '$TYPE'. Please use 'switch' or 'router'.${NC}"
    exit 1
fi
if [ -z "$QCOW2_TO_USE" ] || [ ! -f "$QCOW2_TO_USE" ]; then
    echo -e "${RED}Error: qcow2 image for type '${TYPE}' not found.${NC}"
    echo -e "${RED}Path checked: $QCOW2_TO_USE${NC}"
    exit 1
fi
if [ ! -f "$MAKESCRIPT_PATH" ]; then
    echo -e "${RED}Error: make-config.sh script not found at path: $MAKESCRIPT_PATH${NC}"
    exit 1
fi
echo -e "${GREEN}>>> All required files are available.${NC}"



# --- 6. Handle Root Password ---
# Conditionally validate password configuration if root login is allowed.
if [ "$ROOT_LOGIN_ALLOW" = "allow" ]; then
    echo "${GREEN}--> Root login is enabled, validating password configuration...${NC}"
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}Error: 'openssl' command not found. It is required to hash the password.${NC}"; exit 1;
    fi
    if [ -n "$ROOT_PASSWORD_HASH" ]; then
        echo -e "${YELLOW}>>> Using pre-configured root password hash.${NC}"
    elif [ -n "$ROOT_PASSWORD_PLAINTEXT" ]; then
        echo -e "${YELLOW}>>> Generating root password hash from plaintext...${NC}"
        ROOT_PASSWORD_HASH=$(openssl passwd -6 "$ROOT_PASSWORD_PLAINTEXT")
    else
        echo -e "${RED}Error: Root login is allowed, but no password configured.${NC}"; exit 1;
    fi
else
    echo "${GREEN}--> Root login is set to '${ROOT_LOGIN_ALLOW}', skipping password validation.${NC}"
fi


# ==============================================================================
#                      VM CREATION & CONFIGURATION
# ==============================================================================
echo -e "${GREEN}>>> Starting VM Creation & Configuration for ${VMNAME} (ID: ${VMID})...${NC}"

# --- 7. Generate Certificates & Prepare Config Drive ---
# This block handles all file generation before the VM is created.

if [ "$GRPC_ENABLE" = "true" ]; then
    echo "--> gRPC is enabled. Preparing certificates and extended configuration..."

    # --- 7a. Generate Certificate Authority (if it doesn't exist) ---
    CA_DIR=$(dirname "$CERT_CA_CERT_PATH")
    mkdir -p "$CA_DIR"
    if [ ! -f "$CERT_CA_CERT_PATH" ] || [ ! -f "$CERT_CA_KEY_PATH" ]; then
        echo -e "${YELLOW}--> CA certificate not found. Generating a new one...${NC}"
        openssl genrsa -out "$CERT_CA_KEY_PATH" 2048
        openssl req -x509 -new -nodes -key "$CERT_CA_KEY_PATH" -sha256 -days 3650 -out "$CERT_CA_CERT_PATH" -subj "/CN=MyLabCA"
    else
        echo "--> Using existing Certificate Authority."
    fi

    # Conditionally check for mtools if gRPC is enabled
    if [ "$GRPC_ENABLE" = "true" ]; then
        if ! command -v mcopy &> /dev/null; then
            echo -e "${RED}Error: 'mcopy' command not found. It is required for gRPC certificate injection.${NC}"
            echo -e "${RED}Please install the 'mtools' package with: apt-get install mtools${NC}"
            exit 1
        fi
    fi

    # --- 7b. Generate Device-Specific Certificate ---
    echo "--> Generating device certificate for ${VMNAME}..."
    CERT_ID="${CERT_ID_PREFIX}-${VMNAME}-cert"
    
    # Generate device key
    openssl genrsa -out "${VMNAME}.key" 2048
    
    # Generate Certificate Signing Request (CSR)
    openssl req -new -key "${VMNAME}.key" -out "${VMNAME}.csr" -subj "/CN=${VMNAME}"
    
    # Create OpenSSL v3 extensions file with Subject Alternative Names (SAN)
    cat << EOF_V3 > v3.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${VMNAME}
IP.1 = ${IP_ADDR}
EOF_V3

    # Sign the device certificate with our CA
    openssl x509 -req -in "${VMNAME}.csr" -CA "$CERT_CA_CERT_PATH" -CAkey "$CERT_CA_KEY_PATH" -CAcreateserial -out "${VMNAME}.crt" -days 365 -sha256 -extfile v3.ext

    # --- 7c. Generate gNOI User Password Hash ---
    GNOI_USER_PASSWORD_HASH=$(openssl passwd -6 "$GNOI_USER_PASSWORD_PLAINTEXT")

fi # End of gRPC enable check


CERT_ID="${VMNAME}-cert"

# --- 7d. Generate juniper.conf (conditionally adding gRPC config) ---
echo "--> Generating juniper.conf file..."
cat <<EOF > juniper.conf
system {
    host-name ${VMNAME};
    root-authentication {
        encrypted-password "${ROOT_PASSWORD_HASH}";
    }
$( [ "$GRPC_ENABLE" = "true" ] && cat <<EOF_GNOI_USER
    login {
        user ${GNOI_USER} {
            uid 2001;
            class super-user;
            authentication {
                encrypted-password "${GNOI_USER_PASSWORD_HASH}";
            }
        }
    }
EOF_GNOI_USER
)
    services {
        ssh {
            root-login ${ROOT_LOGIN_ALLOW};
        }
$( [ "$GRPC_ENABLE" = "true" ] && cat <<EOF_GRPC_SVC
        extension-service {
            request-response {
                grpc {
                    ssl {
                        port ${GRPC_PORT};
                        local-certificate ${CERT_ID};
                        hot-reloading;
                        use-pki;
                    }
                }
            }
        }
EOF_GRPC_SVC
)
    }
    management-instance;
    name-server {
        ${DNS_SERVER};
    }
}
interfaces {
    fxp0 {
        unit 0 {
            family inet {
                address ${IP_ADDR}/${IP_SUBNET};
            }
        }
    }
$( [ -n "$GE000_IP" ] && cat <<EOF_GE000
    ge-0/0/0 {
        enable;
        unit 0 {
            family inet {
                address ${GE000_IP}/${IP_SUBNET};
            }
        }
    }
EOF_GE000
)
$( [ -n "$GE001_IP" ] && cat <<EOF_GE001
    ge-0/0/1 {
        enable;
        unit 0 {
            family inet {
                address ${GE001_IP}/${IP_SUBNET};
            }
        }
    }
EOF_GE001
)
$( [ -n "$GE002_IP" ] && cat <<EOF_GE002
    ge-0/0/2 {
        enable;
        unit 0 {
            family inet {
                address ${GE002_IP}/${IP_SUBNET};
            }
        }
    }
EOF_GE002
)
$( [ -n "$GE003_IP" ] && cat <<EOF_GE003
    ge-0/0/3 {
        enable;
        unit 0 {
            family inet {
                address ${GE003_IP}/${IP_SUBNET};
            }
        }
    }
EOF_GE003
)
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
event-options {
    destination local-logs {
        files {
            self_signed_gen_log;
        }
    }
    policy trigger-after-boot {
        events system;
        attributes-match {
            system.message matches "Starting of initial processes complete";
        }
        then {
            execute-commands {
                commands {
                    "request security pki generate-key-pair certificate-id ${CERT_ID} size 2048";
                    "request security pki local-certificate generate-self-signed certificate-id ${CERT_ID} subject \"C=PL, ST=Wielkopolskie, L=Poznan, O=Lab, OU=Net, CN=vjuniper.router1.local\" domain-name vjuniper.local digest sha-256 ip-address ${GE003_IP}";
                }
                output-filename self_signed_gen_log;
            }
        }
    }
}



EOF

# Append SNMP configuration block if it is enabled in config.sh
if [ "$SNMP_ENABLE" = "true" ]; then
    echo "--> SNMP is enabled, appending configuration..."

    # Generate the 'clients' stanza from the array
    CLIENTS_CONFIG=""
    for client in "${SNMP_ALLOWED_CLIENTS[@]}"; do
        CLIENTS_CONFIG+="        clients {\n"
        CLIENTS_CONFIG+="            ${client};\n"
        CLIENTS_CONFIG+="        }\n"
    done

    # Append the SNMP configuration block to the existing juniper.conf file
    cat <<EOF_SNMP >> juniper.conf
snmp {
    interface fxp0.0;
    v3 {
        usm {
            local-engine {
                user ${SNMP_V3_USER} {
                    authentication-md5 {
                        authentication-password "${SNMP_V3_AUTH_PASS_PLAINTEXT}";
                    }
                    privacy-des {
                        privacy-password "${SNMP_V3_PRIV_PASS_PLAINTEXT}";
                    }
                }
            }
        }
        vacm {
            security-to-group {
                security-model usm {
                    security-name ${SNMP_V3_USER} {
                        group ${SNMP_V3_GROUP};
                    }
                }
            }
            access {
                group ${SNMP_V3_GROUP} {
                    default-context-prefix {
                        security-model any {
                            security-level privacy {
                                read-view ${SNMP_V3_VIEW};
                            }
                        }
                    }
                }
            }
        }
    }
    view ${SNMP_V3_VIEW} {
        oid .1 include;
    }
    community ${SNMP_V2_COMMUNITY} {
        authorization read-only;
$(echo -e "${CLIENTS_CONFIG}")
    }
    routing-instance-access;
}
EOF_SNMP
fi

# --- 7e. Create Config Image and Inject Certs ---
echo "--> Creating base config drive..."
chmod +x ${MAKESCRIPT_PATH}
./${MAKESCRIPT_PATH} juniper.conf myconfig.img

if [ "$GRPC_ENABLE" = "true" ]; then
    echo "--> Injecting certificate and key into config drive..."
    mcopy -o -i myconfig.img "${VMNAME}.crt" ::/
    mcopy -o -i myconfig.img "${VMNAME}.key" ::/
fi


# --- 8. Generate Dynamic Network Arguments ---
NET_ARGS=""
for i in "${!bridges_array[@]}"; do
    bridge=$(echo "${bridges_array[$i]}" | xargs)
    if_num=$((i + 1))
    NET_ARGS+=" --net${if_num} virtio,bridge=${bridge},firewall=0"
done

# --- 9. Create the Virtual Machine and Import OS Disk ---
echo "--> Creating new VM with QM..."
qm create ${VMID} --name ${VMNAME} --memory ${MEMORY} --cores ${CORES} \
    --args "-machine accel=kvm:tcg -smbios type=1,product=VM-VEX -cpu 'host,kvm=on'" \
    --boot order=virtio0 --serial0 socket \
    --net0 virtio,bridge=${MANAGEMENT_BRIDGE} \
    ${NET_ARGS}

echo "--> Importing the vJunos OS disk image..."
qm disk import ${VMID} ${QCOW2_TO_USE} ${VMSTORAGE} --format qcow2
VMIMAGE=$(qm config ${VMID} | grep "unused0:" | awk '{print $2}')
qm set ${VMID} --virtio0 ${VMIMAGE},iothread=1,size=32G

# --- 10. Create and Import Junos Config Drive ---
# echo "--> Creating and importing the Junos config drive..."
# chmod +x ${MAKESCRIPT_PATH}
# ./${MAKESCRIPT_PATH} juniper.conf myconfig.img

echo "--> Importing the config drive..."
qm disk import ${VMID} myconfig.img ${VMSTORAGE} --format raw
VMIMAGE_CONF=$(qm config ${VMID} | grep "unused0:" | awk '{print $2}')
qm set ${VMID} --ide0 ${VMIMAGE_CONF},size=16M

# --- 11. Start VM and Apply Post-Boot Tweaks ---ku
echo "--> Starting VM ${VMNAME}..."
qm start ${VMID}

echo -e "${YELLOW}--> Waiting 15 seconds for network interfaces to initialize...${NC}"
sleep 15

echo -e "${YELLOW}--> Applying post-boot network tweaks (LLDP/LACP)...${NC}"
chmod +x vm-bridge-update.sh
./vm-bridge-update.sh ${VMID}

# --- 12. Cleanup ---
echo "--> Cleaning up temporary files..."
rm juniper.conf myconfig.img v3.ext

echo -e "${GREEN}>>> Finished! Machine ${VMNAME} (ID: ${VMID}) has been started.${NC}"