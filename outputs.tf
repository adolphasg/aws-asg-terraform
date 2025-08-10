# Display Auto Scaling Group name for reference
output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_asg.name
}

# Display security group ID for troubleshooting
output "security_group_id" {
  description = "Security group ID attached to instances"
  value       = aws_security_group.web_sg.id
}

# Display subnet IDs used by the ASG
output "selected_subnet_ids" {
  description = "The two subnets used by the ASG"
  value       = local.selected_subnet_ids
}

# Display S3 bucket name for state management
output "s3_backend_bucket_name" {
  description = "S3 bucket created for Terraform state storage"
  value       = aws_s3_bucket.tf_state_bucket.bucket
}