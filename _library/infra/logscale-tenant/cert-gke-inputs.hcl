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
  source = "git::https://github.com/logscale-contrib/tf-self-managed-logscale-k8s-helm.git?ref=v2.2.0"
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

  active_cluster = local.infra_vars.locals.active_cluster
  active_bucket  = local.infra_vars.locals.active_bucket

  destination_name = join("-", compact([local.infra_codename, local.infra_env, local.infra_geo, local.active_cluster]))

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename


  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

}

dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../infra/${local.infra_geo}/ops/gke/"
}


generate "provider_k8s" {
  path      = "provider_k8s.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "kubernetes" {
  
  host                   = "${dependency.k8s.outputs.exec_host}"    
  cluster_ca_certificate = base64decode("${dependency.k8s.outputs.ca_certificate}")
  exec {
    api_version = "${dependency.k8s.outputs.exec_api}"
    command     = "${dependency.k8s.outputs.exec_command}"
    args        = ${jsonencode(dependency.k8s.outputs.exec_args)}
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
  destination_name = local.destination_name

  repository = "https://logscale-contrib.github.io/helm-google-gke-managed-cert/"

  release          = join("-", compact(["logscale", local.name, local.codename, "cert-inputs"]))
  chart            = "google-gke-managed-cert"
  chart_version    = "1.0.3"
  namespace        = join("-", compact(["logscale", local.name, local.codename]))
  create_namespace = true
  project          = "common"

  values = yamldecode(<<EOF
fullnameOverride: cert-inputs
domains: ["${join("-", compact(["logscale", local.name, local.codename, "inputs"]))}.${local.domain_name}"]
EOF
  )
}
