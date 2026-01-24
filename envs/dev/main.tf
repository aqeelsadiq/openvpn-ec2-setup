#####################
# VPCs
#####################
module "vpc" {
  source = "../../modules/vpc"

  vpc_name                = var.vpc_configs.vpc_name
  cidr                    = var.vpc_configs.cidr
  azs                     = var.vpc_configs.azs
  public_subnets          = var.vpc_configs.public_subnets
  private_subnets         = var.vpc_configs.private_subnets
  enable_dns_hostnames    = var.vpc_configs.enable_dns_hostnames
  enable_dns_support      = var.vpc_configs.enable_dns_support
  enable_ipv6             = var.vpc_configs.enable_ipv6
  create_vpc              = var.vpc_configs.create_vpc
  create_igw              = var.vpc_configs.create_igw
  single_nat_gateway      = var.vpc_configs.single_nat_gateway
  one_nat_gateway_per_az  = var.vpc_configs.one_nat_gateway_per_az
  map_public_ip_on_launch = var.vpc_configs.map_public_ip_on_launch
  enable_nat_gateway      = var.vpc_configs.enable_nat_gateway
}


#####################
# SG
#####################
module "security" {
  for_each                   = { for security in var.security_groups : security.loop => security }
  source                     = "../../modules/securitygroup"
  env                        = var.env
  identifier                 = var.identifier
  region                     = var.aws_region
  vpc_id                     = module.vpc.vpc_id
  cidr_blocks                = each.value.cidr_blocks
  egress_protocol            = each.value.egress_protocol
  ingress_protocol           = each.value.ingress_protocol
  ingress_description        = each.value.ingress_description
  egress_description         = each.value.egress_description
  ingress_ports              = each.value.ingress_ports
  egress_ports               = each.value.egress_ports
  public_cidr_blocks         = each.value.public_cidr_blocks
  alb_egress_protocol        = each.value.alb_egress_protocol
  alb_ingress_protocol       = each.value.alb_ingress_protocol
  name_ec2_allow_http_ssh_sg = each.value.name_ec2_allow_http_ssh_sg
  depends_on = [module.vpc]

}

#####################
# ASG
#####################
module "ASG" {
  for_each = { for ASG in var.ASG : ASG.loop => ASG }

  source                   = "../../modules/autoscaling"
  env                      = var.env
  identifier               = var.identifier
  region                   = var.aws_region
  key_name                 = var.key_name
  vpc_id                   = module.vpc.vpc_id                  
  instance_type             = each.value.instance_type
  desired_capacity          = each.value.desired_capacity
  max_size                  = each.value.max_size
  min_size                  = each.value.min_size
  cooldown                  = each.value.cooldown
  scaling_in_adjustment     = each.value.scaling_in_adjustment
  scaling_out_adjustment    = each.value.scaling_out_adjustment
  scale_in_policy_name      = each.value.scale_in_policy_name
  scale_out_policy_name     = each.value.scale_out_policy_name
  adjustment_type           = each.value.adjustment_type
  policy_type               = each.value.policy_type
  launch_template_name      = "${var.env}-${var.identifier}"
  open-vpn-ami              = each.value.open_vpn_ami          
  ubuntu_latest_ami         = each.value.ubuntu_latest_ami
  ec2_allow_http_ssh_sg_id  = module.security[each.value.loop].instance_sg_id
  public_subnet_ids         = module.vpc.public_subnet_ids

  depends_on = [ module.openvpn_s3 ]
}

#####################
# S3
#####################
module "openvpn_s3" {
  source = "../../modules/s3"

  bucket_name        = "${var.env}-openvpn-bucket-aq"
  env                = var.env
  acl                = "private"
  versioning_enabled = true
  sse_enabled        = true
}