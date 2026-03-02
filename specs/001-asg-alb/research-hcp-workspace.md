## Research: HCP Terraform workspace configuration for sandbox deployment

### Decision

Use `cloud` block configuration with workspace naming pattern `sandbox-consumer-asg-alb`, organization `hashi-demos-apj`, project `sandbox`, remote execution mode, and AWS dynamic credentials via OIDC integration.

### Workspace Configuration

**Workspace Naming Convention**:
- **Pattern**: `sandbox-consumer-asg-alb` (following sandbox_consumer_asg<REPO_NAME> pattern)
- **Organization**: `hashi-demos-apj`
- **Project**: `sandbox`
- **Execution Mode**: Remote (HCP Terraform-managed infrastructure)
- **Auto-apply**: Manual (recommended for sandbox testing before automation)

**Required terraform {} Block Configuration**:

```hcl
terraform {
  cloud {
    organization = "hashi-demos-apj"
    
    workspaces {
      name    = "sandbox-consumer-asg-alb"
      project = "sandbox"
    }
    
    hostname = "app.terraform.io"  # Optional, defaults to this value
  }
  
  required_version = "~> 1.9"  # Specify version constraint
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**Authentication**:
- Use `terraform login` command for CLI authentication
- Generates/stores user token in `~/.terraform.d/credentials.tfrc.json`
- Token provides workspace read/write access for CLI-driven workflows

### Dynamic Credentials for AWS

**Setup Requirements**:

1. **AWS OIDC Identity Provider**:
   - Provider URL: `https://app.terraform.io` (no trailing slash)
   - Audience: `aws.workload.identity`

2. **AWS IAM Role Trust Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:hashi-demos-apj:project:sandbox:workspace:sandbox-consumer-asg-alb:run_phase:*"
        }
      }
    }
  ]
}
```

3. **Required Environment Variables** (set in workspace or variable set):

| Variable | Value | Purpose |
|----------|-------|---------|
| `TFC_AWS_PROVIDER_AUTH` | `true` | Enable dynamic credentials |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/tfc-sandbox-role` | IAM role ARN to assume |
| `AWS_REGION` | `ap-southeast-2` | Target AWS region |

**Optional Variables**:
- `TFC_AWS_PLAN_ROLE_ARN` - Separate role for plan phase
- `TFC_AWS_APPLY_ROLE_ARN` - Separate role for apply phase
- `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` - Custom audience (defaults to `aws.workload.identity`)

### Variable Sets for ap-southeast-2

**Regional Variable Set Structure**:

Create a variable set named `aws-ap-southeast-2-sandbox` with:

**Environment Variables**:
- `AWS_REGION` = `ap-southeast-2` (Terraform variable)
- `TFC_AWS_PROVIDER_AUTH` = `true` (Environment variable, sensitive)
- `TFC_AWS_RUN_ROLE_ARN` = `arn:aws:iam::ACCOUNT_ID:role/tfc-sandbox-role` (Environment variable, sensitive)

**Terraform Variables** (examples):
- `region` = `ap-southeast-2`
- `availability_zones` = `["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]`

**Scope**: Apply to project `sandbox` (project-scoped variable set) or specific workspaces

**Variable Precedence** (highest to lowest):
1. Priority global variable sets
2. Priority project-scoped variable set (organization-owned)
3. Priority workspace-scoped variable set (organization-owned)
4. Priority project-scoped variable set (project-owned)
5. Priority workspace-scoped variable set (project-owned)
6. Non-priority workspace-scoped variable set (organization-owned)
7. Non-priority project-scoped variable set (organization-owned)
8. Non-priority workspace-scoped variable set (project-owned)
9. Non-priority project-scoped variable set (project-owned)
10. Non-priority global variable set
11. Workspace-specific variables
12. `.tfvars` files (uploaded with configuration)
13. CLI arguments (run-specific via `-var` flag)

**Best Practice**: Use project-scoped variable sets for shared regional configuration; workspace-specific variables for unique values.

### Execution Mode Considerations

**Remote Execution (Recommended for Sandbox)**:
- **Benefits**:
  - Consistent run environment
  - Audit trail and run history
  - Collaborative plan review
  - No local Terraform installation required
  - State locking automatic
  - Policy enforcement available
- **Drawbacks**:
  - Requires configuration upload
  - Network dependency
  - Resource limits on runners

**Local Execution**:
- Only use for debugging or testing
- State still stored remotely
- Variables/variable sets NOT evaluated
- Requires local Terraform installation

**Agent Execution**:
- For private infrastructure access
- Requires agent deployment
- Not recommended for initial sandbox testing

### State Management and Locking

**Automatic Handling**:
- State stored in HCP Terraform workspace automatically
- Locking handled by HCP Terraform (no DynamoDB table needed)
- State versions retained (historical snapshots)
- No explicit backend configuration needed (overridden by cloud block)

