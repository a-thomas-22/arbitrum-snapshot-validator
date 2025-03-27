# Arbitrum Node Snapshot Validation Playbook

## Overview

This Ansible playbook automates the provisioning of an EC2 instance and deployment of an Arbitrum Nitro node with a RAID0 NVMe configuration and Docker containerization. It is specifically designed to validate an Arbitrum snapshot and is tailored for **i3en** instance types on AWS. This is a utility playbook for testing purposes only and is not intended for production use.

## Requirements

- **Tools:**
  - Ansible
  - AWS CLI configured with appropriate permissions
  - boto3 Python package (`pip install boto3`)

## Setup

### Inventory Configuration

This project uses a dynamic AWS inventory to automatically discover and connect to EC2 instances. The configuration is in `inventory_aws.aws_ec2.yml`:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - us-west-2
aws_profile: testnet-AdministratorAccess
filters:
  tag:Purpose: snapshot-verification
  instance-state-name: running
hostnames:
  - dns-name
  - private-ip-address
compose:
  ansible_host: public_ip_address
  ansible_user: ubuntu
  ansible_python_interpreter: /usr/bin/python3.12
  ansible_ssh_private_key_file: "{{ lookup('env', 'SSH_PRIVATE_KEY') | default(lookup('env', 'PRIVATE_KEY_PATH')) }}"
```

This dynamic inventory:
- Automatically discovers EC2 instances with the tag `Purpose: snapshot-verification`
- Sets the necessary connection parameters for SSH access

### Variables Configuration

Define your variables in the `group_vars/all.yml` file, referencing environment variables for all sensitive data:

```yaml
base_data_path: /data
arbitrum_path: "{{ base_data_path }}/arbitrum"
nitro_path: "{{ arbitrum_path }}/nitro"
chain_name: "sepolia-rollup"
snapshot_type: "pruned"

chain_id_map:
  arb1: 42161
  sepolia-rollup: 421614
  nova: 42170

docker_image: "offchainlabs/nitro-node:v3.5.2-33d30c0"
parent_chain_url: "{{ lookup('env', 'PARENT_CHAIN_URL') }}"
parent_chain_beacon_url: "{{ lookup('env', 'PARENT_CHAIN_BEACON_URL') }}"
```

### Using Environment Variables

To manage sensitive data, create a `.env` file with the required environment variables:

#### `.env`
```bash
# EC2 provisioning variables
AWS_PROFILE=default                           # Optional: AWS profile name to use (from ~/.aws/credentials)
AWS_KEY_NAME=arbitrum-node-key                # Required: Name of your AWS key pair
AWS_SUBNET_ID=subnet-xxxxxxxx                 # Optional: Specific subnet ID to launch the instance in
PUBLIC_KEY_PATH=~/.ssh/id_rsa.pub             # Optional: Path to an existing public key to import to AWS

