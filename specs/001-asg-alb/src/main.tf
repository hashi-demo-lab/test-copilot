resource "random_string" "naming_suffix" {
  length  = 6
  special = false
  upper   = false
}

module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "~> 10.1"

  name    = "web-alb-${local.naming_suffix}"
  vpc_id  = data.aws_vpc.default.id
  subnets = local.subnet_ids

  enable_deletion_protection = false

  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTP from internet"
    }
    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTPS from internet"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "web"
      }
    }
  }

  target_groups = {
    web = {
      name_prefix          = "web-"
      protocol             = "HTTP"
      port                 = 80
      target_type          = "instance"
      deregistration_delay = 30

      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        protocol            = "HTTP"
        matcher             = "200"
      }

      create_attachment = false
    }
  }
}

resource "aws_security_group" "asg" {
  name_prefix = "asg-${local.naming_suffix}-"
  description = "Security group for ASG instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [module.alb.security_group_id]
  }

  egress {
    description = "Allow HTTPS outbound for package updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

module "asg" {
  source  = "app.terraform.io/hashi-demos-apj/autoscaling/aws"
  version = "~> 9.0"

  name = "web-asg-${local.naming_suffix}"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  vpc_zone_identifier       = local.asg_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  traffic_source_attachments = {
    alb_target = {
      traffic_source_identifier = module.alb.target_groups["web"].arn
      traffic_source_type       = "elbv2"
    }
  }

  security_groups = [aws_security_group.asg.id]

  image_id      = var.ami_id
  instance_type = var.instance_type

  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 8
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
      }
    }
  ]

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  create_iam_instance_profile = true
  iam_role_name               = "asg-instance-role-${local.naming_suffix}"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    CloudWatchAgentServerPolicy  = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
    }
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
}

resource "aws_autoscaling_policy" "target_tracking_scaling" {
  name                   = "target-tracking-alb-requests"
  autoscaling_group_name = module.asg.autoscaling_group_name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${module.alb.arn_suffix}/${module.alb.target_groups["web"].arn_suffix}"
    }
    target_value = var.scaling_target_requests
  }
}

module "alb_response_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "alb-high-response-time-${local.naming_suffix}"
  alarm_description   = "ALB target response time exceeds threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.target_response_time_threshold
  treat_missing_data  = "notBreaching"

  metric_name = "TargetResponseTime"
  namespace   = "AWS/ApplicationELB"
  period      = 300
  statistic   = "Average"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
}

module "asg_unhealthy_alarm" {
  source  = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.7"

  alarm_name          = "asg-unhealthy-hosts-${local.naming_suffix}"
  alarm_description   = "Unhealthy host count below threshold"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  threshold           = 1
  treat_missing_data  = "notBreaching"

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 300
  statistic   = "Average"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
    TargetGroup  = module.alb.target_groups["web"].arn_suffix
  }
}
