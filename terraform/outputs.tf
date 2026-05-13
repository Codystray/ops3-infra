output "ecr_repository_url" {
  description = "ECR repository URL: use this in the GitHub Actions workflow"
  value       = aws_ecr_repository.minecraft.repository_url
}

output "instance_public_ip" {
  description = "Public IPv4 address of the Minecraft EC2 instance"
  value       = aws_instance.minecraft.public_ip
}

output "instance_id" {
  description = "EC2 instance ID for reference and console lookup"
  value       = aws_instance.minecraft.id
}

output "ssh_command" {
  description = "Ready-to-paste SSH command for connecting to the instance"
  value       = "ssh -i ~/.ssh/cs312-key.pem ubuntu@${aws_instance.minecraft.public_ip}"
}

output "backup_bucket_name" {
  description = "S3 bucket holding Minecraft world backups"
  value       = aws_s3_bucket.backups.id
}
