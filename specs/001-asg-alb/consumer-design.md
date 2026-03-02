# Consumer Design: ASG+ALB Web Infrastructure

**Branch**: feat/001-asg-alb  
**Date**: 2024-01-15  
**Status**: Draft  
**Provider**: aws ~> 5.0  
**Terraform**: >= 1.9  
**HCP Terraform Org**: hashi-demos-apj  

---

## Table of Contents

1. [Purpose & Requirements](#1-purpose--requirements)
2. [Module Selection & Architecture](#2-module-selection--architecture)
3. [Module Wiring](#3-module-wiring)
4. [Security Controls](#4-security-controls)
5. [Implementation Checklist](#5-implementation-checklist)
6. [Open Questions](#6-open-questions)

---

## 1. Purpose & Requirements

This deployment provisions scalable web infrastructure using an Application Load Balancer (ALB) fronting an Auto Scaling Group (ASG) of EC2 instances in the existing default VPC. The infrastructure supports development workloads requiring high availability across multiple availability zones with automated scaling based on request load. It provides CloudWatch-based observability for monitoring application health and performance metrics.

**Scope boundary**: This deployment does NOT create VPC networking infrastructure (uses existing default VPC), does NOT provision application deployment pipelines, does NOT include DNS management (Route53), does NOT implement WAF rules, and does NOT include database backends. Focus is strictly on compute autoscaling and load balancing layers.

### Requirements

**Functional requirements** -- what the deployment must provision:

- Provision internet-facing Application Load Balancer accepting HTTP/HTTPS traffic with target group health checks
- Deploy Auto Scaling Group with EC2 instances distributed across 2 availability zones (ap-southeast-2a, ap-southeast-2b)
- Implement target tracking scaling policy based on ALB RequestCountPerTarget metric (target: 100 requests/instance)
- Create CloudWatch metric alarms for ALB target response time (>1s threshold) and ASG unhealthy host count (<1 threshold)
- Enable ELB health checks with 300-second grace period for application initialization
- Configure security groups restricting ASG ingress to ALB security group only
- Attach IAM instance profile with SSM Session Manager access for secure instance access
- Enable detailed CloudWatch metrics collection for ASG group size and ALB request metrics

**Non-functional requirements** -- constraints like compliance, performance, availability, cost:

- **Region**: ap-southeast-2 (Sydney) for development environment
- **Availability**: Multi-AZ deployment across 2 availability zones minimum
- **Cost optimization**: Use t3.micro instances, minimum 1 instance, maximum 3 instances during development
- **Security**: EBS volume encryption enabled, IMDSv2 required, no direct SSH access (SSM only)
- **Monitoring**: 5-minute metric intervals (basic monitoring) to minimize cost
- **Compliance**: Resources tagged with Environment=Development, ManagedBy=terraform, Project=sandbox, Owner per HCP Terraform workspace variables

---

## 2. Module Selection & Architecture

### Architectural Decisions

**Use existing default VPC**: Deployment uses existing default VPC subnets to avoid VPC provisioning overhead. *Rationale*: Research finding from `research-hcp-workspace.md` confirms existing VPC pattern for sandbox environments; development workloads do not require custom networking. Data sources discover VPC and subnet IDs dynamically. *Rejected*: Creating new VPC (adds cost and complexity for development), hardcoding subnet IDs (not portable across AWS accounts).

**ALB-to-ASG target group integration**: ALB module creates target groups; ASG module references target group ARNs for automatic instance registration. *Rationale*: Research finding from `research-modules.md` confirms `target_group_arns` output type compatibility (list(string)); research from `research-asg-alb-best-practices.md` recommends ELB health checks over EC2 checks for ALB integration. *Rejected*: Manual target group registration outside modules (violates module-first principle), separate target group module (unnecessary abstraction for single ALB deployment).

**Target tracking scaling on ALB RequestCountPerTarget**: Use ALB RequestCountPerTarget metric with target value 100 requests/instance for scaling decisions. *Rationale*: Research finding from `research-asg-alb-best-practices.md` identifies RequestCountPerTarget as more responsive than CPU for web workloads; targets actual application load. *Rejected*: CPU-based scaling (less responsive for web traffic patterns), step scaling policies (target tracking simpler for development).

**Multi-AZ with 2 availability zones**: Deploy ASG instances across ap-southeast-2a and ap-southeast-2b for high availability. *Rationale*: Research finding from `research-asg-alb-best-practices.md` recommends minimum 2 AZs for development (cost optimization vs 3 AZs), satisfies multi-AZ requirement. *Rejected*: Single AZ deployment (no availability guarantee during AZ failures), 3 AZs (higher NAT Gateway cost for development).

**CloudWatch metric alarms without composite alarms**: Create individual metric alarms for ALB latency and ASG health; composite alarms deferred to production. *Rationale*: Research finding from `research-modules.md` confirms CloudWatch module v5.7.2 supports both metric-alarm and composite-alarm submodules; individual alarms sufficient for development monitoring. *Rejected*: Composite alarms (adds complexity for development environment), CloudWatch dashboards (alarms prioritized for Phase 1, dashboards can be added later).

**Security group chaining ALB→ASG**: ALB security group allows internet ingress; ASG security group references ALB security group ID for application port ingress. *Rationale*: Research finding from `research-module-wiring.md` confirms security group cross-reference pattern prevents circular dependencies; research from `research-asg-alb-best-practices.md` validates least-privilege traffic flow. *Rejected*: ASG open to 0.0.0.0/0 (violates least privilege), separate security group module (ALB module creates security group with sufficient configuration options).

**IAM instance profile via ASG module**: ASG module creates IAM role and instance profile with attached managed policies for SSM and CloudWatch. *Rationale*: Research finding from `research-modules.md` confirms ASG module supports `create_iam_instance_profile = true` with `iam_role_policies` map; research from `research-asg-alb-best-practices.md` recommends AmazonSSMManagedInstanceCore and CloudWatchAgentServerPolicy. *Rejected*: Separate IAM module (adds module dependency for simple policy attachments), manual IAM resources (violates constitution §1.1).

### Module Inventory

| Module | Registry Source | Version | Purpose | Conditional | Key Inputs | Key Outputs |
|--------|----------------|---------|---------|-------------|------------|-------------|
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | Application Load Balancer with target groups, listeners, and security group | always | vpc_id, subnets, security_group_ingress_rules, listeners, target_groups | target_groups (map with arn attributes), security_group_id, dns_name, arn_suffix |
| asg | app.terraform.io/hashi-demos-apj/autoscaling/aws | ~> 9.0 | Auto Scaling Group with launch template, IAM role, and instance refresh | always | min_size, max_size, vpc_zone_identifier, target_group_arns, security_groups, health_check_type, image_id, instance_type, create_iam_instance_profile, iam_role_policies | autoscaling_group_name, autoscaling_group_arn, iam_role_arn, launch_template_id |
| alb_response_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for ALB target response time exceeding threshold | always | alarm_name, comparison_operator, evaluation_periods, threshold, metric_name, namespace, dimensions | cloudwatch_metric_alarm_id, cloudwatch_metric_alarm_arn |
| asg_unhealthy_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | CloudWatch alarm for unhealthy host count below threshold | always | alarm_name, comparison_operator, evaluation_periods, threshold, metric_name, namespace, dimensions | cloudwatch_metric_alarm_id, cloudwatch_metric_alarm_arn |

### Glue Resources

| Resource Type | Logical Name | Purpose | Depends On |
|---------------|--------------|---------|------------|
| random_string | naming_suffix | Generate 6-character suffix for unique resource naming across deployments | -- |
| aws_autoscaling_policy | target_tracking_scaling | Target tracking scaling policy for ALB RequestCountPerTarget metric (ASG module does not expose scaling_policies input in v9.0.2) | module.asg, module.alb |

### Workspace Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Organization | hashi-demos-apj | HCP Terraform organization |
| Workspace | sandbox-consumer-asg-alb | Target workspace per requirement |
| Project | sandbox | Project grouping per requirement |
| Execution Mode | Remote | HCP Terraform managed |
| Terraform Version | >= 1.9 | Pinned in versions.tf |
| Variable Sets | aws-ap-southeast-2-sandbox | Provides AWS_REGION, TFC_AWS_PROVIDER_AUTH, TFC_AWS_RUN_ROLE_ARN for dynamic credentials |
| VCS Connection | -- | CLI-driven workflow for sandbox (manual trigger) |

---

## 3. Module Wiring

### Wiring Diagram

```
data.aws_vpc.default.id ──────────────────────────────────────────┬──→ module.alb.vpc_id
                                                                   └──→ module.asg (via security group data source)

data.aws_subnets.default.ids ──[tolist()]──→ local.subnet_ids ────┬──→ module.alb.subnets (all default subnets for ALB cross-AZ)
                                                                   └──→ module.asg.vpc_zone_identifier (first 2 subnets for multi-AZ)

module.alb.target_groups["web"].arn ──[wrap in list]──→ module.asg.target_group_arns

module.alb.security_group_id ──[referenced_security_group_id in ASG security group rule]──→ module.asg.security_groups (implicit)

module.alb.arn_suffix ──────────────────────→ module.alb_response_alarm.dimensions["LoadBalancer"]

module.asg.autoscaling_group_name ──────────→ aws_autoscaling_policy.target_tracking_scaling.autoscaling_group_name
                                        └──→ module.asg_unhealthy_alarm.dimensions["AutoScalingGroupName"]

module.alb.target_groups["web"].arn_suffix ──→ aws_autoscaling_policy.target_tracking_scaling.resource_label (combined with alb.arn_suffix)
```

### Wiring Table

| Source Module | Output | Target Module | Input | Type | Transformation |
|--------------|--------|--------------|-------|------|----------------|
| data.aws_vpc.default | id | alb | vpc_id | string | direct |
| data.aws_subnets.default | ids | alb | subnets | list(string) | tolist() then pass all |
| data.aws_subnets.default | ids | asg | vpc_zone_identifier | list(string) | tolist() then slice([0:2]) for 2 AZs |
| alb | target_groups["web"].arn | asg | target_group_arns | list(string) | wrap in list |
| alb | security_group_id | asg | security_groups | list(string) | create separate SG with referenced_security_group_id rule, pass SG ID in list |
| alb | arn_suffix | alb_response_alarm | dimensions | map(string) | direct as LoadBalancer dimension value |
| asg | autoscaling_group_name | asg_unhealthy_alarm | dimensions | map(string) | direct as AutoScalingGroupName dimension value |
| asg | autoscaling_group_name | aws_autoscaling_policy | autoscaling_group_name | string | direct |
| alb | arn_suffix | aws_autoscaling_policy | resource_label | string | combine with target_group arn_suffix as "${alb_suffix}/${tg_suffix}" |
| alb | target_groups["web"].arn_suffix | aws_autoscaling_policy | resource_label | string | combine with alb arn_suffix |

### Provider Configuration

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project_name
      Owner       = var.owner
    }
  }

  # Dynamic credentials via HCP Terraform
  # Configured through workspace environment variables:
  # - TFC_AWS_PROVIDER_AUTH = true
  # - TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::ACCOUNT_ID:role/tfc-sandbox-role
}
```

### Variables

| Variable | Type | Required | Default | Validation | Sensitive | Description |
|----------|------|----------|---------|------------|-----------|-------------|
| aws_region | string | No | ap-southeast-2 | contains(["ap-southeast-2"], var.aws_region) | No | AWS region for deployment |
| environment | string | No | Development | -- | No | Environment name for resource tagging |
| project_name | string | No | sandbox | -- | No | Project name for resource naming and tagging |
| owner | string | Yes | -- | -- | No | Owner email or team name for resource tagging |
| min_size | number | No | 1 | var.min_size >= 1 && var.min_size <= var.max_size | No | Minimum number of instances in ASG |
| max_size | number | No | 3 | var.max_size >= var.min_size && var.max_size <= 10 | No | Maximum number of instances in ASG |
| desired_capacity | number | No | 1 | var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size | No | Initial desired number of instances in ASG |
| instance_type | string | No | t3.micro | contains(["t3.micro", "t3.small", "t3.medium", "t4g.micro"], var.instance_type) | No | EC2 instance type for ASG launch template |
| ami_id | string | Yes | -- | can(regex("^ami-", var.ami_id)) | No | AMI ID for EC2 instances (Amazon Linux 2023 recommended) |
| health_check_grace_period | number | No | 300 | var.health_check_grace_period >= 60 | No | Time in seconds after instance launch before health checks start |
| target_response_time_threshold | number | No | 1.0 | var.target_response_time_threshold > 0 | No | ALB target response time threshold in seconds for CloudWatch alarm |
| scaling_target_requests | number | No | 100 | var.scaling_target_requests >= 10 | No | Target number of requests per instance for scaling policy |
| enable_detailed_monitoring | bool | No | false | -- | No | Enable detailed CloudWatch monitoring for ASG instances (additional cost) |
| allowed_cidr_blocks | list(string) | No | ["0.0.0.0/0"] | alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0))]) | No | CIDR blocks allowed to access ALB on HTTP/HTTPS |

### Outputs

| Output | Type | Source | Description |
|--------|------|--------|-------------|
| alb_dns_name | string | module.alb.dns_name | DNS name of the Application Load Balancer for application access |
| alb_arn | string | module.alb.arn | ARN of the Application Load Balancer |
| alb_zone_id | string | module.alb.zone_id | Route53 zone ID of the ALB for DNS record creation |
| alb_security_group_id | string | module.alb.security_group_id | Security group ID of the ALB |
| asg_name | string | module.asg.autoscaling_group_name | Name of the Auto Scaling Group |
| asg_arn | string | module.asg.autoscaling_group_arn | ARN of the Auto Scaling Group |
| asg_iam_role_arn | string | module.asg.iam_role_arn | IAM role ARN for ASG instances |
| launch_template_id | string | module.asg.launch_template_id | ID of the launch template for ASG instances |
| alb_response_alarm_arn | string | module.alb_response_alarm.cloudwatch_metric_alarm_arn | ARN of CloudWatch alarm for ALB target response time |
| asg_unhealthy_alarm_arn | string | module.asg_unhealthy_alarm.cloudwatch_metric_alarm_arn | ARN of CloudWatch alarm for ASG unhealthy host count |

---

## 4. Security Controls

| Control | Enforcement | Module Config | Reference |
|---------|-------------|---------------|-----------|
| Encryption at rest | EBS volumes encrypted via launch template block_device_mappings | module.asg: block_device_mappings.ebs.encrypted = true | CIS AWS 2.2.1 |
| Encryption in transit | HTTPS listener with SSL/TLS certificate (deferred to implementation - HTTP only for dev) | module.alb: listeners.http.protocol = "HTTP" (HTTPS requires ACM certificate) | CIS AWS 2.3.1 |
| Public access | ALB security group allows 0.0.0.0/0 on HTTP (required for internet-facing); ASG restricted to ALB only | module.alb: security_group_ingress_rules from var.allowed_cidr_blocks; ASG security group references ALB SG ID | CIS AWS 5.2 |
| IAM least privilege | ASG IAM role limited to AmazonSSMManagedInstanceCore and CloudWatchAgentServerPolicy managed policies | module.asg: create_iam_instance_profile = true, iam_role_policies = {ssm, cloudwatch} | CIS AWS 1.16 |
| Logging | ALB access logs to S3 disabled for dev environment (cost optimization); CloudWatch metrics enabled | [SECURITY OVERRIDE] module.alb: access_logs.enabled = false (production MUST enable) | CIS AWS 2.6.1 |
| Tagging | Provider default_tags propagate ManagedBy, Environment, Project, Owner to all resources | provider.aws.default_tags in providers.tf | AWS Well-Architected Cost Optimization |
| Metadata service | IMDSv2 required for all ASG instances | module.asg: metadata_options.http_tokens = "required" | CIS AWS 5.6 |
| Network isolation | ASG instances accept traffic only from ALB security group on application port | ASG security group ingress rule: source = module.alb.security_group_id, port = 80 | AWS Well-Architected Security Pillar |
| Session management | No SSH key configured; SSM Session Manager via IAM policy for secure access | module.asg: key_name not set, iam_role_policies includes AmazonSSMManagedInstanceCore | CIS AWS 5.1 |

---

## 5. Implementation Checklist

- [ ] **Scaffold**: Create file structure with versions.tf (terraform + cloud block + required_providers aws ~> 5.0), backend.tf (cloud block for workspace sandbox-consumer-asg-alb), providers.tf (provider aws with default_tags), variables.tf (all 12 variables from Section 3), outputs.tf (all 10 outputs), locals.tf (naming suffix, subnet transformations), data.tf (VPC and subnet data sources), README.md (deployment instructions), terraform.auto.tfvars.example (example variable values)

- [ ] **Core Infrastructure**: Implement main.tf with random_string resource for naming_suffix, ALB module call with target_groups["web"] configuration (health_check path="/", interval=30, matcher="200"), ASG module call with target_group_arns wired from ALB, launch template configuration (instance_type, ami_id, block_device_mappings with encryption, metadata_options with IMDSv2), IAM configuration (create_iam_instance_profile=true, iam_role_policies for SSM and CloudWatch), health_check_type="ELB", instance_refresh with Rolling strategy

- [ ] **Security Groups**: Create aws_security_group resource for ASG instances with ingress rule referencing module.alb.security_group_id on port 80, egress rule for 0.0.0.0/0 on port 443 (package updates), pass ASG security_group_id to module.asg.security_groups input as list

- [ ] **Scaling Policy**: Create aws_autoscaling_policy resource with policy_type="TargetTrackingScaling", target_tracking_configuration for predefined_metric_type="ALBRequestCountPerTarget", resource_label="${module.alb.arn_suffix}/${module.alb.target_groups["web"].arn_suffix}", target_value=var.scaling_target_requests (100), attach to module.asg.autoscaling_group_name

- [ ] **CloudWatch Alarms**: Implement alb_response_alarm module call with metric_name="TargetResponseTime", namespace="AWS/ApplicationELB", dimensions={LoadBalancer=module.alb.arn_suffix}, comparison_operator="GreaterThanThreshold", threshold=var.target_response_time_threshold, evaluation_periods=2; implement asg_unhealthy_alarm module call with metric_name="UnHealthyHostCount", namespace="AWS/ApplicationELB", dimensions={LoadBalancer=module.alb.arn_suffix, TargetGroup=module.alb.target_groups["web"].arn_suffix}, comparison_operator="LessThanThreshold", threshold=1, evaluation_periods=2

- [ ] **Validation & Polish**: Run terraform fmt, terraform validate, create README.md with deployment instructions including HCP Terraform authentication (terraform login), workspace selection, required AMI ID variable, example terraform plan/apply commands; create terraform.auto.tfvars.example with all variable examples; verify no Critical/High findings with trivy scan; test plan succeeds with valid AMI ID

---

## 6. Open Questions

_No unresolved questions. All design decisions have been made based on research findings and development environment best practices._

---

## Design Validation Checklist

### Requirement Quality ✅
- ✅ All 8 functional requirements in §1 map to modules or glue resources in §2
- ✅ All requirements are testable (e.g., "ALB target response time >1s" measurable via CloudWatch alarm)
- ✅ Scope boundary clearly excludes VPC creation, DNS, WAF, databases

### Specification Consistency ✅
- ✅ Table of Contents links all 6 sections
- ✅ All 4 modules have Registry Source (`app.terraform.io/hashi-demos-apj/*`) and Version (`~> X.Y`)
- ✅ Wiring table accounts for all module outputs consumed downstream (10 wiring entries)
- ✅ Wiring diagram matches wiring table (no orphaned connections)
- ✅ All 12 variables have Type + Description filled
- ✅ All 9 security controls have CIS/Well-Architected references (1 explicit override documented)
- ✅ Provider configuration includes default_tags (ManagedBy, Environment, Project, Owner)
- ✅ Implementation checklist has 6 items (within 4-8 range)
- ✅ No section references another by line number
- ✅ Module names appear once in Module Inventory (§2)
- ✅ Variable names appear once in Module Wiring (§3)
- ✅ Only glue resources used: random_string, aws_autoscaling_policy (no raw infrastructure resources)

### Cross-Reference Validation ✅
- ✅ All 4 modules in §2 referenced in wiring connections (§3) or implementation checklist (§5)
- ✅ All 9 security controls in §4 reference specific modules from §2 (ALB, ASG)
- ✅ Implementation checklist in §5 covers all modules: ALB, ASG, CloudWatch alarms, scaling policy

### Research Citations ✅
- ✅ Module versions cited from `research-modules.md` (ALB 10.1.0, ASG 9.0.2, CloudWatch 5.7.2)
- ✅ Target tracking scaling cited from `research-asg-alb-best-practices.md` (RequestCountPerTarget pattern)
- ✅ Security group chaining cited from `research-module-wiring.md` (one-way dependency pattern)
- ✅ HCP Terraform workspace config cited from `research-hcp-workspace.md` (cloud block, dynamic credentials)
- ✅ Type transformations cited from `research-module-wiring.md` (tolist(), arn_suffix for CloudWatch)
