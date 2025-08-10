# Project identification and AWS region configuration
variable "project_name" {
  description = "A short name for tagging and resource naming"
  type        = string
  default     = "holiday-asg"
}

variable "aws_region" {
  description = "AWS region to deploy infrastructure"
  type        = string
  default     = "us-east-1"
}

# EC2 instance configuration
variable "instance_type" {
  description = "EC2 instance type for Auto Scaling Group"
  type        = string
  default     = "t3.micro"
}

# Auto Scaling Group capacity settings
variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 5
}

# Security configuration options
variable "enable_ssh" {
  description = "Whether to allow SSH access to instances"
  type        = bool
  default     = false
}

variable "ssh_cidr" {
  description = "CIDR block allowed for SSH access if enabled"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access"
  type        = string
  default     = ""
}

# Scaling policy configuration
variable "cpu_target_utilization" {
  description = "Target average CPU utilization for auto scaling"
  type        = number
  default     = 50
}