# Node configuration variables
SSH_PRIVATE_KEY=/path/to/private/key.pem      # Path to your SSH private key
PARENT_CHAIN_URL=https://example-ethereum-rpc.com
PARENT_CHAIN_BEACON_URL=https://example-beacon-rpc.com
```

> **Note:** If you prefer to use an AWS profile instead of setting AWS credentials directly, you can specify the profile name using the `AWS_PROFILE` environment variable.

> **Note:** For SSH key handling, you have two options:
> 1. **Use an existing AWS key pair**: Set `AWS_KEY_NAME` to the name of an existing key pair in AWS.
> 2. **Import an existing key**: Set `PUBLIC_KEY_PATH` to the path of your public key file. The playbook will import this key to AWS with the name specified in `AWS_KEY_NAME`.

#### Load the `.env` Variables
Before running the playbook, load the variables into your environment:

```bash
export $(cat .env | xargs)
```

## Deployment

Run the following command to execute the playbook:

```bash
ansible-playbook -i inventory_aws.aws_ec2.yml site.yml
```

This will:
1. Provision a new EC2 instance (i3en.2xlarge) in the specified AWS region
2. Create a security group with the necessary ports open (SSH, Arbitrum RPC)
3. Configure the instance with RAID0 for NVMe drives
4. Download and validate the Arbitrum snapshot
5. Start the Arbitrum node in a Docker container

## Customizing EC2 Provisioning

You can customize the EC2 instance provisioning by modifying the variables in the `provision_ec2.yml` file:

```yaml
vars:
  aws_region: us-west-2                # AWS region to deploy in
  aws_profile: "{{ lookup('env', 'AWS_PROFILE') | default(omit) }}"  # AWS profile to use
  instance_type: i3en.2xlarge          # EC2 instance type (must be i3en family)
  ami_id: ami-0c65adc9a5c1b5d7c        # Ubuntu 20.04 AMI ID (update for your region)
  key_name: "{{ lookup('env', 'AWS_KEY_NAME') | default('arbitrum-node-key') }}"  # Key pair name
  public_key_path: "{{ lookup('env', 'PUBLIC_KEY_PATH') | default(omit) }}"  # Path to existing public key to import
  security_group_name: arbitrum-snapshot-verification-sg # Name for the security group
  instance_name: arbitrum-snapshot-validator         # Name tag for the EC2 instance
```

### EC2 Instance Tagging

The EC2 instances are tagged with metadata that helps with organization and filtering:

```yaml
tags:
  Name: "{{ instance_name }}"
  Purpose: "snapshot-verification"
  Environment: "testnet"
  Chain: "{{ chain_name | default('sepolia-rollup') }}"
  NetworkType: "rollup"
  ProjectVersion: "1.0"
```

These tags provide several benefits:
- **Filtering**: Easily find instances in the AWS console by purpose, chain, or environment
- **Grouping**: The dynamic inventory automatically creates groups based on these tags
- **Automation**: Target specific instances in your playbooks using tag-based groups
- **Cost tracking**: Better organize resources for cost allocation

For example, to run a playbook only on instances with a specific tag:

```bash
ansible-playbook -i inventory_aws.aws_ec2.yml site.yml --limit "tag_Chain_sepolia_rollup"
```

## Accessing Logs

Nitro logs are stored in the `/data/arbitrum/logs` directory on the server. The logs are automatically rotated when they reach 100MB in size, and up to 20 backup log files are kept.

To view the logs:
```bash
ssh -i /path/to/key.pem ubuntu@<server-ip>
tail -f /data/arbitrum/logs/nitro.log
```

You can also view archived logs in the same directory.

## Cleanup

To avoid ongoing AWS charges, you can use the included cleanup playbook to terminate instances and remove associated resources:

```bash
# Basic cleanup - terminates instances with the snapshot-verification tag
ansible-playbook -i inventory_aws.aws_ec2.yml cleanup.yml

# Dry run mode - shows what would be deleted without actually deleting
ansible-playbook -i inventory_aws.aws_ec2.yml cleanup.yml -e "DRY_RUN=true"

# Cleanup with key pair deletion
ansible-playbook -i inventory_aws.aws_ec2.yml cleanup.yml -e "DELETE_KEYPAIR=true"

# Cleanup instances with a specific chain tag
ansible-playbook -i inventory_aws.aws_ec2.yml cleanup.yml -e "tag_Chain_sepolia_rollup=true"

# Combine options
ansible-playbook -i inventory_aws.aws_ec2.yml cleanup.yml -e "DELETE_KEYPAIR=true tag_Chain_sepolia_rollup=true"
```

The cleanup playbook will:
1. Find and terminate all EC2 instances with the `Purpose: snapshot-verification` tag
2. Delete the security group created for these instances
3. Optionally delete the AWS key pair if `DELETE_KEYPAIR=true`

You can also manually terminate instances through the AWS Management Console or using the AWS CLI:

```bash
aws ec2 terminate-instances --instance-ids <instance-id>
```
