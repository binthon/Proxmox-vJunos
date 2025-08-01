#!/bin/bash
# ----------------------------------------------------
# Default Configuration for vJunos VM Creation Script
# ----------------------------------------------------
# This file holds all the default variables.
# You can override these settings by using command-line flags when running the main script.

# --- Proxmox & Network Settings ---

# The Proxmox storage ID where the VM disks will be placed.
VMSTORAGE="local-lvm"

# The default gateway for the VM's management interface.
GATEWAY="10.250.249.254"

# The Proxmox bridge for the management interface (fxp0 / net0).
MANAGEMENT_BRIDGE="vmbr0"

# The DNS server to be configured inside the VM.
DNS_SERVER="8.8.8.8"


# --- Default VM Parameters ---

# Default RAM for the VM in Megabytes.
MEMORY=5120

# Default number of CPU cores for the VM.
CORES=4

# The subnet mask (prefix length) for the management IP address.
IP_SUBNET=24



# --- vJunos Specific Settings ---

# Determines if root login via SSH is allowed. Can be "allow" or "deny".
ROOT_LOGIN_ALLOW="allow"


# --- Root Password Configuration ---
# The script prioritizes the HASH. If the HASH is empty, it will be generated
# from the PLAINTEXT password below.

# WARNING: Storing plaintext passwords is a major security risk.
# It is strongly recommended to leave PLAINTEXT empty and fill the HASH instead.
ROOT_PASSWORD_PLAINTEXT="test1234"

# The encrypted root password.
# Leave this empty if you want it to be generated from the plaintext password above.
# To generate manually: openssl passwd -6 'your_password'
ROOT_PASSWORD_HASH=""



# --- File Paths ---

# Path to the vJunos-switch qcow2 image.
SWITCH_QCOW2_PATH="/root/download/vJunos-switch-25.2R1.9.qcow2"

# Path to the vJunos-router qcow2 image.
ROUTER_QCOW2_PATH="/root/download/vJunos-router-25.2R1.9.qcow2"

# The path to the Junos config generation script.
MAKESCRIPT_PATH="./make-config-25.2R1.9.sh"


# --- Miscellaneous Settings ---

# The MTU to be set on the host bridges during the post-boot tweaks.
POST_BOOT_MTU=9200s



# --- SNMP Configuration ---
# Set to "true" to enable and add the SNMP block to the configuration.
SNMP_ENABLE="true"

# SNMP v2c Community String configuration
SNMP_V2_COMMUNITY="lab"
# List of allowed client subnets for SNMPv2c.
SNMP_ALLOWED_CLIENTS=("10.250.249.0/24")

# SNMP v3 User Configuration
SNMP_V3_USER="lab"
SNMP_V3_GROUP="group"
SNMP_V3_VIEW="SNMPVIEW"
# Plaintext passwords for the script to use. Junos will hash them upon commit.
SNMP_V3_AUTH_PASS_PLAINTEXT="test12345"
SNMP_V3_PRIV_PASS_PLAINTEXT="test12345"


# --- gRPC & Certificate Configuration ---
# Set to "true" to enable gRPC and automatic certificate generation.
GRPC_ENABLE="true"

# The port number for the gRPC service.
GRPC_PORT=57400

# The username for the gRPC/gNOI user.
GNOI_USER="gnoi-user"

# Plaintext password for the gNOI user. The script will hash it.
GNOI_USER_PASSWORD_PLAINTEXT="test123456"

# The name (certificate-id) for the certificate inside Junos.
CERT_ID_PREFIX="vm" # e.g., vm-switch-cert

# Paths for the Certificate Authority files.
# If they don't exist, the script will create them once.
# It's recommended to use an absolute path for consistency.
CERT_CA_KEY_PATH="/root/certs/ca.key"
CERT_CA_CERT_PATH="/root/certs/ca.crt"