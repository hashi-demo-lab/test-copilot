## Research: Private registry modules for ASG, ALB, and CloudWatch dashboards

### Decision

Use `hashi-demos-apj/autoscaling/aws` v9.0.2 for Auto Scaling Groups, `hashi-demos-apj/alb/aws` v10.1.0 for Application Load Balancers, and `hashi-demos-apj/cloudwatch/aws` v5.7.2 (metric-alarm submodule) for CloudWatch monitoring — all three modules are actively maintained, provide comprehensive configuration options, and support development environment requirements in ap-southeast-2.

### Modules Identified

#### 1. Auto Scaling Group Module

- **Module Address**: `app.terraform.io/hashi-demos-apj/autoscaling/aws`
- **Latest Version**: v9.0.2
- **Source**: https://github.com/hashi-demo-lab/terraform-aws-autoscaling
- **Description**: Terraform module to create AWS Auto Scaling resources
- **Purpose**: Creates Auto Scaling Groups with launch templates, instance refresh, lifecycle hooks, and IAM role integration

**Required Inputs**:
- `min_size` (number) - The minimum size of the autoscaling group
- `max_size` (number) - The maximum size of the autoscaling group
- `vpc_zone_identifier` (list(string)) - List of subnet IDs for the ASG (use existing VPC subnets)

**Key Optional Inputs**:
- `name` (string) - Name of the ASG (default: unique name with prefix)
- `desired_capacity` (number) - Number of EC2 instances that should be running
- `launch_template_version` (string) - Launch template version (`$Latest`, `$Default`, or version number)
- `security_groups` (list(string)) - Security group IDs to associate
- `target_group_arns` (list(string)) - Set of `aws_alb_target_group` ARNs for ALB integration
- `health_check_type` (string) - `EC2` or `ELB` health check type (default: `EC2`)
- `health_check_grace_period` (number) - Time after instance comes into service before checking health
- `instance_refresh` (object) - Instance refresh configuration with rolling update strategy
- `enabled_metrics` (list(string)) - CloudWatch metrics to collect
- `image_id` (string) - AMI ID for launch template
- `instance_type` (string) - EC2 instance type
- `block_device_mappings` (list) - EBS volume configuration with encryption support
- `create_iam_instance_profile` (bool) - Whether to create IAM instance profile (default: false)
- `iam_role_policies` (map(string)) - Map of IAM policy ARNs to attach

**Key Outputs**:
- `autoscaling_group_id` (string) - The autoscaling group id
- `autoscaling_group_name` (string) - The autoscaling group name
- `autoscaling_group_arn` (string) - ARN of the Auto Scaling Group
- `autoscaling_group_target_group_arns` (list(string)) - List of Target Group ARNs attached
- `autoscaling_group_vpc_zone_identifier` (list(string)) - VPC zone identifier (subnet IDs)
- `autoscaling_group_desired_capacity` (number) - Current desired capacity
- `autoscaling_group_min_size` (number) - Minimum size
- `autoscaling_group_max_size` (number) - Maximum size
- `launch_template_id` (string) - ID of the launch template
- `launch_template_arn` (string) - ARN of the launch template
- `launch_template_name` (string) - Name of the launch template
- `iam_role_arn` (string) - IAM role ARN if created
- `iam_instance_profile_id` (string) - Instance profile ID

**Security Defaults**:
- EBS volume encryption: Configurable via `block_device_mappings.ebs.encrypted` (recommended: `true`)
- IMDSv2: Configurable via `metadata_options.http_tokens = "required"` (AWS security best practice)
- IAM role integration: Supports attaching managed policies like `AmazonSSMManagedInstanceCore`
- Monitoring: Supports detailed CloudWatch monitoring via `enable_monitoring`
- Launch template encryption: Supports EBS encryption at rest

**Example Usage Pattern**:
```hcl
module "asg" {
  source  = "app.terraform.io/hashi-demos-apj/autoscaling/aws"
  version = "9.0.2"

  name = "web-asg-dev"
  
  # Scaling configuration
  min_size         = 2
  max_size         = 4
  desired_capacity = 2
  
  # Use existing VPC subnets
  vpc_zone_identifier = var.private_subnet_ids
  
  # Health checks
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  # ALB integration
  target_group_arns = [module.alb.target_groups["web"].arn]
  
  # Launch template
  image_id      = "ami-0123456789abcdef"
  instance_type = "t3.micro"
  
  security_groups = [module.web_sg.security_group_id]
  
  # Security best practices
  block_device_mappings = [{
    device_name = "/dev/xvda"
    ebs = {
      encrypted             = true
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }]
  
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  
  # IAM role
  create_iam_instance_profile = true
  iam_role_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  
  # Instance refresh for rolling updates
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
  
  # CloudWatch metrics
  enabled_metrics = [
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]
  
  tags = {
    Environment = "development"
    Region      = "ap-southeast-2"
  }
}
```

