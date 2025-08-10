# Terraform AWS Auto Scaling Group (ASG) with Apache and S3 Remote State

A simple, production-ready setup that launches a scalable web tier on AWS using Terraform. It creates an Auto Scaling Group across two subnets in your default VPC, boots Apache on each instance, and stores Terraform state safely in an S3 bucket.

![Architecture Diagram](https://cdn.abacus.ai/images/0af30bb8-a2db-4176-84ea-82279b801321.png)

---

### Table of Contents

- [Introduction](#introduction)
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [How to Deploy (Step-by-Step)](#how-to-deploy-step-by-step)
- [Remote State Migration to S3](#remote-state-migration-to-s3)
- [Verify and Test](#verify-and-test)
- [Change Capacity During Spikes](#change-capacity-during-spikes)
- [Cleanup and Teardown](#cleanup-and-teardown)
- [Common Troubleshooting](#common-troubleshooting)
- [Configuration (Variables)](#configuration-variables)
- [Outputs](#outputs)
- [Security Notes](#security-notes)
- [Cost Notes](#cost-notes)
- [FAQ](#faq)
- [Command Cheat Sheet](#command-cheat-sheet)

---

### Introduction

Holiday traffic, flash sales, and viral moments can overwhelm fixed servers. This project uses Terraform to build a self-healing, auto-scaling web tier on AWS so your site stays fast when traffic surges and costs stay low when it’s quiet.

### Architecture Overview

-   **Default VPC** in your chosen AWS region.
-   **Two default subnets** (one in each AZ) used by an Auto Scaling Group.
-   **EC2 instances** run Apache via user data on boot.
-   **Security Group** that allows HTTP (80) and HTTPS (443) from the internet.
-   **S3 bucket** stores Terraform state (with versioning and encryption).
-   Includes a **CPU-based target tracking scaling policy**.
-   **Optional SSH access**, disabled by default.

### Prerequisites

-   **AWS account** with permissions for EC2, Auto Scaling, VPC describe, and S3.
-   **AWS CLI** configured (`aws configure`).
-   **Terraform v1.5+** installed.
-   A **default VPC** in your region (most accounts have this).

---

### Project Structure



. ├─ main.tf ├─ variables.tf └─ outputs.tf


You’ll start with local Terraform state, create the S3 bucket, then migrate your state to that bucket.

---

### How to Deploy (Step-by-Step)

1)  **Create `variables.tf`**: Define all configurable parameters for your deployment.
2)  **Create `outputs.tf`**: Specify the important values to be displayed after deployment.
3)  **Create `main.tf`**: This file contains the core infrastructure configuration. Initially, the S3 backend block should be commented out.

    ```hcl
    # Example of the backend block to comment out initially in main.tf
    # backend "s3" {}
    ```

4)  **Initialize and apply locally**: Navigate to your project directory in your terminal and run:

    ```bash
    terraform init
    terraform validate
    terraform plan
    terraform apply -auto-approve
    ```

    This will create the S3 bucket (for state), Security Group, Launch Template, ASG, and two EC2 instances.

---

### Remote State Migration to S3

Once the S3 bucket is created, you can migrate your Terraform state from local storage to S3 for better collaboration and backup.

1)  **Edit the `terraform` block in `main.tf`** to enable the backend by uncommenting the `backend "s3" {}` block.
2)  **Get the bucket name** Terraform created (you'll need this for the next step):

    ```bash
    terraform output -raw s3_backend_bucket_name
    ```

3)  **Re-initialize and migrate state to S3**:

    ```bash
    terraform init -migrate-state -reconfigure \
      -backend-config="bucket=$(terraform output -raw s3_backend_bucket_name)" \
      -backend-config="key=terraform.tfstate" \
      -backend-config="region=$(terraform output -raw aws_region 2>/dev/null || echo us-east-1)"
    ```

    If you see a "Missing region value" error, ensure your AWS CLI is configured or pass your region explicitly in the command.

---

### Verify and Test

After deployment, verify your web servers are running and accessible.

-   **Get public IPs** in the AWS console (EC2 > Instances, filter by `Name` tag like `holiday-asg-web`) or via CLI:

    ```bash
    aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=holiday-asg-web" "Name=instance-state-name,Values=running" \
      --query "Reservations[].Instances[].PublicIpAddress" --output text
    ```

-   **Open each IP in a browser**: `http://PUBLIC_IP`
    You should see a simple web page displaying the Instance ID and Availability Zone.

**Test fault tolerance:**
-   **Terminate one instance** in the AWS console (EC2 > Instances > select instance > Instance state > Terminate).
-   **Watch the ASG** (EC2 > Auto Scaling Groups > your ASG > Activity tab) to confirm it launches a replacement instance to maintain the minimum capacity.

---

### Change Capacity During Spikes

To adjust your web tier's capacity for high-traffic periods:

-   **Edit `variables.tf`** and update the values for `min_size`, `desired_capacity`, and `max_size`.
-   **Apply the change**:

    ```bash
    terraform apply -auto-approve
    ```

-   **Verify** the new number of instances in the EC2 console or with the CLI.

---

### Cleanup and Teardown

To avoid ongoing costs, destroy all resources when you're done.

-   **If your backend is S3**, Terraform cannot delete the bucket that holds its own state. You need to temporarily move state to local:
    -   **Comment out** the `backend "s3" { ... }` block in `main.tf`.
    -   **Re-initialize** and migrate state to local:
        ```bash
        terraform init -migrate-state -reconfigure
        ```
-   **In the `aws_s3_bucket` resource**, optionally add `force_destroy = true` for easier teardown of versioned buckets.
-   **Destroy all resources**:

    ```bash
    terraform destroy -auto-approve
    ```

    If the S3 bucket is versioned and not empty, it might still fail to delete. Ensure `force_destroy = true` is set and applied, or manually empty all versions and delete markers using the AWS CLI before running `terraform destroy` again.

---

### Common Troubleshooting

-   **Error: Unsupported block type for `key_name` in launch template**:
    -   **Solution:** Fix by using `key_name = var.key_name != "" ? var.key_name : null` instead of a `dynamic` block.

-   **Error: Backend configuration changed**:
    -   **Solution:** If you're moving state (e.g., local to S3), use `terraform init -migrate-state -reconfigure -backend-config=...`. If you're just updating backend config without moving state, use `terraform init -reconfigure -backend-config=...`.

-   **Error: Missing region for backend**:
    -   **Solution:** Add `-backend-config="region=us-east-1"` to your `terraform init` command, or set the `AWS_REGION` environment variable.

-   **Error: S3 bucket won’t delete (BucketNotEmpty)**:
    -   **Solution:** If Terraform manages it, ensure `force_destroy = true` is set and applied, then run `terraform destroy`. Otherwise, manually empty all object versions and delete markers using the AWS CLI, then delete the bucket.

---

### Configuration (Variables)

You can customize the deployment by modifying the `variables.tf` file. Key variables and their default values:

-   `project_name`: `holiday-asg`
-   `aws_region`: `us-east-1`
-   `instance_type`: `t3.micro`
-   `min_size` / `desired_capacity` / `max_size`: `2` / `2` / `5`
-   `enable_ssh`: `false`
-   `ssh_cidr`: `0.0.0.0/0` (applies only if `enable_ssh = true`)
-   `key_name`: `""` (no SSH key by default)
-   `cpu_target_utilization`: `50`

---

### Outputs

After `terraform apply`, the following important values will be displayed:

-   `asg_name`: Name of the Auto Scaling Group.
-   `security_group_id`: ID of the security group attached to instances.
-   `selected_subnet_ids`: The two subnets used by the ASG.
-   `s3_backend_bucket_name`: S3 bucket storing Terraform state.

---

### Security Notes

-   **SSH is disabled by default**: Only enable it if necessary (`enable_ssh = true`) and always limit `ssh_cidr` to your specific IP address (e.g., `203.0.113.10/32`).
-   **Minimal open ports**: Only web ports (80/443) are open to the world.
-   **Encrypted state**: Your S3 state file is encrypted and versioned for security and recovery.

---

### Cost Notes

-   `t3.micro` instances are low-cost, but running multiple instances and incurring data transfer will still generate charges.
-   S3 storage and requests for state are minimal but not free.
-   **Always destroy resources after testing** to avoid ongoing costs.

---

### FAQ

-   **Can I deploy in a non-default VPC?**
    -   Yes. You would need to replace the default VPC and subnets data sources with explicit configurations for your custom VPC and subnet IDs.
-   **Can I use an Application Load Balancer (ALB) in front of the ASG?**
    -   Yes. You would add ALB and Target Group resources, then attach the ASG to the target group.
-   **What if my region doesn’t have two default subnets?**
    -   You would need to manually create two public subnets in different Availability Zones within your VPC and update the `vpc_zone_identifier` in the `aws_autoscaling_group` resource with their IDs.

---

### Command Cheat Sheet

-   **Initialize Terraform**:
    ```bash
    terraform init
    ```
-   **Validate configuration**:
    ```bash
    terraform validate
    ```
-   **Preview changes**:
    ```bash
    terraform plan
    ```
-   **Apply changes**:
    ```bash
    terraform apply -auto-approve
    ```
-   **Migrate to S3 backend**:
    ```bash
    terraform init -migrate-state -reconfigure -backend-config="bucket=YOUR_BUCKET" -backend-config="key=terraform.tfstate" -backend-config="region=YOUR_REGION"
    ```
-   **Scale capacity (after editing `variables.tf`)**:
    ```bash
    terraform apply -auto-approve
    ```
-   **List instance public IPs**:
    ```bash
    aws ec2 describe-instances --filters "Name=tag:Name,Values=holiday-asg-web" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].PublicIpAddress" --output text
    ```
-   **Destroy all resources**:
    ```bash
    terraform destroy -auto-approve
    ```
