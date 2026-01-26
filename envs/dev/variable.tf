
variable "identifier" {}
variable "env" {}
variable "aws_region" {}
variable "key_name" {}
variable "allowed_user_arns" {}


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
    ubuntu_latest_ami      = string
    loop                   = string
  }))
}