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
  source = "git::https://github.com/logscale-contrib/terraform-kubernetes-argocd-project.git"
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

  destination_name = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? "in-cluster" : "${local.name}-${local.env}-${local.codename}"

}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../ops/gke/"
}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../argocd/helm/",
    "${get_terragrunt_dir()}/../../../gke/"
  ]
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
  name        = "${local.name}-${local.env}-${local.codename}-logscale"
  namespace   = "argocd"
  description = "Used for cluster wide resources"
  repository  = "https://argoproj.github.io/argo-helm"

  destinations = [
    {
      name      = local.destination_name
      namespace = "*"
      server    = "*"
    }
  ]
  namespaceResourceWhitelist = [
    {
      "group" : "*"
      "kind" : "*"
    }
  ]
  cluster_resource_whitelist = [
    {
      "group" : "rbac.authorization.k8s.io"
      "kind" : "ClusterRole"
    },
    {
      "group" : "rbac.authorization.k8s.io"
      "kind" : "ClusterRoleBinding"
    }
  ]
  "sourceRepos" = [
    "*",
  ]
}