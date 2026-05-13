variable "key_name" {
  description = "Name of an existing AWS EC2 key pair (e.g., ~/.ssh/cs312-key.pem)"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH to the instance. Use your-ip/32 for tighter security; 0.0.0.0/0 is permissive."
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small (2 GB RAM) is the smallest size with enough headroom for a JVM + OS + Docker."
  type        = string
  default     = "t3.small"
}
