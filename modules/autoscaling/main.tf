###########################################################
# Elastic IP
###########################################################
resource "aws_eip" "vpn_eip" {
  vpc = true
  tags = {
    Name = "${var.env}-${var.identifier}-vpn-eip"
  }
}

############################################################
# IAM Role for EC2 with S3 and EC2 Full Access
############################################################
resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.env}-${var.identifier}-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "ec2_full_access_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_instance_profile" "ec2_s3_instance_profile" {
  name = "${var.env}-${var.identifier}-ec2-s3-instance-profile"
  role = aws_iam_role.ec2_s3_role.name
}


resource "aws_ebs_volume" "openvpn_data" {
  availability_zone = "us-east-1a" 
  size              = 8        
  type              = "gp3"
  tags = {
    Name = "${var.env}-${var.identifier}-openvpn-data"
  }
}

###########################################################
# Launch Template
###########################################################
resource "aws_launch_template" "asg_launch_template" {
  name_prefix   = "${var.env}-${var.identifier}-lt"
  image_id      = var.ubuntu_latest_ami
  instance_type = var.instance_type
  key_name      = var.key_name


  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_s3_instance_profile.name
  }
  network_interfaces {
    security_groups          = [var.ec2_allow_http_ssh_sg_id]
    associate_public_ip_address = true
  }


  block_device_mappings {
    device_name = "/dev/sdf" 
    ebs {
      volume_size          = aws_ebs_volume.openvpn_data.size
      volume_type          = aws_ebs_volume.openvpn_data.type
      delete_on_termination = false
    }
  }
    user_data = base64encode(file("${path.module}/script.sh"))



  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.env}-${var.identifier}"
    }
  }
}


###########################################################
# Auto scaling group
###########################################################
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.env}-${var.identifier}-asg"
  max_size                  = var.max_size
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  launch_template {
    id      = aws_launch_template.asg_launch_template.id
    version = "$Latest"
  }
  vpc_zone_identifier       = var.public_subnet_ids

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.env}-${var.identifier}-openvpn-server"
    propagate_at_launch = true
  }
}