# Ops 3 Runbook: Automated Minecraft Server

## Overview

This runbook documents how to provision, configure, deploy, and tear down
the Minecraft server infrastructure. All resources are managed through
Terraform (infrastructure), Ansible (host configuration), and GitHub
Actions (image publishing). No component should be modified by hand.

## Conventions used throughout the project

- Server MOTD must include name or student ID (per assignment).
- Resource names are prefixed `ops3-`.
- ECR tags follow `vMAJOR.MINOR.PATCH` and match the git tag that produced
  them (no overwriting; one image per tag).

## Prerequisites

Local machine must have:

- Terraform (version installed: `terraform version`) or OpenTofu
- Ansible (version installed: `ansible --version`)
- AWS CLI v2
- The cs312-key SSH private key at `~/.ssh/cs312-key.pem` with `chmod 600`
- The matching AWS EC2 key pair (named `cs312-key`) already exists in AWS
- Active AWS Academy session with credentials in `~/.aws/credentials`
  (access key, secret key, and session token all required)

## Credential refresh procedure

AWS Academy credentials expire when the Learner Lab session ends.
To refresh:

1. Open the Learner Lab in AWS Academy.
2. Click "AWS Details" then "Show" next to AWS CLI.
3. Replace the contents of `~/.aws/credentials` with the new block.
4. Confirm the line `region=us-east-1` is present in the `[default]` block
   of `~/.aws/credentials`. Academy's copyable credential block does not
   always include it. Without it, aws CLI commands fail with "You must
   specify a region."
5. Update the same three values in GitHub repository
   Settings > Secrets and variables > Actions:
   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY
   - AWS_SESSION_TOKEN
6. Verify locally with: `aws sts get-caller-identity`

## Repository layout

```
ops3/
├── RUNBOOK.md
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── ansible/
│   ├── inventory.ini
│   ├── playbook.yml
│   └── ansible.cfg
├── .github/
│   └── workflows/
│       └── publish-image.yml
└── .gitignore
```

The `.gitignore` excludes:

- `terraform/.terraform/` (provider plugins)
- `terraform/*.tfstate` (state files, contain resource IDs)
- `terraform/*.tfstate.backup`

## Resources provisioned (step 2)

| Resource | Purpose |
|---|---|
| `aws_security_group.minecraft` | SSH (22) from configured CIDR; Minecraft (25565) from anywhere; all outbound. |
| `aws_ecr_repository.minecraft` | Container registry for Minecraft images. Tags are mutable for development; production would prefer immutable tags. |
| Default VPC and its first subnet (referenced via data sources) | Network placement; default VPC provides a public subnet with an internet gateway. |

## Terraform variables (step 2)

| Variable | Purpose | Default |
|---|---|---|
| `key_name` | Existing AWS EC2 key pair name used for SSH (consumed in step 4) | (required) |
| `ssh_allowed_cidr` | CIDR allowed to SSH to the instance | `0.0.0.0/0` (tighten to your-ip/32) |

## Terraform state handling

State is stored locally in `terraform/terraform.tfstate`. The file is
gitignored because it contains AWS resource IDs and could contain sensitive
values. Tradeoff: local state is simple and has no AWS dependencies, but it
cannot be shared across teammates and is not protected against laptop loss.
A team would migrate to an S3 backend with state locking; for this
single-operator assignment, local state is sufficient.

## Image publishing pipeline (step 3)

Workflow file: `.github/workflows/publish-image.yml`

Trigger: pushing a git tag matching `v*` (e.g., `v1.0.0`).

Steps performed by the workflow:

1. Configure AWS credentials from the three GitHub secrets (Academy
   session credentials, not long-lived IAM keys).
2. Log Docker into ECR.
3. Pull the upstream image `itzg/minecraft-server:java21` (the de facto
   standard Minecraft Docker image; we re-tag rather than rebuild from a
   Dockerfile).
