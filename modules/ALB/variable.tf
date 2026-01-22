variable "region" {
  description = "AWS region where the Application Load Balancer and related resources will be created."
}

variable "env" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
}

variable "identifier" {
  description = "Unique identifier used to prefix resource names to avoid naming conflicts."
}

variable "vpc_id" {
  description = "ID of the VPC where the Application Load Balancer will be deployed."
}

variable "alb_sg_id" {
  description = "Security group ID associated with the Application Load Balancer."
}

variable "internal" {
  description = "Specifies whether the load balancer is internal (true) or internet-facing (false)."
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs where the Application Load Balancer will be placed."
}

variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled for the Application Load Balancer."
}

variable "alb_name" {
  description = "Name of the Application Load Balancer."
}

variable "load_balancer_type" {
  description = "Type of load balancer to create (e.g. application or network)."
}

variable "target_group_name" {
  description = "Name of the target group associated with the Application Load Balancer."
}

variable "alb_listener_port" {
  description = "Port on which the Application Load Balancer listener will listen."
}

variable "target_group_protocol" {
  description = "Protocol used by the target group (e.g. HTTP or HTTPS)."
}

variable "alb_listener_type" {
  description = "Protocol used by the Application Load Balancer listener (e.g. HTTP or HTTPS)."
}

variable "health_check_path" {
  description = "Path used by the target group to perform health checks on targets."
}

variable "health_check_protocol" {
  description = "Protocol used for health checks performed by the target group."
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks required before considering a target healthy."
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks required before considering a target unhealthy."
}

variable "health_check_timeout" {
  description = "Amount of time, in seconds, to wait for a health check response."
}

variable "health_check_interval" {
  description = "Time interval, in seconds, between consecutive health checks."
}

variable "health_check_matcher" {
  description = "HTTP status codes that indicate a successful health check response (e.g. 200 or 200-299)."
}
