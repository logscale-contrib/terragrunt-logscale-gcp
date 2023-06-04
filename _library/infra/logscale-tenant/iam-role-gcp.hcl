# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration for mysql. The common variables for each environment to
# deploy mysql are defined here. This configuration will be merged into the environment configuration
# via an include block.
# ---------------------------------------------------------------------------------------------------------------------

# Terragrunt will copy the Terraform configurations specified by the source parameter, along with any files in the
# working directory, into a temporary folder, and execute your Terraform commands in that folder. If any environment
# needs to deploy a different module version, it should redefine this block with a different ref to override the
# deployed version.

terraform {
  source = "tfr:///terraform-google-modules/iam/google//modules/custom_role_iam?version=7.6.0"
}


# ---------------------------------------------------------------------------------------------------------------------
# Locals are named constants that are reusable within the configuration.
# ---------------------------------------------------------------------------------------------------------------------
locals {

  gcp_vars   = read_terragrunt_config(find_in_parent_folders("gcp.hcl"))
  project_id = local.gcp_vars.locals.project_id
  region     = local.gcp_vars.locals.region

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename

}
dependency "sa1" {
  config_path = "${get_terragrunt_dir()}/../sa/sa-1/"
}
dependency "sa2" {
  config_path = "${get_terragrunt_dir()}/../sa/sa-2/"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  target_level = "project"
  target_id    = local.project_id
  role_id      = "${local.name}_${local.codename}_signblob"
  title        = "Logscale Export function support"
  description  = "Grants access to signblobs for export"
  #   base_roles           = ["roles/iam.serviceAccountAdmin"]
  permissions = ["iam.serviceAccounts.signBlob"]
  #   excluded_permissions = ["iam.serviceAccounts.setIamPolicy"]
  members = [
    "serviceAccount:${dependency.sa1.outputs.gcp_service_account_email}",
    "serviceAccount:${dependency.sa2.outputs.gcp_service_account_email}"
  ]

} 