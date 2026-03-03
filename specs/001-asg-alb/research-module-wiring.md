## Research: Module Wiring Patterns for ASG+ALB Consumer Infrastructure

### Decision

Use standard AWS reference architecture for ALB-to-ASG integration with VPC data sources, security group cross-references, CloudWatch unified dashboards, and IAM role passthrough — ensures type-safe wiring with minimal transformations.

### Wiring Patterns Identified

#### 1. ALB → ASG Target Group Attachment

**Pattern**: ALB module creates target groups, ASG module references them

- **ALB Module Output**: `target_group_arns` (type: `list(string)`)
  - Exports list of target group ARNs created by ALB module
  - Computed after ALB target group resource creation
  
- **ASG Module Input**: `target_group_arns` (type: `list(string)`)
  - Accepts list of ARNs to attach ASG instances to
  - Direct passthrough: `module.alb.target_group_arns`

**Type Compatibility**: ✅ Direct match — both `list(string)`

**Common Mistakes**:
- ❌ Passing single ARN as string instead of list: `[module.alb.target_group_arn]`
- ❌ Using `target_group_names` instead of `target_group_arns` (names don't work for attachment)
- ❌ Attempting to pass before ALB target group is created (dependency cycle)

**Best Practice**:
```hcl
module "asg" {
  source = "app.terraform.io/org/asg/aws"
  
  target_group_arns = module.alb.target_group_arns
  # Direct passthrough - no transformation needed
}
```

---

#### 2. VPC Data Source → Module Subnet Inputs

**Pattern**: Data source for existing VPC, outputs feed into module subnet configuration

- **Data Source Output**: `aws_subnets.private.ids` (type: `set(string)`)
  - Returns subnet IDs as a set (unordered collection)
  - Filter by VPC ID and tags
  
- **Module Input Expectation**: `subnet_ids` (type: `list(string)`)
  - Most modules expect ordered list of subnet IDs
  
**Type Compatibility**: ⚠️ Requires transformation — `set(string)` → `list(string)`

**Transformation Required**:
```hcl
data "aws_vpc" "existing" {
  default = true  # or filter by tags
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
  
  tags = {
    Tier = "Private"
  }
}

locals {
  # Convert set to list for module consumption
  private_subnet_ids = tolist(data.aws_subnets.private.ids)
  
  # If you need consistent ordering across runs
  private_subnet_ids_sorted = sort(tolist(data.aws_subnets.private.ids))
}

module "alb" {
  source = "app.terraform.io/org/alb/aws"
  
  # ALB needs public subnets
  subnet_ids = local.public_subnet_ids
}

module "asg" {
  source = "app.terraform.io/org/asg/aws"
  
  # ASG instances in private subnets
  subnet_ids = local.private_subnet_ids
}
```

**Common Mistakes**:
- ❌ Direct passthrough without `tolist()`: `data.aws_subnets.private.ids` (type mismatch error)
- ❌ Using `data.aws_subnet` (singular) in a loop instead of `data.aws_subnets` (plural)
- ❌ Not filtering subnets by tier (public vs private) — ALB needs public, ASG needs private
- ❌ Hardcoding subnet IDs instead of using data sources

**Best Practice Variable Defaults**:
```hcl
variable "vpc_id" {
  type        = string
  description = "VPC ID for infrastructure deployment"
  default     = null  # If null, use default VPC
}

variable "subnet_filter_tags" {
  type        = map(string)
  description = "Tags to filter subnets by tier"
  default = {
    Tier = "Private"  # or "Public" for ALB
  }
}
```

---

#### 3. Security Group References Between ALB and ASG

**Pattern**: ALB security group allows inbound traffic, ASG security group allows traffic from ALB

- **ALB Module Output**: `security_group_id` (type: `string`)
  - Security group ID for the ALB
  - Allows inbound HTTP/HTTPS from internet
  
- **ASG Module Input**: `allowed_security_group_ids` (type: `list(string)`)
  - List of security group IDs allowed to reach ASG instances
  - Creates ingress rules allowing traffic from these groups

**Type Compatibility**: ⚠️ Requires wrapping — `string` → `list(string)`

**Wiring Pattern**:
```hcl
module "alb" {
  source = "app.terraform.io/org/alb/aws"
  
  vpc_id     = data.aws_vpc.existing.id
  subnet_ids = local.public_subnet_ids
  
  # ALB security group allows internet traffic
  ingress_cidr_blocks = var.allowed_cidr_blocks  # e.g., ["0.0.0.0/0"]
}

module "asg" {
  source = "app.terraform.io/org/asg/aws"
  
  vpc_id     = data.aws_vpc.existing.id
  subnet_ids = local.private_subnet_ids
  
  # ASG security group allows traffic from ALB only
  allowed_security_group_ids = [module.alb.security_group_id]
  
  # Port must match ALB target group health check port
  application_port = 8080
}
```

**Common Mistakes**:
- ❌ Passing string instead of list: `module.alb.security_group_id` (should be `[module.alb.security_group_id]`)
- ❌ Opening ASG to `0.0.0.0/0` instead of restricting to ALB security group
- ❌ Port mismatch between ALB target group and ASG ingress rules
- ❌ Circular dependency: ALB referencing ASG security group AND ASG referencing ALB security group

**Best Practice**:
- ALB ingress from internet (or restricted CIDR)
- ASG ingress only from ALB security group
- One-way dependency: ASG → ALB (no circular references)

---

#### 4. CloudWatch Dashboard Integration with ASG/ALB Metrics

**Pattern**: CloudWatch dashboard module references ASG and ALB identifiers to query metrics

- **ALB Module Outputs**:
  - `load_balancer_arn_suffix` (type: `string`) — for CloudWatch metric dimensions
  - `target_group_arn_suffix` (type: `string`) — for target group metrics
  - `load_balancer_dns_name` (type: `string`) — for dashboard annotations
  
- **ASG Module Outputs**:
  - `autoscaling_group_name` (type: `string`) — for ASG metric dimensions
  - `launch_template_id` (type: `string`) — for tracking configuration changes
  
- **CloudWatch Dashboard Module Inputs**:
  - `alb_arn_suffix` (type: `string`)
  - `asg_name` (type: `string`)
  - `target_group_arn_suffix` (type: `string`)

**Type Compatibility**: ✅ Direct match — all `string` types

**Wiring Pattern**:
```hcl
module "cloudwatch_dashboard" {
  source = "app.terraform.io/org/cloudwatch-dashboard/aws"
  
  dashboard_name = "${var.project_name}-${var.environment}"
  
  # ALB metrics
  alb_arn_suffix            = module.alb.load_balancer_arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  
  # ASG metrics
  autoscaling_group_names = [module.asg.autoscaling_group_name]
  
  # Widget configuration
  metrics = [
    {
      namespace  = "AWS/ApplicationELB"
      metric     = "TargetResponseTime"
      dimensions = { LoadBalancer = module.alb.load_balancer_arn_suffix }
    },
    {
      namespace  = "AWS/ApplicationELB"
      metric     = "HealthyHostCount"
      dimensions = { 
        LoadBalancer = module.alb.load_balancer_arn_suffix
        TargetGroup  = module.alb.target_group_arn_suffix
      }
    },
    {
      namespace  = "AWS/AutoScaling"
      metric     = "GroupDesiredCapacity"
      dimensions = { AutoScalingGroupName = module.asg.autoscaling_group_name }
    }
  ]
}
```

**Common Mistakes**:
- ❌ Using full ARN instead of ARN suffix for CloudWatch dimensions (AWS API requires suffix)
- ❌ Hardcoding metric dimensions instead of referencing module outputs
- ❌ Not including both ALB and ASG metrics in unified dashboard
- ❌ Using `load_balancer_id` (doesn't exist) instead of `load_balancer_arn_suffix`

**Best Practice Variable Defaults**:
```hcl
variable "dashboard_enabled" {
  type        = bool
  description = "Create CloudWatch dashboard for monitoring"
  default     = true
}

variable "dashboard_period" {
  type        = number
  description = "Metric period in seconds"
  default     = 300  # 5 minutes
}
```

---

#### 5. IAM Role Passthrough Patterns

**Pattern**: ASG module accepts IAM instance profile, separate IAM module creates roles/profiles

**Option A: Module Creates IAM Role**
- **ASG Module Input**: `create_iam_role` (type: `bool`, default: `true`)
- **ASG Module Input**: `iam_role_policies` (type: `map(string)`) — policy ARNs to attach
- **ASG Module Output**: `iam_role_arn` (type: `string`)

```hcl
module "asg" {
  source = "app.terraform.io/org/asg/aws"
  
  create_iam_role = true
  
  iam_role_policies = {
    ssm_managed   = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    s3_readonly   = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    cloudwatch    = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
}

# Export for downstream consumers
output "instance_role_arn" {
  value       = module.asg.iam_role_arn
  description = "IAM role ARN for ASG instances"
}
```

**Option B: External IAM Role**
- **IAM Module Output**: `instance_profile_name` (type: `string`)
- **ASG Module Input**: `iam_instance_profile_name` (type: `string`)

```hcl
module "iam" {
  source = "app.terraform.io/org/iam-role/aws"
  
  role_name = "${var.project_name}-asg-role"
  
  trusted_service = "ec2.amazonaws.com"
  
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
}

module "asg" {
  source = "app.terraform.io/org/asg/aws"
  
  create_iam_role          = false
  iam_instance_profile_name = module.iam.instance_profile_name
}
```

**Type Compatibility**: ✅ Direct match — `string` passthrough

**Common Mistakes**:
- ❌ Passing `iam_role_arn` when module expects `iam_instance_profile_name` (or vice versa)
- ❌ Creating role in consumer code with raw `aws_iam_role` resource (violates constitution)
- ❌ Not attaching SSM policy (prevents Systems Manager access for debugging)
- ❌ Overly permissive policies attached by default

**Best Practice Variable Defaults**:
```hcl
variable "create_iam_role" {
  type        = bool
  description = "Create IAM role for ASG instances (false = provide existing profile)"
  default     = true
}

variable "iam_instance_profile_name" {
  type        = string
  description = "Existing IAM instance profile name (only if create_iam_role = false)"
  default     = null
}

variable "additional_policy_arns" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach"
  default     = []
}
```

---

#### 6. Output Exposure for Downstream Consumers

**Pattern**: Consumer root module exports key identifiers for chaining deployments

**Required Outputs**:
```hcl
# ALB outputs
output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "ALB DNS name for application access"
}

output "alb_zone_id" {
  value       = module.alb.zone_id
  description = "Route53 hosted zone ID of the ALB"
}

output "alb_arn" {
  value       = module.alb.arn
  description = "ARN of the Application Load Balancer"
}

# ASG outputs
output "asg_name" {
  value       = module.asg.autoscaling_group_name
  description = "Name of the Auto Scaling Group"
}

output "asg_arn" {
  value       = module.asg.autoscaling_group_arn
  description = "ARN of the Auto Scaling Group"
}

# Security group outputs
output "alb_security_group_id" {
  value       = module.alb.security_group_id
  description = "Security group ID for the ALB"
}

output "asg_security_group_id" {
  value       = module.asg.security_group_id
  description = "Security group ID for ASG instances"
}

# IAM outputs
output "instance_role_arn" {
  value       = module.asg.iam_role_arn
  description = "IAM role ARN for ASG instances"
}
```

**Type Consistency**: All outputs maintain original types from module outputs

**Common Mistakes**:
- ❌ Renaming outputs inconsistently (e.g., `lb_dns` instead of `alb_dns_name`)
- ❌ Not exposing security group IDs (needed for adding ingress rules externally)
- ❌ Exposing sensitive values without `sensitive = true` flag
- ❌ Missing descriptions (makes outputs hard to understand for downstream consumers)

**Best Practice**:
- Output names should mirror module output names for consistency
- Always include descriptions
- Mark sensitive outputs: `sensitive = true`
- Group related outputs with comments

---

### Type Compatibility Summary

| Wiring | Source Type | Target Type | Transformation | Example |
|--------|-------------|-------------|----------------|---------|
| ALB → ASG target groups | `list(string)` | `list(string)` | None | Direct passthrough |
| VPC data → Subnets | `set(string)` | `list(string)` | `tolist()` | `tolist(data.aws_subnets.private.ids)` |
| ALB SG → ASG SG | `string` | `list(string)` | Wrap in list | `[module.alb.security_group_id]` |
| ALB/ASG → Dashboard | `string` | `string` | None | Direct passthrough |
| IAM → ASG | `string` | `string` | None | Direct passthrough |

---

### Common Wiring Mistakes to Avoid

1. **Set vs List Type Mismatch**
   - Problem: Data sources return `set(string)`, modules expect `list(string)`
   - Solution: Always use `tolist()` when passing data source IDs to modules
   - Example: `subnet_ids = tolist(data.aws_subnets.private.ids)`

2. **Single Value vs List Mismatch**
   - Problem: Passing `string` where `list(string)` expected
   - Solution: Wrap in square brackets
   - Example: `allowed_security_group_ids = [module.alb.security_group_id]`

3. **Circular Dependencies**
   - Problem: Module A references Module B output, Module B references Module A output
   - Solution: One-way dependencies only (ASG depends on ALB, not vice versa)
   - Anti-pattern: ALB referencing ASG security group AND ASG referencing ALB security group

4. **ARN vs ARN Suffix**
   - Problem: Using full ARN for CloudWatch metric dimensions
   - Solution: Use `arn_suffix` outputs for metrics, full `arn` for IAM policies
   - Example: CloudWatch needs `load_balancer_arn_suffix`, not `load_balancer_arn`

5. **Missing Data Source Filters**
   - Problem: Data source returns wrong subnets (public instead of private)
   - Solution: Always filter by tags or attributes
   - Example: Add `tags = { Tier = "Private" }` to subnet data source

6. **Variable Default Precedence**
   - Problem: Module defaults conflict with consumer intent
   - Solution: Explicit variable values override module defaults
   - Best practice: Set consumer defaults for environment-specific values

---

### Best Practices for Variable Defaults

#### Network Configuration
```hcl
variable "vpc_id" {
  type        = string
  description = "VPC ID for deployment (null = use default VPC)"
  default     = null
  
  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-' or be null"
  }
}

variable "subnet_tier" {
  type        = string
  description = "Subnet tier for filtering (Public or Private)"
  default     = "Private"
  
  validation {
    condition     = contains(["Public", "Private"], var.subnet_tier)
    error_message = "Subnet tier must be Public or Private"
  }
}
```

#### Security Configuration
```hcl
variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access ALB"
  default     = ["0.0.0.0/0"]  # Public by default, restrict in production
  
  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All values must be valid CIDR blocks"
  }
}
```

#### Scaling Configuration
```hcl
variable "min_size" {
  type        = number
  description = "Minimum number of instances in ASG"
  default     = 2
  
  validation {
    condition     = var.min_size >= 1 && var.min_size <= var.max_size
    error_message = "Min size must be between 1 and max_size"
  }
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances in ASG"
  default     = 10
}
```

#### Feature Toggles
```hcl
variable "enable_cloudwatch_dashboard" {
  type        = bool
  description = "Create CloudWatch dashboard for monitoring"
  default     = true
}

variable "enable_detailed_monitoring" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring (additional cost)"
  default     = false  # Disabled by default for cost
}
```

---

### Rationale

Module wiring patterns follow industry-standard practices for AWS ALB+ASG architectures:

1. **Type Transformations**: AWS Terraform provider data sources return sets (unordered) while modules expect lists (ordered). Using `tolist()` is the standard transformation pattern documented in Terraform AWS provider.

2. **Security Group One-Way References**: AWS best practice for ALB-to-ASG traffic flow — ALB is the entry point, ASG instances should only accept traffic from the ALB. This prevents circular dependencies and follows least-privilege principles.

3. **ARN Suffix for CloudWatch**: AWS CloudWatch API requires ARN suffixes (not full ARNs) for metric dimensions on ALB and target groups. This is documented in AWS CloudWatch documentation for Application Load Balancer metrics.

4. **IAM Passthrough Flexibility**: Two patterns supported based on organizational preferences — some prefer modules to create IAM roles (single module deployment), others prefer separate IAM modules (centralized IAM management). Both patterns are valid.

5. **Output Exposure**: Exposing key identifiers (DNS names, ARNs, security group IDs) enables downstream consumers to reference this infrastructure in other deployments (e.g., Route53 records, additional security group rules, monitoring dashboards).

---

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Passing full ARNs to CloudWatch module | CloudWatch metric dimensions require ARN suffixes, not full ARNs |
| Bidirectional security group references | Creates circular dependency between modules |
| Hardcoded subnet IDs | Not portable across environments; data sources provide flexibility |
| Single module for ALB+ASG+CloudWatch | Violates single responsibility; harder to reuse components |
| Using `each.value` for subnet iteration | Data sources with filters return all matching subnets at once |

---

### Sources

- AWS Well-Architected Framework: Load Balancing and Auto Scaling best practices
- Terraform AWS Provider Documentation: `aws_lb`, `aws_autoscaling_group`, data sources
- HashiCorp Learn: Module composition patterns
- AWS CloudWatch Documentation: Application Load Balancer metrics and dimensions
- Terraform Language Reference: Type conversions (`tolist()`, `toset()`)
