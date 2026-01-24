aws_region = "us-east-1"
key_name = "openvpn"
env        = "dev"
identifier = "rhizome"

vpc_configs = {
  vpc_name                = "dev-rhizome-vpc"
  cidr                    = "10.0.0.0/16"
  azs                     = ["us-east-1a", "us-east-1b"]
  public_subnets          = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets         = ["10.0.101.0/24"]
  enable_dns_hostnames    = true
  enable_dns_support      = true
  enable_ipv6             = false
  create_vpc              = true
  create_igw              = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = false
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
}

security_groups = [
  {

    cidr_blocks                = ["0.0.0.0/0"]
    alb_egress_protocol        = "tcp"
    alb_ingress_protocol       = "tcp"
    egress_protocol            = -1
    ingress_protocol           = -1
    ingress_description        = "Allow SSH access from anywhere"
    egress_description         = "Allow all traffic to go out"
    key_name                   = "sg-1"
    ingress_ports              = [0]
    egress_ports               = [0]
    public_cidr_blocks         = ["0.0.0.0/0"]
    loop                       = "loop"
    name_ec2_allow_http_ssh_sg = "ec2-allow-http-ssh-sg"
  },
]



ASG = [
  {
    instance_type          = "t3.micro"
    scaling_in_adjustment  = -1
    scaling_out_adjustment = 1
    cooldown               = 300
    desired_capacity       = 1
    max_size               = 5
    min_size               = 1
    scale_in_policy_name   = "scale-in-policy"
    scale_out_policy_name  = "scale-out-policy"
    adjustment_type        = "ChangeInCapacity"
    policy_type            = "SimpleScaling"
    ubuntu_latest_ami      = "ami-0c398cb65a93047f2"
    loop                   = "loop"
  }
]