---

#### 2. Application Load Balancer Module

- **Module Address**: `app.terraform.io/hashi-demos-apj/alb/aws`
- **Latest Version**: v10.1.0
- **Source**: https://github.com/hashi-demo-lab/terraform-aws-alb
- **Description**: Terraform module to create AWS Application/Network Load Balancer (ALB/NLB) resources
- **Purpose**: Creates Application Load Balancers with listeners, target groups, security groups, and Route53 integration

**Required Inputs**:
- `vpc_id` (string) - VPC identifier where security group will be created
- `subnets` (list(string)) - List of subnet IDs to attach to the LB (must be in different AZs)

**Key Optional Inputs**:
- `name` (string) - Name of the load balancer (max 32 characters)
- `load_balancer_type` (string) - Type: `application`, `network`, or `gateway` (default: `application`)
- `create_security_group` (bool) - Create security group for ALB (default: true)
- `security_group_ingress_rules` (map) - Map of ingress rules for the security group
- `security_group_egress_rules` (map) - Map of egress rules for the security group
- `security_groups` (list(string)) - External security group IDs to attach
- `listeners` (map(object)) - Map of listener configurations (HTTP/HTTPS)
- `target_groups` (map(object)) - Map of target group configurations
- `enable_deletion_protection` (bool) - Prevent accidental deletion (default: true)
- `drop_invalid_header_fields` (bool) - Remove invalid HTTP headers (default: false)
- `enable_cross_zone_load_balancing` (bool) - Enable cross-AZ load balancing
- `access_logs` (object) - S3 bucket configuration for access logs
- `route53_records` (map) - DNS records to create
- `web_acl_arn` (string) - WAF ACL ARN to associate

**Key Outputs**:
- `id` (string) - ID and ARN of the load balancer
- `arn` (string) - ARN of the load balancer
- `arn_suffix` (string) - ARN suffix for CloudWatch metrics
- `dns_name` (string) - DNS name of the load balancer
- `zone_id` (string) - Zone ID for Route53 records
- `listeners` (map) - Map of listeners created with attributes
- `listener_rules` (map) - Map of listener rules created
- `target_groups` (map) - Map of target groups created with attributes
- `security_group_id` (string) - ID of the security group created
- `security_group_arn` (string) - ARN of the security group
- `route53_records` (map) - Route53 records created

**Security Defaults**:
- Security group: Module creates dedicated security group with explicit rules
- HTTPS: Supports SSL/TLS certificates via ACM or IAM
- Header security: `drop_invalid_header_fields` configurable
- Deletion protection: Enabled by default to prevent accidental deletion
- Access logs: Configurable S3 bucket for audit logging
- WAF integration: Supports AWS WAF web ACL attachment

**Example Usage Pattern**:
```hcl
module "alb" {
  source  = "app.terraform.io/hashi-demos-apj/alb/aws"
  version = "10.1.0"
  
  name               = "web-alb-dev"
  load_balancer_type = "application"
  
  # Use existing VPC
  vpc_id  = var.vpc_id
  subnets = var.public_subnet_ids  # Must span multiple AZs
  
  # Security group
  create_security_group = true
  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = var.vpc_cidr
    }
  }
  
  # HTTP to HTTPS redirect
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.certificate_arn
      
      forward = {
        target_group_key = "web"
      }
    }
  }
  
  # Target groups
  target_groups = {
    web = {
      name_prefix      = "web-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
        matcher             = "200"
      }
      
      stickiness = {
        enabled = true
        type    = "lb_cookie"
        duration = 86400
      }
    }
  }
  
  # Access logging
  access_logs = {
    bucket  = var.log_bucket_name
    enabled = true
    prefix  = "alb-logs"
  }
  
  # Security
  enable_deletion_protection = false  # Set true for production
  drop_invalid_header_fields = true
  
  tags = {
    Environment = "development"
    Region      = "ap-southeast-2"
  }
}
```

