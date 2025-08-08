# Proxmox-vJunos

### The project automates the process of creating virtual machines from Juniper vJunos qcow disk in the Promxox VE environment. The script generate the juniper.conf with super-user, password, snmp and gNMI. Additionally attach disks, network interfaces and set ip addresses.

## Repository Contents

| File | Description |
|------|-------------|
| `config.sh` | Default settings (storage, RAM/CPU, addressing, passwords, image paths, SNMP/gRPC. |
| `create-vjunos.sh` | Main provisioning script – loads defaults, validates arguments, generates `juniper.conf`, builds and attaches the config drive, creates and starts the VM. |
| `make-config.sh` | Juniper utility script to create a **config drive** from `juniper.conf` (VFAT format, `vmm-config.tgz`). |
| `vm-bridge-update.sh` | Post-boot script to set MTU and adjust Linux bridge forwarding masks for VM interfaces. |
