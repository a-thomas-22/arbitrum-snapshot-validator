# Arbitrum Node Snapshot Validation Playbook

## Overview

This Ansible playbook automates the deployment of an Arbitrum Nitro node with a RAID0 NVMe configuration and Docker containerization. It is specifically designed to validate an Arbitrum snapshot and is tailored for **i3en** instance types on AWS. This is a utility playbook for testing purposes only and is not intended for production use. Expect that it may break or require modifications for broader use cases.

## Requirements

- **Instance Type:** AWS **i3en** with Ubuntu 20.04
- **Disks:** Minimum of 2 NVMe drives
- **Tools:**
  - Ansible
  - SSH access to the EC2 instance

## Setup

### Inventory Configuration

Create an `inventory.yml` file to define your server details:

```yaml
all:
  hosts:
    arbitrum_node:
      ansible_host: "{{ lookup('env', 'EC2_PUBLIC_IP') }}"  
      ansible_user: ubuntu                                 
      ansible_ssh_private_key_file: "{{ lookup('env', 'SSH_PRIVATE_KEY') }}"  
```

### Variables Configuration

Define your variables in the `group_vars/all.yml` file, referencing environment variables for all sensitive data:

```yaml
arbitrum_data_path: /data
chain_name: "arb1"
snapshot_type: "pruned"


chain_id_map:
  arb1: 42161

docker_image: "{{ lookup('env', 'DOCKER_IMAGE') }}"
parent_chain_url: "{{ lookup('env', 'PARENT_CHAIN_URL') }}"
parent_chain_beacon_url: "{{ lookup('env', 'PARENT_CHAIN_BEACON_URL') }}"
```

### Using Environment Variables

To manage sensitive data, create a `.env` file with the required environment variables:

#### `.env`
```bash
EC2_PUBLIC_IP=35.92.198.80
SSH_PRIVATE_KEY=/path/to/private/key.pem
PARENT_CHAIN_URL=https://example-ethereum-rpc.com
PARENT_CHAIN_BEACON_URL=https://example-beacon-rpc.com
```

#### Load the `.env` Variables
Before running the playbook, load the variables into your environment:

```bash
export $(cat .env | xargs)
```

## Deployment

Run the following command to execute the playbook:

```bash
ansible-playbook -i inventory.yml site.yml
```
