variable "region" {
  description = "AWS region where the resources will be created."
  type        = string
}

variable "env" {
  description = "Deployment environment name, e.g., dev, staging, prod."
  type        = string
}

variable "identifier" {
  description = "Unique identifier to prefix resource names to avoid naming conflicts."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the security groups and related resources will be deployed."
  type        = string
}

variable "cidr_blocks" {
  description = "List of CIDR blocks allowed for ingress or egress traffic."
  type        = list(string)
}

variable "egress_protocol" {
  description = "Protocol to allow for egress traffic (e.g., tcp, udp, icmp)."
  type        = string
}

variable "ingress_protocol" {
  description = "Protocol to allow for ingress traffic (e.g., tcp, udp, icmp)."
  type        = string
}

variable "egress_description" {
  description = "Description for the egress rule of the security group."
  type        = string
}

variable "ingress_description" {
  description = "Description for the ingress rule of the security group."
  type        = string
}

variable "egress_ports" {
  description = "List of ports to allow for egress traffic."
  type        = list(number)
}

variable "ingress_ports" {
  description = "List of ports to allow for ingress traffic."
  type        = list(number)
}

variable "public_cidr_blocks" {
  description = "List of public CIDR blocks allowed to access the security group."
  type        = list(string)
}

variable "alb_egress_protocol" {
  description = "Protocol to allow for egress traffic specific to the Application Load Balancer."
  type        = string
}

variable "alb_ingress_protocol" {
  description = "Protocol to allow for ingress traffic specific to the Application Load Balancer."
  type        = string
}

variable "name_ec2_allow_http_ssh_sg" {
  description = "Name of the security group that allows HTTP and SSH access to EC2 instances."
  type        = string
}
