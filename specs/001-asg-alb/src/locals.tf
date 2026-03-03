locals {
  naming_suffix = random_string.naming_suffix.result
  subnet_ids    = tolist(data.aws_subnets.default.ids)

  # Select first 2 subnets for ASG multi-AZ deployment
  asg_subnet_ids = slice(local.subnet_ids, 0, min(2, length(local.subnet_ids)))
}
