## Research: AWS Best Practices for ASG + ALB Integration

### Decision

Use private registry modules `hashi-demos-apj/alb/aws` v10.1.0 and `hashi-demos-apj/autoscaling/aws` v9.0.2 with target group integration, ELB health checks (300s grace period), target tracking scaling on ALB RequestCountPerTarget, and security group chaining (ALB SG → ASG SG) for cost-optimized development environment.

### Modules Identified

- **Primary Module**: `app.terraform.io/hashi-demos-apj/autoscaling/aws` v9.0.2
  - **Purpose**: Auto Scaling Group with launch template, IAM role, and lifecycle hooks
  - **Key Inputs**: 
    - `min_size`, `max_size`, `desired_capacity` (scaling bounds)
    - `vpc_zone_identifier` (list(string) - subnet IDs for multi-AZ)
    - `target_group_arns` (list(string) - connects to ALB target groups)
    - `health_check_type` ("ELB" for ALB health checks)
    - `health_check_grace_period` (number - seconds before health checks start)
    - `instance_refresh` (object - rolling update configuration)
    - `create_iam_instance_profile` (bool - enables IAM role creation)
    - `iam_role_policies` (map(string) - attach managed policies)
    - `security_groups` (list(string) - SGs for instances)
  - **Key Outputs**: 
    - `autoscaling_group_id` (string)
    - `autoscaling_group_arn` (string)
    - `autoscaling_group_name` (string)
    - `autoscaling_group_target_group_arns` (list(string))
    - `iam_role_arn` (string)
    - `iam_instance_profile_arn` (string)
    - `launch_template_id` (string)
    - `launch_template_arn` (string)
  - **Secure Defaults**: IAM instance profile with SSM access, encrypted EBS volumes, monitoring enabled

