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


  argocd        = read_terragrunt_config(find_in_parent_folders("argocd.hcl"))
  isArgoCluster = local.argocd.locals.isArgoCluster

}

dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../ops/gke/"
}
dependency "k8sEdge" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}
dependency "sa" {
  config_path = "${get_terragrunt_dir()}/../sa/"
}
dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../../../ops/apps/argocd/projects/common/"
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
  destination_name = local.argocd.locals.isArgoCluster ? "in-cluster" : dependency.k8sEdge.outputs.name

  repository = "https://charts.external-secrets.io"

  release          = dependency.k8sEdge.outputs.name
  chart            = "external-secrets"
  chart_version    = "0.8.3"
  namespace        = "external-secrets"
  create_namespace = true
  project          = "common"


  values = yamldecode(<<EOF
fullnameOverride: "external-secrets"
replicaCount: 2
leaderElect: true
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
resources:
  requests: 
    cpu: 10m
    memory: 40Mi
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
  create: true
  automount: true
  name: external-secrets
  annotations:
    "iam.gke.io/gcp-service-account": ${dependency.sa.outputs.gcp_service_account_email}
  
certController:
  resources:
    requests: 
      cpu: 10m
      memory: 64Mi
    # limits:
    #   cpu: 1
    #   memory: 128Mi
webhook:
  resources:
    requests: 
      cpu: 10m
      memory: 24Mi
    # limits:
    #   cpu: 1
    #   memory: 100Mi
EOF
  )

  ignoreDifferences = [
  ]
}
