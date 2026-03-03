variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = contains(["ap-southeast-2"], var.aws_region)
    error_message = "Only ap-southeast-2 region is allowed for this deployment."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "Development"
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "sandbox"
}

variable "owner" {
  description = "Owner email or team name for resource tagging"
  type        = string
}

variable "min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1

  validation {
    condition     = var.min_size >= 1
    error_message = "min_size must be at least 1."
  }
}

variable "max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 3

  validation {
    condition     = var.max_size >= 1 && var.max_size <= 10
    error_message = "max_size must be between 1 and 10."
  }
}

variable "desired_capacity" {
  description = "Initial desired number of instances in ASG"
  type        = number
  default     = 1

  validation {
    condition     = var.desired_capacity >= 1
    error_message = "desired_capacity must be at least 1."
  }
}

variable "instance_type" {
  description = "EC2 instance type for ASG launch template"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t4g.micro"], var.instance_type)
    error_message = "instance_type must be one of: t3.micro, t3.small, t3.medium, t4g.micro."
  }
}

variable "ami_id" {
  description = "AMI ID for EC2 instances (Amazon Linux 2023 recommended)"
  type        = string

  validation {
    condition     = can(regex("^ami-", var.ami_id))
    error_message = "ami_id must be a valid AMI ID starting with 'ami-'."
  }
}

variable "health_check_grace_period" {
  description = "Time in seconds after instance launch before health checks start"
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 60
    error_message = "health_check_grace_period must be at least 60 seconds."
  }
}

variable "target_response_time_threshold" {
  description = "ALB target response time threshold in seconds for CloudWatch alarm"
  type        = number
  default     = 1.0

  validation {
    condition     = var.target_response_time_threshold > 0
    error_message = "target_response_time_threshold must be greater than 0."
  }
}

variable "scaling_target_requests" {
  description = "Target number of requests per instance for scaling policy"
  type        = number
  default     = 100

  validation {
    condition     = var.scaling_target_requests >= 10
    error_message = "scaling_target_requests must be at least 10."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for ASG instances (additional cost)"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access ALB on HTTP/HTTPS"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "All elements in allowed_cidr_blocks must be valid CIDR blocks."
  }
}
