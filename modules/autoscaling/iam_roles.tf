# IAM Resources
resource "aws_iam_role" "openvpn_role" {
  name = "${var.env}-${var.identifier}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "openvpn_ec2_policy" {
  name        = "${var.env}-${var.identifier}-ec2-policy"
  description = "Permissions for OpenVPN EC2 instance"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:Describe*",
          "ec2:AttachVolume",
          "ec2:CreateTags"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "openvpn_ec2_policy_attach" {
  role       = aws_iam_role.openvpn_role.name
  policy_arn = aws_iam_policy.openvpn_ec2_policy.arn
}

resource "aws_iam_instance_profile" "openvpn_instance_profile" {
  name = "${var.env}-${var.identifier}-ec2-profile"
  role = aws_iam_role.openvpn_role.name
}


############################################################
# Lambda IAM Role
############################################################
resource "aws_iam_role" "lambda_role" {
  name = "lambda-ec2-snapshot-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda-ec2-snapshot-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateImage",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "ec2:DescribeSnapshots",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:CreateVolume",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ssm:GetParameter",
          "ec2:AssociateAddress",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeAddresses"

        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
  depends_on = [aws_iam_role.lambda_role]
}

############################################################
# EventBridge Rules
############################################################
resource "aws_cloudwatch_event_rule" "ec2_lifecycle_rule" {
  name        = "ec2-lifecycle-rule"
  description = "Capture EC2 instance launch and termination events"

  event_pattern = jsonencode({
    "source" : ["aws.ec2"],
    "detail-type" : ["EC2 Instance State-change Notification"],
    "detail" : {
      "state" : ["terminated"]
    }
  })

}
resource "aws_cloudwatch_event_rule" "snapshot_schedule_rule" {
  name        = "ec2-snapshot-schedule"
  description = "Trigger snapshot Lambda every 5 minutes"

  schedule_expression = "rate(2 minutes)"
}


resource "aws_cloudwatch_event_target" "ec2_lifecycle_lambda_target" {
  rule      = aws_cloudwatch_event_rule.ec2_lifecycle_rule.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.ec2_snapshot_lambda.arn

  depends_on = [
    aws_lambda_function.ec2_snapshot_lambda,
    aws_lambda_permission.allow_eventbridge,
    aws_cloudwatch_event_rule.ec2_lifecycle_rule
  ]
}
resource "aws_cloudwatch_event_target" "schedule_target" {
  rule      = aws_cloudwatch_event_rule.snapshot_schedule_rule.name
  target_id = "lambda-schedule"
  arn       = aws_lambda_function.ec2_snapshot_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_snapshot_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_lifecycle_rule.arn
  # depends_on = [aws_lambda_function.ec2_snapshot_lambda]
}
resource "aws_lambda_permission" "allow_eventbridge_schedule" {
  statement_id  = "AllowExecutionFromEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_snapshot_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.snapshot_schedule_rule.arn
}