---

#### 3. CloudWatch Module

- **Module Address**: `app.terraform.io/hashi-demos-apj/cloudwatch/aws`
- **Latest Version**: v5.7.2
- **Source**: https://github.com/hashi-demo-lab/terraform-aws-cloudwatch
- **Description**: Terraform module to create AWS CloudWatch resources
- **Purpose**: Provides submodules for CloudWatch alarms, dashboards, log groups, and metric streams

**Architecture**: Root module is empty - use submodules:
- `modules/metric-alarm` - Single metric alarms
- `modules/composite-alarm` - Composite alarms combining multiple alarms
- `modules/metric-alarms-by-multiple-dimensions` - Alarms across multiple dimensions
- `modules/cis-alarms` - CIS benchmark compliance alarms
- `modules/log-group` - CloudWatch log group creation
- `modules/log-metric-filter` - Extract metrics from logs

**Submodule: metric-alarm**

**Required Inputs**:
- `alarm_name` (string) - Unique alarm name within AWS account
- `comparison_operator` (string) - Arithmetic operation (`GreaterThanThreshold`, `LessThanThreshold`, etc.)
- `evaluation_periods` (number) - Number of periods to evaluate
- `threshold` (number) - Value to compare against

**Key Optional Inputs**:
- `metric_name` (string) - Name of the metric
- `namespace` (string) - Metric namespace (e.g., `AWS/ApplicationELB`, `AWS/EC2`)
- `period` (string) - Period in seconds for statistic evaluation
- `statistic` (string) - Statistic to apply (SampleCount, Average, Sum, Minimum, Maximum)
- `dimensions` (map(string)) - Dimensions for the metric
- `alarm_description` (string) - Description of the alarm
- `alarm_actions` (list(string)) - ARNs to execute on ALARM state (e.g., SNS topics)
- `ok_actions` (list(string)) - ARNs to execute on OK state
- `insufficient_data_actions` (list(string)) - ARNs for INSUFFICIENT_DATA state
- `treat_missing_data` (string) - How to handle missing data (missing, ignore, breaching, notBreaching)
- `metric_query` (any) - For metric math expressions (up to 20)

**Key Outputs**:
- `cloudwatch_metric_alarm_id` (string) - ID of the CloudWatch alarm
- `cloudwatch_metric_alarm_arn` (string) - ARN of the CloudWatch alarm

**Submodule: composite-alarm**

**Required Inputs**:
- `alarm_name` (string) - Unique composite alarm name
- `alarm_rule` (string) - Expression combining other alarms (max 10240 chars)

**Key Optional Inputs**:
- `alarm_description` (string) - Description of composite alarm
- `alarm_actions` (list(string)) - ARNs to execute on ALARM state
- `ok_actions` (list(string)) - ARNs to execute on OK state
- `actions_enabled` (bool) - Whether actions should execute (default: true)
- `actions_suppressor` (map(any)) - Actions suppressor configuration

**Security Defaults**:
- Encryption: CloudWatch Logs supports encryption at rest with KMS
- Access control: Alarms support IAM-based access control
- SNS integration: Secure notification delivery via encrypted SNS topics
- Metric data: Encrypted in transit via HTTPS

**Example Usage Pattern**:
```hcl
# ALB Target Response Time Alarm
module "alb_target_response_alarm" {
  source = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"
  
  alarm_name          = "web-alb-high-response-time-dev"
  alarm_description   = "ALB target response time exceeds 1 second"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1.0
  
  # Metric configuration
  metric_name = "TargetResponseTime"
  namespace   = "AWS/ApplicationELB"
  period      = "60"
  statistic   = "Average"
  
  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
  
  # Actions
  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  
  treat_missing_data = "notBreaching"
  
  tags = {
    Environment = "development"
    Service     = "web-alb"
  }
}

# ASG CPU Utilization Alarm
module "asg_cpu_alarm" {
  source = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.2"
  
  alarm_name          = "web-asg-high-cpu-dev"
  alarm_description   = "ASG CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  
  metric_name = "CPUUtilization"
  namespace   = "AWS/EC2"
  period      = "300"
  statistic   = "Average"
  
  dimensions = {
    AutoScalingGroupName = module.asg.autoscaling_group_name
  }
  
  alarm_actions = [var.sns_topic_arn]
  
  treat_missing_data = "notBreaching"
}

# Composite Alarm - Unhealthy Application
module "unhealthy_app_alarm" {
  source = "app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/composite-alarm"
  version = "5.7.2"
  
  alarm_name        = "web-app-unhealthy-dev"
  alarm_description = "Application is unhealthy - high latency AND high error rate"
  
  # Combine multiple alarms
  alarm_rule = "ALARM(${module.alb_target_response_alarm.cloudwatch_metric_alarm_id}) AND ALARM(${module.alb_5xx_alarm.cloudwatch_metric_alarm_id})"
  
  alarm_actions = [var.critical_sns_topic_arn]
  
  actions_enabled = true
}
```

