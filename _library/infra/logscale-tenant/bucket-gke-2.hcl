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
  source = "tfr:///terraform-google-modules/cloud-storage/google//modules/simple_bucket?version=4.0.0"
}


# ---------------------------------------------------------------------------------------------------------------------
# Locals are named constants that are reusable within the configuration.
# ---------------------------------------------------------------------------------------------------------------------
locals {

  gcp_vars   = read_terragrunt_config(find_in_parent_folders("gcp.hcl"))
  project_id = local.gcp_vars.locals.project_id
  region     = local.gcp_vars.locals.region

  # Automatically load environment-level variables
  infra_vars     = read_terragrunt_config(find_in_parent_folders("infra.hcl"))
  infra_env      = local.infra_vars.locals.environment
  infra_codename = local.infra_vars.locals.codename
  infra_geo      = local.infra_vars.locals.geo
  cluster_id   = local.infra_vars.locals.two
  
  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename

  bucket_vars  = read_terragrunt_config("bucket.hcl")
  suffix       = local.bucket_vars.locals.suffix

}
dependency "sa1" {
  config_path = "${get_terragrunt_dir()}/../../sa/sa-1/"
}
dependency "sa2" {
  config_path = "${get_terragrunt_dir()}/../../sa/sa-2/"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  name       = join("-", compact(["logscale", local.name, local.codename, local.suffix]))
  project_id = local.project_id
  location   = local.infra_geo

  custom_placement_config = {
    data_locations : ["US-EAST1", "US-WEST1"]
  }

  versioning = true
  lifecycle_rules = [
    {
      "action" : { "type" : "Delete" },
      "condition" : {
        "daysSinceNoncurrentTime" : 2
      }
    }
  ]
  iam_members = [
    {
      role   = "roles/storage.objectAdmin"
      member = "serviceAccount:${dependency.sa1.outputs.gcp_service_account_email}"
    },
    {
      role   = "roles/storage.objectAdmin"
      member = "serviceAccount:${dependency.sa2.outputs.gcp_service_account_email}"
    }
  ]

}