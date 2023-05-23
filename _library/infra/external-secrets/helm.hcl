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
  # Expose the base source URL so different versions of the module can be deployed in different environments. This will
  # be used to construct the terraform block in the child terragrunt configurations.

  gcp_vars   = read_terragrunt_config(find_in_parent_folders("gcp.hcl"))
  project_id = local.gcp_vars.locals.project_id
  region     = local.gcp_vars.locals.region

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename

  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  destination_name = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? "in-cluster" : "${local.name}-${local.env}-${local.codename}"

}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../logscale-ops/gke/"

}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../common/project/",
    "${get_terragrunt_dir()}/../sa/"
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
  uniqueName = "${local.name}-${local.codename}"

  destination_name = local.destination_name

  repository = "https://charts.external-secrets.io"

  release          = local.codename
  chart            = "external-secrets"
  chart_version    = "0.8.1"
  namespace        = "external-secrets"
  create_namespace = false
  project          = "${local.name}-${local.env}-${local.codename}-common"


  values = yamldecode(<<EOF
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
resources:
  requests: 
    cpu: 50m
    memory: 50Mi
  # limits:
  #   cpu: 1
  #   memory: 64Mi
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
          - key: "kubernetes.io/os"
            operator: "In"
            values: ["linux"]   
          - key: iam.gke.io/gke-metadata-server-enabled
            operator: In
            values:
            - "true"

replicaCount: 1
leaderElect: true
serviceAccount:
  create: false
  automount: true
  name: external-secrets-${local.name}-${local.codename}
certController:
  resources:
    requests: 
      cpu: 50m
      memory: 96Mi
    # limits:
    #   cpu: 1
    #   memory: 128Mi
webhook:
  resources:
    requests: 
      cpu: 100m
      memory: 50Mi
    # limits:
    #   cpu: 1
    #   memory: 100Mi
EOF
  )

  ignoreDifferences = [
  ]
}
