# Terraform and provider version requirements
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Initially commented out - will enable after S3 bucket creation
  # backend "s3" {}
}

# Configure AWS provider with specified region
provider "aws" {
  region = var.aws_region
}

# Data sources for dynamic resource naming and identification
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Locate the default VPC in the current region
data "aws_vpc" "default" {
  default = true
}

# Find all default subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  # Only select subnets that are default for their availability zone
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Local values for computed configurations
locals {
  # Select first two subnets for high availability deployment
  selected_subnet_ids = slice(data.aws_subnets.default.ids, 0, 2)

  # Generate unique S3 bucket name using account ID
  tf_state_bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# S3 bucket for storing Terraform state remotely
resource "aws_s3_bucket" "tf_state_bucket" {
  bucket = local.tf_state_bucket_name
  tags = {
    Name        = "${var.project_name}-tfstate"
    Project     = var.project_name
    Environment = "prod"
  }
}

# Enable versioning on the state bucket for rollback capability
resource "aws_s3_bucket_versioning" "tf_state_bucket_versioning" {
  bucket = aws_s3_bucket.tf_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption for the state bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_bucket_sse" {
  bucket = aws_s3_bucket.tf_state_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Security group allowing web traffic from internet
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow web traffic from the internet"
  vpc_id      = data.aws_vpc.default.id

  # Allow HTTP traffic on port 80
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Allow HTTPS traffic on port 443
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Conditionally allow SSH access if enabled
  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  # Allow all outbound traffic for updates and dependencies
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name    = "${var.project_name}-web-sg"
    Project = var.project_name
  }
}

# Find the latest Amazon Linux 2 AMI
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# User data script to install and configure Apache web server
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    
    # Update system packages
    yum update -y
    
    # Install Apache web server
    yum install -y httpd
    
    # Enable Apache to start on boot
    systemctl enable httpd
    systemctl start httpd

    # Get instance metadata for display
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo "unknown")
    AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone || echo "unknown")

    # Create custom HTML page showing instance information
    cat > /var/www/html/index.html <<EOT
    <html>
      <head><title>${var.project_name} - Web Server</title></head>
      <body style="font-family: Arial; margin: 2rem;">
        <h1>${var.project_name} - Auto Scaling Web Server</h1>
        <p>Instance ID: $INSTANCE_ID</p>
        <p>Availability Zone: $AZ</p>
        <p>Deployed via Terraform Infrastructure as Code</p>
      </body>
    </html>
    EOT
  EOF
}

# Launch template defining instance configuration
resource "aws_launch_template" "web_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.al2.id
  instance_type = var.instance_type

  # Conditionally set SSH key pair if provided
  key_name = var.key_name != "" ? var.key_name : null

  update_default_version = true

  # Network configuration for public access
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  # Encode user data script for instance initialization
  user_data = base64encode(local.user_data)

  # Tags applied to launched instances
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-web"
      Project     = var.project_name
      Role        = "web"
      ManagedBy   = "terraform"
    }
  }

  tags = {
    Name    = "${var.project_name}-lt"
    Project = var.project_name
  }
}

# Auto Scaling Group spanning multiple availability zones
resource "aws_autoscaling_group" "web_asg" {
  name                      = "${var.project_name}-asg"
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size
  vpc_zone_identifier       = local.selected_subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 60

  # Reference to launch template for instance configuration
  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  # Configuration for smooth rolling updates
  min_elb_capacity           = 0
  force_delete               = true
  wait_for_capacity_timeout  = "10m"

  # Tags propagated to all instances
  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  # Ensure proper resource lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Auto scaling policy based on CPU utilization
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project_name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  policy_type            = "TargetTrackingScaling"

  # Scale based on average CPU utilization across all instances
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_utilization
  }
}