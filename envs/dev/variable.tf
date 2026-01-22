
variable "identifier" {}
variable "env" {}
variable "aws_region" {}
variable "key_name" {}


variable "vpc_configs" {
  description = "Map of VPC configurations"
  type = object({
    vpc_name                = string
    cidr                    = string
    azs                     = list(string)
    public_subnets          = list(string)
    private_subnets         = list(string)
    enable_dns_hostnames    = bool
    enable_dns_support      = bool
    enable_ipv6             = bool
    create_vpc              = bool
    create_igw              = bool
    single_nat_gateway      = bool
    one_nat_gateway_per_az  = bool
    map_public_ip_on_launch = bool
    enable_nat_gateway      = bool
  })
}

variable "security_groups" {
  type = list(object({
    loop                 = string
    cidr_blocks          = list(string)
    egress_protocol      = string
    ingress_protocol     = string
    ingress_ports        = list(number)
    egress_ports         = list(number)
    name_ec2_allow_http_ssh_sg = string
    alb_ingress_protocol = string
    alb_egress_protocol  = string
    ingress_description  = string
    egress_description   = string
    public_cidr_blocks   = list(string)
  }))
}





variable "ASG" {
  description = "Auto Scaling Group configuration"
  type = list(object({
    instance_type          = string
    scaling_in_adjustment  = number
    scaling_out_adjustment = number
    cooldown               = number
    desired_capacity       = number
    max_size               = number
    min_size               = number
    scale_in_policy_name   = string
    scale_out_policy_name  = string
    adjustment_type        = string
    policy_type            = string
    launch_template_name   = string
    open_vpn_ami           = string
    ubuntu_latest_ami      = string
    ec2_snapshot_name      = string
    loop                   = string
  }))
}

# variable "ALB" {
#   description = "ALB configuration"
#   type = list(object({
#     alb_name                         = string
#     load_balancer_type               = string
#     target_group_name                = string
#     alb_listener_port                = number
#     target_group_protocol            = string
#     alb_listener_type                = string
#     loop                             = string
#     alb_egress_protocol              = string
#     enable_deletion_protection       = bool
#     internal                         = bool
#     health_check_path                = string
#     health_check_protocol            = string
#     health_check_healthy_threshold   = number
#     health_check_unhealthy_threshold = number
#     health_check_timeout             = number
#     health_check_interval            = number
#     health_check_matcher             = string
#   }))
# }