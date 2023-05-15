# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  gcp_vars   = read_terragrunt_config(find_in_parent_folders("gcp.hcl"))
  project_id = local.gcp_vars.locals.project_id
  region     = local.gcp_vars.locals.region

  # # Automatically load environment-level variables
  # environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # # Extract out common variables for reuse
  # env = local.environment_vars.locals.environment

  # # Extract the variables we need for easy access
  # account_name = local.account_vars.locals.account_name
  # project_id   = local.account_vars.locals.aws_account_id
  # region   = local.region_vars.locals.aws_region

  # tag_vars = read_terragrunt_config(find_in_parent_folders("tags.hcl"))
  # tags = jsonencode(merge(
  #   local.tag_vars.locals.tags,
  #   {
  #     Environment   = local.env
  #     Owner         = get_aws_caller_identity_user_id()
  #     GitRepository = run_cmd("sh", "-c", "git config --get remote.origin.url")
  #   },
  # ))
}



generate "provider_gcp" {
  path      = "provider_gcp.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
provider "google" {
  project     = "${local.project_id}"
  region = "${local.region}"
}
provider "google-beta" {
  project     = "${local.project_id}"
  region = "${local.region}"
}  
  EOF
}

remote_state {
  backend = "gcs"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    project = local.project_id
    bucket  = "logsrlife-terragrunt"
    prefix  = "logscale/${path_relative_to_include()}"
  }
}

terraform {
  extra_arguments "init_args" {
    commands = [
      "init"
    ]

    arguments = [
      "-upgrade",
    ]
  }
}


# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
# inputs = merge(
#   local.account_vars.locals,
#   local.region_vars.locals,
#   local.environment_vars.locals,
# )