**State Access**:
- Current state + historical versions viewable in UI
- State versions include diff view
- Roll back capability to previous versions
- Intermediate state versions cleaned up on unlock

**Permissions Required**:
- Read state: View workspace
- Write state: Plan/apply permissions
- Read outputs from other workspaces: Read access to those workspaces

**State Outputs Sharing**:
```hcl
# Reference outputs from another workspace
data "terraform_remote_state" "vpc" {
  backend = "remote"
  
  config = {
    organization = "hashi-demos-apj"
    workspaces = {
      name = "sandbox-vpc-networking"
    }
  }
}
```

### Best Practices for Sandbox Environments

**Workspace Settings**:
1. **Auto-apply**: Disabled (manual confirmation for sandbox testing)
2. **Execution Mode**: Remote (consistent environment)
3. **Terraform Version**: Pin to specific version or use constraint (e.g., `~> 1.9`)
4. **Run Triggers**: Disabled initially (enable for automation later)
5. **Notifications**: Enable for Slack/email to track deployment status

**Security**:
1. **Dynamic Credentials**: Always use OIDC over static credentials
2. **Least Privilege**: IAM role permissions limited to sandbox resources
3. **Resource Tagging**: Tag all resources with `Environment=sandbox`, `ManagedBy=terraform`
4. **Workspace Locking**: Lock workspace during critical operations
5. **Sensitive Variables**: Mark credentials/secrets as sensitive

**Cost Management**:
1. **Resource Tagging**: Enable cost allocation tags
2. **Auto-destroy**: Consider TTL or scheduled destroy for sandbox
3. **Resource Limits**: Set AWS resource quotas for sandbox account
4. **Health Checks**: Enable drift detection to catch manual changes

**Collaboration**:
1. **Team Access**: Grant appropriate permissions (read/plan/write/admin)
2. **Run Comments**: Document rationale in run comments
3. **VCS Integration**: Optional for sandbox (CLI-driven workflow recommended initially)
4. **State Sharing**: Document cross-workspace dependencies

**Development Workflow**:
1. Develop locally with `terraform plan`
2. Push to HCP Terraform for review: `terraform apply`
3. Team reviews plan in UI
4. Approve and apply remotely
5. Validate infrastructure
6. Promote successful patterns to higher environments

**Variable Management**:
1. Use variable sets for shared configuration (region, common tags)
2. Use workspace-specific variables for unique values (instance counts, sizes)
3. Never commit `.tfvars` files with sensitive data
4. Use `.terraformignore` to exclude files from upload (credentials, local state)

### Wiring Considerations

**Module Source Configuration**:
```hcl
# Private registry module
module "vpc" {
  source  = "app.terraform.io/hashi-demos-apj/vpc/aws"
  version = "2.1.0"
  # ... inputs
}
```

**Cross-Workspace State Access**:
- Requires `data "terraform_remote_state"` blocks
- Authentication token must have read access to source workspaces
- Outputs must be defined in source workspace

**No Additional Configuration Required**:
- State backend automatically configured by cloud block
- Locking handled automatically
- No S3/DynamoDB backend resources needed

### Rationale

**Cloud Block vs Backend Block**:
- `cloud` block is modern replacement for `backend "remote"`
- Supports workspace selection by name or tags
- Integrates with project-based organization
- Mutually exclusive with backend blocks

**Remote Execution for Sandbox**:
- Provides consistent environment across team
- Audit trail for troubleshooting
- Enables future policy enforcement
- No local Terraform version mismatches

**Dynamic Credentials via OIDC**:
- Eliminates credential rotation burden
- Temporary credentials per run (enhanced security)
- Role ARN scoped to organization/project/workspace
- Industry best practice per HashiCorp recommendations

**Project-Scoped Variable Sets**:
- Reduces duplication across sandbox workspaces
- Centralized regional configuration
- Simplified credential management
- Inherited by all workspaces in sandbox project

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| Backend "remote" block | Deprecated in favor of cloud block |
| Static AWS credentials | Security risk; requires rotation; dynamic credentials preferred |
| Local execution mode | No audit trail; inconsistent environments; variables not evaluated |
| Workspace-specific variables for region | Duplication across workspaces; variable sets more maintainable |
| Manual state management (S3/DynamoDB) | HCP Terraform handles automatically; adds unnecessary complexity |
| VCS-driven workflow for sandbox | CLI-driven workflow more flexible for rapid iteration in sandbox |

### Sources

- [HCP Terraform Workspaces](https://developer.hashicorp.com/terraform/cloud-docs/workspaces)
- [Dynamic Provider Credentials - AWS](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- [Workspace Variables](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/variables)
- [Terraform Cloud Block Configuration](https://developer.hashicorp.com/terraform/language/settings/terraform-cloud)
- [Workspace Settings](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings)
- [Terraform State in HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/state)
- [Projects](https://developer.hashicorp.com/terraform/cloud-docs/projects)
- [CLI Cloud Settings](https://developer.hashicorp.com/terraform/cli/cloud/settings)
