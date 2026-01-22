output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.application_load_balancer.arn
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.target_group.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.application_load_balancer.dns_name
}

