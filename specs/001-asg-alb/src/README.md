# ASG+ALB Web Infrastructure

This Terraform configuration provisions scalable web infrastructure using an Application Load Balancer (ALB) fronting an Auto Scaling Group (ASG) of EC2 instances in the existing default VPC.

## Prerequisites

- AWS account with appropriate permissions
- HCP Terraform account access
- Terraform CLI installed (>= 1.9)
- Valid AMI ID for ap-southeast-2 region

## Configuration

### HCP Terraform Setup

1. Authenticate to HCP Terraform:
   ```bash
   terraform login
   ```

2. Ensure workspace `sandbox-consumer-asg-alb` exists in organization `hashi-demos-apj` under project `sandbox`.

3. Configure workspace environment variables for AWS dynamic credentials:
   - `TFC_AWS_PROVIDER_AUTH` = `true`
   - `TFC_AWS_RUN_ROLE_ARN` = `arn:aws:iam::<account-id>:role/tfc-sandbox-role`

### Required Variables

Create a `terraform.tfvars` file with required variables:

```hcl
owner  = "your-email@example.com"  # Required
ami_id = "ami-0c55b159cbfafe1f0"   # Required - Amazon Linux 2023 AMI for ap-southeast-2
```

See `terraform.auto.tfvars.example` for all available variables and their defaults.

## Deployment

### Plan

```bash
terraform plan
```

### Apply

```bash
terraform apply
```

After successful deployment, note the `alb_dns_name` output to access your application.

## Architecture

- **Load Balancer**: Internet-facing ALB with HTTP/HTTPS listeners
- **Auto Scaling**: 1-3 t3.micro instances across 2 availability zones
- **Scaling Policy**: Target tracking on ALB RequestCountPerTarget (100 req/instance)
- **Monitoring**: CloudWatch alarms for latency and unhealthy hosts
- **Security**: EBS encryption, IMDSv2, SSM-only access, security group chaining

## Outputs

- `alb_dns_name` - DNS name for accessing the application
- `asg_name` - Auto Scaling Group name
- `alb_arn`, `asg_arn` - Resource ARNs for reference
- `alb_response_alarm_arn`, `asg_unhealthy_alarm_arn` - CloudWatch alarm ARNs

## Cost Optimization

This configuration is optimized for development:
- t3.micro instances (minimum cost)
- Basic CloudWatch monitoring (5-minute intervals)
- Minimal instance count (1-3 instances)
- 2 AZs instead of 3

## Security

All resources are tagged with:
- `ManagedBy = "terraform"`
- `Environment = "Development"`
- `Project = "sandbox"`
- `Owner = <your-email>`

Access patterns:
- ALB: Public internet (HTTP/HTTPS)
- ASG instances: No direct access (SSM Session Manager only)
- Security groups: Chained ALB → ASG

## Cleanup

```bash
terraform destroy
```
