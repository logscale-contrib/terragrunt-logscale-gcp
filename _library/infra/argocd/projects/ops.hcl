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


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../gke/"

}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../helm/"
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
  name        = "ops"
  namespace   = "argocd"
  description = "Used for cluster ops resources"
  repository  = "https://argoproj.github.io/argo-helm"

  destinations = [
    {
      server    = "*"
      name      = "in-cluster"
      namespace = "*"
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
      "group" : "*"
      "kind" : "*"
    }

  ]
  "sourceRepos" = [
    "*",
  ]
}