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


}

dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"

}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../argocd/projects/common/"
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
  name = "openebs-withlvm-init"

  # destination_name = "*"

  repository = "https://logscale-contrib.github.io/openebs-withlvm-init"

  release          = "ops"
  chart            = "openebs-withlvm-init"
  chart_version    = "2.4.6"
  namespace        = "kube-system"
  create_namespace = false
  project          = "common"
  skipCrds         = false


  values = yamldecode(<<EOF
fullnameOverride: lvm-init
config:
    platform: "gcp"
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: storageClass
              operator: In
              values:
                - nvme
            - key: kubernetes.io/os
              operator: In
              values:
                - linux
EOF
  )

  ignoreDifferences = [
  ]
}
