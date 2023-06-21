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
  source = "git::https://github.com/logscale-contrib/terraform-argocd-applicationset.git?ref=v1.1.1"
}



locals {
  # Expose the base source URL so different versions of the module can be deployed in different environments. This will
  # be used to construct the terraform block in the child terragrunt configurations.

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

  destination_name = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? "in-cluster" : "${local.name}-${local.env}-${local.codename}"

  argocd        = read_terragrunt_config(find_in_parent_folders("argocd.hcl"))
  isArgoCluster = local.argocd.locals.isArgoCluster


}



dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../ops/gke/"
}
dependency "k8sEdge" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../../../ops/apps/argocd/projects/common/",
    "${get_terragrunt_dir()}/../../external-secrets/helm/",
  ]
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

  name       = "logscale-priorityclass"
  repository = "https://bedag.github.io/helm-charts/"

  release          = "pc"
  chart            = "raw"
  chart_version    = "2.0.0"
  namespace        = "kube-system"
  create_namespace = false
  project          = "common"
  skipCrds         = false

  values = yamldecode(<<EOF
resources:
  - apiVersion: scheduling.k8s.io/v1
    kind: PriorityClass
    metadata:
      name: logscale-core
    value: 100000000
    globalDefault: false
    description: "This priority class should only be used for critical priority common pods."

  - apiVersion: scheduling.k8s.io/v1
    kind: PriorityClass
    metadata:
      name: logscale-ui
    value: 90000000
    globalDefault: false
    description: "This priority class should only be used for high priority common pods."

  - apiVersion: scheduling.k8s.io/v1
    kind: PriorityClass
    metadata:
      name: logscale-inputs
    value: 80000000
    globalDefault: false
    description: "This priority class should only be used for high priority common pods."
  - apiVersion: scheduling.k8s.io/v1
    kind: PriorityClass
    metadata:
      name: utility
    value: 10000000
    globalDefault: true
    description: "This priority class should only be used for high priority common pods."

EOF
  )

  ignoreDifferences = [
  ]
}
