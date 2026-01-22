# resource "aws_launch_template" "openvpn" {
#   name_prefix   = "${var.env}-${var.identifier}-lt"
#   image_id      = var.ubuntu_latest_ami
#   instance_type = var.instance_type
#   key_name      = var.key_name

#   network_interfaces {
#     associate_public_ip_address = true
#     security_groups             = [var.ec2_allow_http_ssh_sg_id]
#   }

#   user_data = base64encode(templatefile(
#     "${path.module}/script.sh",
#     {
#       efs_id = var.efs_id
#     }
#   ))

#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "${var.env}-openvpn"
#       AutoSnapshot = "false"
#     }
#   }
# }

# resource "aws_autoscaling_group" "this" {
#   name             = "${var.env}-${var.identifier}-asg"
#   min_size         = 1
#   max_size         = 1
#   desired_capacity = 1

#   vpc_zone_identifier = var.public_subnet_ids

#   launch_template {
#     id      = aws_launch_template.openvpn.id
#     version = "$Latest"
#   }

#   health_check_type         = "EC2"
#   health_check_grace_period = 300
# }


############################################################
# IAM Role for EC2 with S3 Full Access
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

# Attach S3 Full Access Policy
resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_s3_instance_profile" {
  name = "${var.env}-${var.identifier}-ec2-s3-instance-profile"
  role = aws_iam_role.ec2_s3_role.name
}


# # # ###############################################################################################
# # # ################################ volume  #######################################################
# # # ################################################################################################


resource "aws_ebs_volume" "openvpn_data" {
  availability_zone = "us-east-1a"   # same as your subnet's AZ
  size              = 8        # adjust size as needed
  type              = "gp3"
  tags = {
    Name = "${var.env}-${var.identifier}-openvpn-data"
  }
}

############################################################
# Lambda Function
############################################################
resource "aws_lambda_function" "ec2_snapshot_lambda" {
  function_name = "ec2-snapshot-handler"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 512
  filename      = "${path.module}/lambda_function.zip"
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custom_policy_attach
  ]

  environment {
    variables = {

      DEFAULT_SUBNET_ID       = var.public_subnet_ids[0]
      DEFAULT_SECURITY_GROUPS = var.ec2_allow_http_ssh_sg_id
      DEFAULT_INSTANCE_TYPE   = var.instance_type
      DEFAULT_KEY_NAME        = var.key_name
      DEFAULT_TAG_NAME        = var.ec2_snapshot_name
    }
  }
}


resource "aws_launch_template" "asg_launch_template" {
  name_prefix   = "${var.env}-${var.identifier}-lt"
  image_id      = var.ubuntu_latest_ami
  instance_type = var.instance_type
  key_name      = var.key_name


  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_s3_instance_profile.name
  }
  network_interfaces {
    security_groups = [var.ec2_allow_http_ssh_sg_id]
    associate_public_ip_address = true
  }

  block_device_mappings {
    device_name = "/dev/sdf"  # will mount as /dev/sdf in EC2
    ebs {
      volume_size          = aws_ebs_volume.openvpn_data.size
      volume_type          = aws_ebs_volume.openvpn_data.type
      delete_on_termination = false
    }
  }
   user_data = base64encode(file("${path.module}/script.sh"))

#    user_data = file("${path.module}/script.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.env}-${var.identifier}-instance"
    }
  }
}

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
  # target_group_arns         = [var.target_group_arn]

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.env}-${var.identifier}-asg"
    propagate_at_launch = true
  }
}