---

### Wiring Considerations

**ASG → ALB Integration**:
- ASG `target_group_arns` input requires ALB `target_groups` output
- **Output Type**: `module.alb.target_groups` is a map of objects; extract ARN: `module.alb.target_groups["web"].arn`
- **Type**: `list(string)` for ASG, single target group ARN per entry

**ASG → Security Group**:
- ASG `security_groups` input expects list of security group IDs
- ALB module creates security group; use `module.alb.security_group_id`
- **Type**: `list(string)`

**CloudWatch → ASG/ALB**:
- CloudWatch alarms use `dimensions` to target specific resources
- ASG dimension: `AutoScalingGroupName = module.asg.autoscaling_group_name`
- ALB dimension: `LoadBalancer = module.alb.arn_suffix` (NOT full ARN)
- **Type**: `map(string)` for dimensions

**VPC Integration**:
- Both ASG and ALB require existing VPC subnet IDs
- ASG: `vpc_zone_identifier` (private subnets recommended)
- ALB: `subnets` (public subnets for internet-facing, must span 2+ AZs)
- **Type**: `list(string)` for both

**Glue Resources Needed**:
- `random_string` - Generate unique naming suffixes for resources
- `aws_sns_topic` - Target for CloudWatch alarm notifications (not in private registry)

---

### Rationale

**Module Selection**:
1. All three modules exist in the `hashi-demos-apj` private registry with recent versions
2. Modules are forks of the well-maintained `terraform-aws-modules` public registry modules, ensuring quality and community patterns
3. Active maintenance: ASG updated Nov 2025, ALB updated Nov 2025, CloudWatch updated Nov 2025
4. Comprehensive feature set: Support for launch templates, instance refresh, target groups, listeners, metric alarms, and composite alarms
5. Security-conscious design: Support for EBS encryption, IMDSv2, deletion protection, SSL/TLS, and access logging

**Development Environment Suitability**:
- Modules support existing VPC integration (no VPC creation required)
- Flexible scaling: ASG min/max/desired capacity fully configurable for dev workloads
- Cost optimization: Support for Spot instances, small instance types (t3.micro)
- Region agnostic: Works in ap-southeast-2 with standard AWS resource patterns

**Interface Compatibility**:
- ASG outputs (`autoscaling_group_name`) → CloudWatch alarm dimensions ✓
- ALB outputs (`target_groups["key"].arn`, `arn_suffix`) → ASG input + CloudWatch dimensions ✓
- All modules use consistent HCL types (string, list(string), map) for cross-module references
- No type transformations required for module composition

---

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Public registry `terraform-aws-modules/*` | Organization uses private registry; want centralized module versioning and governance |
| Raw `aws_autoscaling_group` + `aws_lb` resources | Constitution requires consumer code to compose from registry modules, not author raw resources |
| AWS CloudFormation | Organization standard is Terraform; existing tooling and workflows |
| Different CloudWatch dashboard module | CloudWatch module v5.7.2 provides comprehensive alarm submodules; dashboards can be added via `modules/dashboard` if needed |

---

### Sources

- Private Registry API: `https://app.terraform.io/api/registry/v1/modules/hashi-demos-apj`
- ASG Module: https://github.com/hashi-demo-lab/terraform-aws-autoscaling
- ALB Module: https://github.com/hashi-demo-lab/terraform-aws-alb
- CloudWatch Module: https://github.com/hashi-demo-lab/terraform-aws-cloudwatch
- AWS ALB Documentation: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/
- AWS Auto Scaling Documentation: https://docs.aws.amazon.com/autoscaling/
- AWS CloudWatch Documentation: https://docs.aws.amazon.com/cloudwatch/
- AWS Security Best Practices: https://docs.aws.amazon.com/securityhub/latest/userguide/autoscaling-controls.html