- **Supporting Modules**:
  - `app.terraform.io/hashi-demos-apj/alb/aws` v10.1.0 — ALB with target groups, listeners, security group
  - `app.terraform.io/hashi-demos-apj/security-group/aws` v5.3.1 — Security groups for ALB and ASG
  - `app.terraform.io/hashi-demos-apj/vpc/aws` v6.5.0 — VPC with subnets across AZs
  - `app.terraform.io/hashi-demos-apj/iam/aws` v6.2.3 — IAM roles and policies (if not using ASG module's built-in IAM)
  - `app.terraform.io/hashi-demos-apj/cloudwatch/aws` v5.7.2 — CloudWatch alarms and dashboards

- **Glue Resources Needed**: 
  - `random_id` or `random_string` for unique naming suffix
  - `aws_autoscaling_policy` (if using target tracking not supported by ASG module directly)
  - `aws_cloudwatch_metric_alarm` for custom scaling alarms

- **Wiring Considerations**:
  - **ALB → ASG**: ALB module output `target_groups["default"].arn` (string) feeds into ASG module input `target_group_arns` (list(string))
  - **Security Groups**: ALB module output `security_group_id` (string) feeds into ASG security group ingress rule `referenced_security_group_id`
  - **VPC**: VPC module outputs `private_subnet_ids` (list(string)) feed into both ALB `subnets` and ASG `vpc_zone_identifier`
  - **Health Checks**: ALB target group health check settings must align with ASG `health_check_grace_period`

### Rationale

**1. ASG + ALB Integration Best Practices:**

- **Target Groups**: ALB module supports creating multiple target groups with customizable health checks. For dev environments, use:
  - Health check interval: 30s (default, lower cost than 10s)
  - Healthy threshold: 2 consecutive checks
  - Unhealthy threshold: 2 consecutive checks
  - Timeout: 5s
  - Matcher: "200" (or "200-299" for broader success range)
  - Path: "/health" or "/" (application-specific)
  
- **Health Checks**: 
  - Set ASG `health_check_type = "ELB"` to use ALB target group health checks (more accurate than EC2 checks)
  - Set `health_check_grace_period = 300` (5 minutes) to allow instance startup and application initialization before health checks fail
  - ALB deregisters unhealthy targets automatically; ASG replaces them
  
- **Connection Draining (Deregistration Delay)**:
  - Target group `deregistration_delay = 30` seconds for dev (default is 300s)
  - Lower value reduces cost during testing (instances terminate faster)
  - Ensures in-flight requests complete before instance termination

**2. Multi-AZ Deployment for High Availability:**

- **Subnet Distribution**: Deploy ASG instances across at least 2 AZs (3 for production)
  - For dev: Use 2 AZs to minimize NAT Gateway costs
  - Set `vpc_zone_identifier` to private subnet IDs from multiple AZs
  - ALB spans all subnets automatically (deploys one node per subnet/AZ)
  
- **Min/Max/Desired Capacity**:
  - Dev environment: `min_size = 1`, `max_size = 3`, `desired_capacity = 1`
  - Ensures at least 1 instance running, can scale to 3 under load
  - Use `desired_capacity_type = "units"` for instance-based scaling
  
- **Cross-Zone Load Balancing**: 
  - ALB enables cross-zone load balancing by default (no extra cost)
  - Distributes traffic evenly across instances in all AZs

**3. Target Tracking Scaling Policies:**

- **Recommended Metrics for Dev**:
  - **ALBRequestCountPerTarget**: Target value 100-200 requests per instance
    - Scales based on actual application load
    - More responsive than CPU for web workloads
  - **CPU Utilization**: Target value 60-70% (fallback metric)
    - Lower threshold for dev to test scaling behavior
  
- **Scaling Policy Configuration**:
  ```hcl
  scaling_policies = {
    alb-requests = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ALBRequestCountPerTarget"
          resource_label = "${alb_arn_suffix}/${target_group_arn_suffix}"
        }
        target_value = 100.0
      }
    }
  }
  ```
  - Scale-out: Add instance when metric exceeds target
  - Scale-in: Remove instance after 15 minutes below target (default cooldown)
  - Warmup time: 300s (5 minutes) before instance counts toward metric

**4. Security Group Design for ALB → ASG Traffic Flow:**

- **ALB Security Group**:
  - Ingress: 
    - Port 80 (HTTP) from 0.0.0.0/0 or specific CIDR
    - Port 443 (HTTPS) from 0.0.0.0/0 or specific CIDR
  - Egress: 
    - Ports 80/443/8080 (app port) to ASG security group ID
    - Restrict to application port only (principle of least privilege)

- **ASG Security Group**:
  - Ingress:
    - Application port (e.g., 80, 8080) from ALB security group ID (referenced_security_group_id)
    - Port 22 (SSH) from bastion/VPN CIDR (optional for dev)
  - Egress:
    - Port 443 to 0.0.0.0/0 (for package updates, external API calls)
    - VPC CIDR for internal services

- **Security Group Chaining**:
  - Use `referenced_security_group_id` instead of CIDR blocks
  - ALB SG ID referenced in ASG SG ingress rule
  - Automatically adjusts when ALB scales or changes IPs

**5. IAM Roles and Instance Profiles for ASG Instances:**

- **ASG Module Built-in IAM**:
  - Set `create_iam_instance_profile = true`
  - Attach managed policies via `iam_role_policies`:
    ```hcl
    iam_role_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    }
    ```
  
- **Recommended Policies for Dev**:
  - **AmazonSSMManagedInstanceCore**: Enables AWS Systems Manager Session Manager (no SSH keys needed)
  - **CloudWatchAgentServerPolicy**: Allows CloudWatch agent to publish metrics and logs
  - **AmazonEC2ReadOnlyAccess**: Useful for debugging (optional, least privilege)

- **Custom IAM Policy** (if needed):
  - Use separate IAM module for fine-grained permissions
  - Example: S3 bucket access, Parameter Store read, Secrets Manager access
  - Pass `iam_instance_profile_name` to ASG module instead of creating inline

**6. CloudWatch Monitoring for ASG and ALB:**

- **ASG Metrics** (enabled by default):
  - `GroupMinSize`, `GroupMaxSize`, `GroupDesiredCapacity`
  - `GroupInServiceInstances`, `GroupPendingInstances`, `GroupTerminatingInstances`
  - `GroupTotalInstances`
  - Enable detailed monitoring: `enable_monitoring = true` in launch template (extra cost, 1-minute intervals)

- **ALB Metrics** (automatically collected):
  - **Request Metrics**: `RequestCount`, `HTTPCode_Target_2XX_Count`, `HTTPCode_Target_5XX_Count`
  - **Latency**: `TargetResponseTime` (p50, p95, p99)
  - **Connection Metrics**: `ActiveConnectionCount`, `NewConnectionCount`
  - **Target Health**: `HealthyHostCount`, `UnHealthyHostCount`

- **Recommended Alarms for Dev**:
  - **HealthyHostCount < 1**: Alert if no healthy instances (critical)
  - **HTTPCode_Target_5XX_Count > 10**: Alert on application errors
  - **TargetResponseTime > 5s**: Alert on slow response (p95)
  - **CPU Utilization > 80%**: Alert on resource exhaustion

- **CloudWatch Dashboards**:
  - Use CloudWatch module to create dashboards with ASG and ALB metrics
  - Combine with application logs via CloudWatch Logs agent

### Development Environment Cost Optimization:

1. **Instance Type**: Use `t3.micro` or `t4g.micro` (Graviton2, cheaper)
2. **Scaling**: Start with `min_size = 1`, scale only under load
3. **Spot Instances**: Use `mixed_instances_policy` with 50% on-demand, 50% spot for non-critical dev
4. **Multi-AZ**: Use 2 AZs instead of 3 (reduces NAT Gateway costs)
5. **Health Check Interval**: Use 30s instead of 10s (lower ALB processing)
6. **Deregistration Delay**: Use 30s instead of 300s (faster termination)
7. **Monitoring**: Basic monitoring (5-minute intervals) instead of detailed (1-minute)
8. **Access Logs**: Disable ALB access logs for dev (S3 storage cost)

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Raw `aws_lb`, `aws_autoscaling_group` resources | Organization policy requires private registry modules; modules provide secure defaults and reduce boilerplate |
| Public registry `terraform-aws-modules/alb` and `terraform-aws-modules/autoscaling` | Private registry modules are forks of these with organization-specific customizations; use private versions for consistency |
| Classic Load Balancer (CLB) | Deprecated; ALB offers better features (path-based routing, HTTP/2, WebSockets) and similar cost |
| Network Load Balancer (NLB) | Higher cost, overkill for HTTP/HTTPS workloads; use ALB unless need TCP/UDP or ultra-low latency |
| EC2 instances without ASG | No auto-healing, no scaling, manual management; ASG is best practice even for single-instance dev |
| ECS Fargate instead of EC2 ASG | Higher cost per vCPU/GB; use ASG for cost-sensitive dev environments or when need OS-level access |

### Sources

- Private Registry: 
  - https://app.terraform.io/app/hashi-demos-apj/registry/modules/private/hashi-demos-apj/alb/aws/10.1.0
  - https://app.terraform.io/app/hashi-demos-apj/registry/modules/private/hashi-demos-apj/autoscaling/aws/9.0.2
- GitHub Module Source:
  - https://github.com/hashi-demo-lab/terraform-aws-alb
  - https://github.com/hashi-demo-lab/terraform-aws-autoscaling
- AWS Documentation:
  - Auto Scaling Groups: https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html
  - ALB Target Groups: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html
  - Target Tracking Scaling: https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html
  - Multi-AZ: https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-benefits.html#arch-AutoScalingMultiAZ
  - Connection Draining: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html#deregistration-delay
  - IAM Roles for EC2: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html
  - CloudWatch Metrics: https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-instance-monitoring.html
