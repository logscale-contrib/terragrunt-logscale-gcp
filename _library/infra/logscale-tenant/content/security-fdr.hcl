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


locals {

  # Automatically load environment-level variables
  infra_vars     = read_terragrunt_config(find_in_parent_folders("infra.hcl"))
  infra_env      = local.infra_vars.locals.environment
  infra_codename = local.infra_vars.locals.codename
  infra_geo      = local.infra_vars.locals.geo
  active_cluster = local.infra_vars.locals.active_cluster

  destination_name = join("-", compact([local.infra_codename, local.infra_env, local.infra_geo, local.active_cluster]))

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename


  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  humio                    = read_terragrunt_config(find_in_parent_folders("humio.hcl"))
  humio_rootUser           = local.humio.locals.humio_rootUser
  humio_license            = local.humio.locals.humio_license
  humio_sso_idpCertificate = local.humio.locals.humio_sso_idpCertificate
  humio_sso_signOnUrl      = local.humio.locals.humio_sso_signOnUrl
  humio_sso_entityID       = local.humio.locals.humio_sso_entityID

  # Automatically load environment-level variables
  content_vars = read_terragrunt_config("content.hcl")
  # Extract out common variables for reuse
  prefix            = local.content_vars.locals.prefix
  suffix            = local.content_vars.locals.suffix
  ingestSizeInGB    = local.content_vars.locals.ingestSizeInGB == "" ? "1073741824" : local.content_vars.locals.ingestSizeInGB
  storageSizeInGB   = local.content_vars.locals.storageSizeInGB == "" ? "1073741824" : local.content_vars.locals.storageSizeInGB
  timeInDays        = local.content_vars.locals.timeInDays == "" ? "999" : local.content_vars.locals.timeInDays
  allowDataDeletion = local.content_vars.locals.allowDataDeletion


}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../../infra/${local.infra_geo}/ops/gke/"
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

  repository = "https://logscale-contrib.github.io/helm-logscale-content"

  release          = join("-", compact(["logscale", local.prefix, local.name, local.codename, "content-falcon-fdr", local.suffix]))
  chart            = "logscale-content"
  chart_version    = "1.3.1"
  namespace        = join("-", compact(["logscale", local.name, local.codename]))
  create_namespace = false
  project          = "common"

  values = yamldecode(<<EOF
fullnameOverride: ${join("-", compact(["logscale", local.name, local.codename]))}
managedClusterName: ${join("-", compact(["logscale", local.name, local.codename]))}
repositoryDefault:
  ingestSizeInGB: "${local.ingestSizeInGB}"
  storageSizeInGB: "${local.storageSizeInGB}"
  timeInDays: "${local.timeInDays}"
  allowDataDeletion: ${local.allowDataDeletion}
eso:
  secretStoreRefs:
    - name: ops
      kind: ClusterSecretStore  
repositories:
  - name: ${join("-", compact([local.prefix, "falcon-fdr", local.suffix]))}
EOF
  )

  ignoreDifferences = [
  ]
}
