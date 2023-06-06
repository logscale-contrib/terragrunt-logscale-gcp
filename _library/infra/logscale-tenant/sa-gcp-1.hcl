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
  source = "tfr:///terraform-google-modules/kubernetes-engine/google//modules/workload-identity?version=26.0.0"
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
  cluster_id   = local.infra_vars.locals.one
  

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename


}
dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../infra/${local.infra_geo}/${local.cluster_id}/gke/"
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

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  gcp_sa_name = join("-", compact([local.name, local.codename, dependency.k8s.outputs.name]))

  name                            = "logscale"
  namespace                       = join("-", compact(["logscale", local.name, local.codename]))
  project_id                      = local.project_id
  automount_service_account_token = true

  annotate_k8s_sa     = false
  use_existing_k8s_sa = true
} 