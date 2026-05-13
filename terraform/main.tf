terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "minecraft" {
  name        = "ops3-minecraft-sg"
  description = "SSH and Minecraft access for the Ops 3 server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ops3-minecraft-sg"
  }
}

data "aws_ecr_repository" "minecraft" {
  name = "ops3-minecraft-server"
}

data "aws_s3_bucket" "backups" {
  bucket = var.backup_bucket
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "minecraft" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.minecraft.id]
  iam_instance_profile   = "LabInstanceProfile"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    # cloud-init runs this once on first boot.
    # Ansible's standard modules require Python 3 on the managed node.
    # Everything else is the playbook's job.
    apt-get update -y
    apt-get install -y python3
  EOF

  tags = {
    Name = "ops3-minecraft"
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"

  content = <<-EOF
    [minecraft]
    mc ansible_host=${aws_instance.minecraft.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/cs312-key.pem
  EOF
}

resource "null_resource" "ansible_provision" {
  triggers = {
    instance_id     = aws_instance.minecraft.id
    playbook_sha256 = filesha256("${path.module}/../ansible/playbook.yml")
  }

  # Wait for SSH to come up, then wait for cloud-init to finish so Python 3
  # is installed before Ansible tries to connect.
  provisioner "local-exec" {
    command = <<-EOT
      for i in $(seq 1 30); do
        if ssh -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=5 \
               -i ~/.ssh/cs312-key.pem \
               ubuntu@${aws_instance.minecraft.public_ip} \
               'cloud-init status --wait' 2>/dev/null; then
          echo "Host is ready after $((i*10)) seconds."
          exit 0
        fi
        echo "Waiting for SSH on ${aws_instance.minecraft.public_ip} (attempt $i/30)..."
        sleep 10
      done
      echo "Host never became reachable on SSH after 300 seconds."
      exit 1
    EOT
  }

  # Run the playbook.
  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = "ansible-playbook playbook.yml"
  }

  depends_on = [
    local_file.ansible_inventory,
  ]
}