4. Smoke test: start the image with `EULA=TRUE` and the pinned Minecraft
   `VERSION`, then poll `docker logs` for up to 180 seconds looking for
   the `Done (` string that the server prints when it has finished
   initializing. Fails the pipeline if the string is not seen in time.
5. Tag the image as `<ECR-URL>:<git-tag>` and push to ECR.

### Releasing a new image version

1. Confirm AWS Academy credentials are fresh; if the lab session has
   rolled over, refresh the three GitHub secrets.
2. From the repo root: `git tag vX.Y.Z && git push origin vX.Y.Z`
3. Watch the run in the Actions tab.
4. Verify the new tag with:
   `aws ecr describe-images --repository-name ops3-minecraft-server`

### Refresh procedure for GitHub Actions secrets

When the AWS Academy lab session ends, the three `AWS_*` secrets in the
GitHub repo are no longer valid. To refresh:

1. AWS Academy Learner Lab > AWS Details > Show next to AWS CLI.
2. GitHub repo > Settings > Secrets and variables > Actions.
3. Edit each of `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
   `AWS_SESSION_TOKEN`.
4. Paste the new value from the Academy panel.

## EC2 instance and IAM (step 4)

| Resource | Purpose |
|---|---|
| `data.aws_ami.ubuntu` | Looks up the latest Ubuntu 24.04 LTS AMI from Canonical (owner 099720109477). Keeps the config self-updating. |
| `aws_instance.minecraft` | The host that runs the Minecraft container. |

### Instance configuration decisions

- **AMI**: Ubuntu 24.04 LTS, looked up dynamically rather than hardcoded so
  the config stays current as Canonical publishes new images.
- **Instance type**: `t3.small` (2 GB RAM). Minecraft's JVM needs ~1 GB
  heap; t3.small leaves ~1 GB for the OS and Docker. t3.micro (1 GB total)
  is too tight. t3.medium would be more comfortable but doubles the cost.
- **Storage**: 20 GB gp3 root volume. The Ubuntu AMI defaults to 8 GB,
  which is too tight once a Minecraft world begins to grow. gp3 is the
  current-generation SSD type, cheaper than gp2.
- **IAM**: `LabInstanceProfile` attached to the instance. This is the
  AWS Academy pre-existing instance profile containing `LabRole`. Grants
  ECR pull and S3 read/write without on-disk credentials.
- **User-data**: cloud-init installs only Python 3 on first boot.
  Everything else is configured by Ansible. This division enforces the
  "all server configuration lives in Ansible" requirement.

### Updated Terraform variables (step 4)

| Variable | Purpose | Default |
|---|---|---|
| `key_name` | Existing AWS EC2 key pair name used for SSH | (required) |
| `ssh_allowed_cidr` | CIDR allowed to SSH to the instance | `0.0.0.0/0` |
| `instance_type` | EC2 instance type | `t3.small` |

### Connecting to the instance

After `terraform apply`, the `ssh_command` output prints a ready-to-paste
command. Wait for cloud-init to finish before using Ansible against the
host:

    ssh -i ~/.ssh/cs312-key.pem ubuntu@<public-ip> 'cloud-init status --wait'

This blocks until first-boot setup is complete (60-120 seconds on a fresh
instance).

## Server configuration (step 5)

Playbook: `ansible/playbook.yml`
Inventory: `ansible/inventory.ini` (populated manually for now; will be
generated from Terraform output in step 7)

### What the playbook does

1. **Installs Docker** from the official Docker apt repository.
2. **Installs AWS CLI v2** from Amazon's installer.
3. **Installs the Python Docker SDK** (required by Ansible's
   `community.docker.docker_container` module).
4. **Authenticates Docker to ECR** by calling
   `aws ecr get-login-password` on the host. Credentials come from
   `LabInstanceProfile` automatically via IMDSv2; no keys on disk.
5. **Runs the Minecraft container** from the pinned ECR image,
   mounting `/opt/minecraft/data` as `/data` for world persistence,
   with `EULA=TRUE`, `VERSION`, `MEMORY`, and `MOTD` env vars set.

### Playbook variables

| Variable | Purpose | Current value |
|---|---|---|
| `aws_region` | Region where ECR lives | `us-east-1` |
| `ecr_repository` | ECR repo name (also in Terraform) | `ops3-minecraft-server` |
| `image_tag` | Pinned image tag to pull | `v1.0.0` |
| `minecraft_version` | Minecraft server version (passed to itzg image) | `1.21.1` |
| `minecraft_memory` | JVM memory size | `1G` |
| `minecraft_motd` | Server MOTD; must include name/student ID | (set per operator) |
| `data_dir` | Host directory bind-mounted to `/data` in the container | `/opt/minecraft/data` |

### Running the playbook

After Terraform has provisioned the instance and cloud-init has finished:

```bash
cd ansible/
ansible minecraft -m ping        # confirm connectivity
ansible-playbook playbook.yml    # configure host and start server
```

### Idempotency

Re-running the playbook against an already-configured host should
produce `changed=0` (or a small number from non-state-changing module
reports like image-pull checks). This is the property that makes the
playbook safe to re-run on any schedule.

### Upgrading the running version

To deploy a new image version:

1. Push a new git tag (e.g., `v1.0.1`) and let the GitHub Actions
   pipeline publish to ECR.
2. Edit `image_tag` in `ansible/playbook.yml` to match the new tag.
3. Re-run `ansible-playbook playbook.yml`. The `docker_container`
   task detects the changed image and recreates the container; the
   `/data` volume persists, so the world is preserved.

## World data persistence and recovery (step 6)

### Storage layout

- **Live world data**: `/opt/minecraft/data` on the EC2 instance,
  bind-mounted into the container at `/data`. Survives container
  recreates but is lost if the EC2 instance is destroyed.
- **Backup artifacts**: S3 bucket
  `ops3-minecraft-backups-<account-id>`. Holds timestamped tarballs
  plus a `latest.tar.gz` pointer. Versioning enabled. Lifecycle rule
  expires objects after 7 days.

### Backup mechanism

- Script: `/usr/local/bin/minecraft-backup.sh` (installed by Ansible).
- Schedule: cron, top of every hour.
- Action: tars `/opt/minecraft/data`, uploads to S3 twice (timestamped
  artifact and `latest.tar.gz`).
- Log: `/var/log/minecraft-backup.log`.
- Credentials: AWS CLI on the instance uses `LabRole` via IMDSv2 to
  authenticate to S3; no keys are stored on disk.

### Restore mechanism (rebuild path)

The Ansible playbook checks two things before each apply:

1. Is `/opt/minecraft/data` empty? (`find` reports zero matches)
2. Does `s3://<bucket>/latest.tar.gz` exist? (`aws s3 ls` returns 0)

If both are true, the playbook downloads `latest.tar.gz` and extracts
it into `/opt/minecraft/data` before starting the container. This means
a `terraform destroy && terraform apply && ansible-playbook` cycle
brings the prior world back.

If either is false, restore is skipped, preserving live data on a
playbook re-run, or accepting a fresh world on first run with no
backups yet.

### Manual operations

| Operation | Command |
|---|---|
| Force a backup now | `ssh ... 'sudo /usr/local/bin/minecraft-backup.sh'` |
| List backups | `aws s3 ls s3://ops3-minecraft-backups-<account-id>/` |
| Restore manually | Delete `/opt/minecraft/data/*` on the host, then re-run the playbook |

### Trade-offs of this design

- **Hourly cadence**: balances "low data loss" against "low storage cost
  and low write amplification." Faster cadence would lose less data but
  produce more S3 PUTs.
- **Sync, not server-side save flush**: a `sync` before tar is "good
  enough" for crash-safe storage of files. If the container has rcon
  enabled, calling `save-all flush` first would be more correct.
  Future improvement.
- **One bucket per account, not per environment**: appropriate for a lab
  assignment with one operator. A production setup would have separate
  buckets per environment to prevent accidental cross-restores.
