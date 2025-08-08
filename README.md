# Proxmox-vJunos

### The project automates the process of creating virtual machines from Juniper vJunos qcow disk in the Promxox VE environment. The script generate the juniper.conf with super-user, password, snmp and gNMI. Additionally attach disks, network interfaces and set ip addresses.

## Repository Contents

| File | Description |
|------|-------------|
| `config.sh` | Default settings (storage, RAM/CPU, addressing, passwords, image paths, SNMP/gRPC. |
| `create-vjunos.sh` | Main provisioning script – loads defaults, validates arguments, generates `juniper.conf`, builds and attaches the config drive, creates and starts the VM. |
| `make-config.sh` | Juniper utility script to create a **config drive** from `juniper.conf` (VFAT format, `vmm-config.tgz`). |
| `vm-bridge-update.sh` | Post-boot script to set MTU and adjust Linux bridge forwarding masks for VM interfaces. |

## Configuration (config.sh)
The config.sh file defines:
- Proxmox/Network: VMSTORAGE, MANAGEMENT_BRIDGE, GATEWAY, DNS_SERVER.
- VM defaults: MEMORY, CORES, IP_SUBNET.
- vJunos images: SWITCH_QCOW2_PATH, ROUTER_QCOW2_PATH.
- Root login: ROOT_LOGIN_ALLOW, ROOT_PASSWORD_HASH or ROOT_PASSWORD_PLAINTEXT.
- SNMP: enable/disable, v2c and v3 settings.
- gRPC/gNMI: enable/disable, port, username and password.

## How create-vm.sh works
1. Loads config.sh and parses CLI arguments.
2. Validates IP addresses, VMID availability, bridge existence, and required files.
3. Prepares passwords (uses hash or generates hash from plaintext).
4. Builds juniper.conf including:
    - hostname, root authentication, SSH and optional gRPC services,
    - management IP (fxp0) and optional data interface IPs,
    - default route in mgmt_junos,
    - LLDP and optional SNMP config.
5. Creates myconfig.img (config drive) using make-config.sh.
6. Creates the VM in Proxmox, imports the .qcow2 OS disk, attaches the config drive.
7. Starts the VM and runs vm-bridge-update.sh.
8. Cleans up temporary files.
