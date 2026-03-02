output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer for application access"
  value       = module.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.arn
}

output "alb_zone_id" {
  description = "Route53 zone ID of the ALB for DNS record creation"
  value       = module.alb.zone_id
}

output "alb_security_group_id" {
  description = "Security group ID of the ALB"
  value       = module.alb.security_group_id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.asg.autoscaling_group_name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = module.asg.autoscaling_group_arn
}

output "asg_iam_role_arn" {
  description = "IAM role ARN for ASG instances"
  value       = module.asg.iam_role_arn
}

output "launch_template_id" {
  description = "ID of the launch template for ASG instances"
  value       = module.asg.launch_template_id
}

output "alb_response_alarm_arn" {
  description = "ARN of CloudWatch alarm for ALB target response time"
  value       = module.alb_response_alarm.cloudwatch_metric_alarm_arn
}

output "asg_unhealthy_alarm_arn" {
  description = "ARN of CloudWatch alarm for ASG unhealthy host count"
  value       = module.asg_unhealthy_alarm.cloudwatch_metric_alarm_arn
}
