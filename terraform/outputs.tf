output "ecr_repository_url" {
  description = "ECR repository URL: use this in the GitHub Actions workflow"
  value       = aws_ecr_repository.minecraft.repository_url
}
