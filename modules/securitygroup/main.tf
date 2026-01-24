resource "aws_security_group" "instance_sg" {
  vpc_id = var.vpc_id
  dynamic "ingress" {
    for_each = var.ingress_ports
    iterator = port
    content {
      description = var.alb_ingress_protocol
      from_port   = port.value
      to_port     = port.value
      protocol    = var.ingress_protocol
      cidr_blocks = var.public_cidr_blocks


    }
  }



  dynamic "egress" {
    for_each = var.egress_ports
    iterator = port
    content {
      description = var.egress_description
      from_port   = port.value
      to_port     = port.value
      protocol    = var.egress_protocol
      cidr_blocks = var.cidr_blocks

    }
  }
  tags = {
    Name = "${var.env}-${var.name_ec2_allow_http_ssh_sg}"
  }
}