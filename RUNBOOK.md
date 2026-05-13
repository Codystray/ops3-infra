# Ops 3 Runbook: Automated Minecraft Server

## Overview

This runbook documents how to provision, configure, deploy, and tear down
the Minecraft server infrastructure. All resources are managed through
Terraform (infrastructure), Ansible (host configuration), and GitHub
Actions (image publishing). No component should be modified by hand.

## Prerequisites

Local machine must have:
- Terraform >= 1.x (or OpenTofu)
- Ansible >= 2.14
- AWS CLI v2
- An SSH keypair available at ~/.ssh/cs312-key.pem and id_ed25519.pub
- Active AWS Academy session with credentials in ~/.aws/credentials
  (access key, secret key, and session token all required)

## Credential refresh procedure

AWS Academy credentials expire when the Learner Lab session ends.
To refresh:

1. Open the Learner Lab in AWS Academy.
2. Click "AWS Details" then "Show" next to AWS CLI.
3. Replace the contents of ~/.aws/credentials with the new block.
4. Update the same three values in GitHub repository Settings >
   Secrets and variables > Actions:
   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY
   - AWS_SESSION_TOKEN
5. Verify locally with: aws sts get-caller-identity

After pasting fresh AWS Academy credentials, also confirm the line
`region=us-east-1` is present in the `[default]` block of
~/.aws/credentials. Academy's copyable credential block does not always
include it. Without it, aws CLI commands fail with "You must specify a
region."

## Repository layout

ops3/
├── RUNBOOK.md
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── terraform.tfvars
├── ansible/
│   ├── inventory.ini
│   ├── playbook.yml
│   └── ansible.cfg
├── .github/
│   └── workflows/
│       └── publish-image.yml
└── .gitignore

## Resources provisioned (step 2)

| Resource | Purpose |
|---|---|
| aws_security_group.minecraft | SSH (22) from configured CIDR; Minecraft (25565) from anywhere; all outbound. |
| aws_ecr_repository.minecraft | Container registry for Minecraft images. Tags are mutable for development; production would prefer immutable tags. |
| Default VPC and its first subnet (referenced via data sources) | Network placement; default VPC provides a public subnet with an internet gateway. |

## Terraform variables (step 2)

| Variable | Purpose | Default |
|---|---|---|
| key_name | Existing AWS EC2 key pair name used for SSH (consumed in step 4) | (required) |
| ssh_allowed_cidr | CIDR allowed to SSH to the instance | 0.0.0.0/0 (tighten to your-ip/32) |

## Terraform state handling

State is stored locally in `terraform/terraform.tfstate`. The file is gitignored
because it contains AWS resource IDs and could contain sensitive values. Tradeoff:
local state is simple and has no AWS dependencies, but it cannot be shared across
teammates and is not protected against laptop loss. A team would migrate to an S3
backend with state locking; for this single-operator assignment, local state is
sufficient.
