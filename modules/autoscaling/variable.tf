variable "region" {
  description = "AWS region where the Auto Scaling Group and related resources will be created."
}

variable "env" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
}

variable "identifier" {
  description = "Unique identifier used to prefix resource names to avoid naming conflicts."
}

variable "vpc_id" {
  description = "ID of the VPC where the Auto Scaling Group resources will be deployed."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type to be used for instances in the Auto Scaling Group."
}

# variable "user_data" {
#   description = "User data script to be executed on EC2 instance launch."
# }

variable "scaling_in_adjustment" {
  description = "Number of instances to remove during a scale-in event."
}

variable "scaling_out_adjustment" {
  description = "Number of instances to add during a scale-out event."
}

variable "cooldown" {
  description = "Cooldown period (in seconds) between scaling activities."
}

variable "ec2_allow_http_ssh_sg_id" {
  description = "Security group ID allowing HTTP and SSH access to EC2 instances."
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs where the Auto Scaling Group instances will be launched."
  type        = list(string)
}

# variable "target_group_arn" {
#   description = "ARN of the target group associated with the Auto Scaling Group."
#   type        = string
# }

variable "ubuntu_latest_ami" {
  description = "AMI ID of the latest Ubuntu image used for EC2 instances."
  type        = string
}

variable "launch_template_name" {
  description = "Name of the EC2 launch template used by the Auto Scaling Group."
  type        = string
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances in the Auto Scaling Group."
  type        = number
}

variable "max_size" {
  description = "Maximum number of EC2 instances allowed in the Auto Scaling Group."
  type        = number
}

variable "min_size" {
  description = "Minimum number of EC2 instances allowed in the Auto Scaling Group."
  type        = number
}


variable "scale_in_policy_name" {
  description = "Name of the Auto Scaling scale-in policy."
  type        = string
}

variable "scale_out_policy_name" {
  description = "Name of the Auto Scaling scale-out policy."
  type        = string
}

variable "adjustment_type" {
  description = "Type of adjustment used in scaling policies (e.g. ChangeInCapacity)."
  type        = string
}

variable "policy_type" {
  description = "Type of Auto Scaling policy (e.g. SimpleScaling or TargetTrackingScaling)."
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair used to access instances via SSH."
}

variable "open-vpn-ami" {
  description = "AMI ID used for OpenVPN-based EC2 instances, if applicable."
}
# variable "efs_id" {}


