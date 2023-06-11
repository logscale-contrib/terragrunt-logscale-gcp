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
  source = "git::https://github.com/logscale-contrib/terraform-azuread-oidc-app.git?ref=v2.0.2"
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
  env       = local.environment_vars.locals.environment
  codename  = local.environment_vars.locals.codename
  name_vars = read_terragrunt_config(find_in_parent_folders("name.hcl"))
  name      = local.name_vars.locals.name


  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  fqdn = format("%s.%s", join("-", compact(["logscale", local.codename, local.name])), local.domain_name)
}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}
dependency "ns" {
  config_path = "${get_terragrunt_dir()}/../ns/"
}
generate "provider_k8s" {
  path      = "provider_k8s.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "kubernetes" {
  
    host                   = "https://${dependency.k8s.outputs.endpoint}"    
    cluster_ca_certificate = base64decode("${dependency.k8s.outputs.ca_certificate}")
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = []
      command     = "gke-gcloud-auth-plugin"
  }
}
EOF
}
# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {

  name = local.fqdn
  identifier_uris = [
    "https://${local.fqdn}"
  ]

  web = [{
    homepage_url = "https://${local.fqdn}"
    logout_url   = "https://${local.fqdn}/logout"
    redirect_uris = [
      "https://${local.fqdn}/auth/oidc"
    ]
  }]

  # secret_name      = "azuread-oidc"
  # secret_namespace = dependency.ns.outputs.name
  # secret_key       = "oidc.azure.clientSecret"


  assigned_groups = [
    {
      #display_name = "consultant",
      group_id = "cd688a6d-cfd7-411e-9e05-18e792f73960"
    },
    {
      #display_name = "tech-lead",
      group_id = "d3a25eb5-6990-4eb8-9118-f27dbb6da9ac"
    }
  ]
}