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
dependency "registry" {
  config_path = "${get_terragrunt_dir()}/../registry/"
}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../../../ops/apps/argocd/projects/common/",
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
  destination_name = local.argocd.locals.isArgoCluster ? "in-cluster" : dependency.k8sEdge.outputs.name


  repository = "https://estahn.github.io/charts/"

  release          = dependency.k8sEdge.outputs.name
  chart            = "k8s-image-swapper"
  chart_version    = "1.6.1"
  namespace        = "k8s-image-swapper"
  create_namespace = true
  project          = "common"


  values = yamldecode(<<EOF
fullnameOverride: "k8s-image-swapper"
image:
  tag: 1.5.1
serviceAccount:
  create: true
  name: k8s-image-swapper
  annotations:
    "iam.gke.io/gcp-service-account": ${dependency.sa.outputs.gcp_service_account_email}
config:
  dryRun: false
  logLevel: debug
  logFormat: json

  imageCopyPolicy: immediate
  imageSwapPolicy: always
  imageCopyDeadline: 30s
  source:
    # Filters provide control over what pods will be processed.
    # By default all pods will be processed. If a condition matches, the pod will NOT be processed.
    # For query language details see https://jmespath.org/
    filters:
      - jmespath: "obj.metadata.namespace == 'kube-system'"
      - jmespath: "obj.metadata.namespace == 'k8s-image-swapper'"
  target:
    type: gcp
    aws:
      disable: true
    gcp:
      location: ${dependency.k8sEdge.outputs.location}
      projectId: ${local.project_id}
      repositoryId: ${dependency.registry.outputs.repository_id}
patch:
  enabled: false
certmanager:
  enabled: true
resources:
  requests: 
    cpu: 50m
    memory: 64Mi
  # limits:
  #   cpu: 1
  #   memory: 1Gi  
EOF
  )

  ignoreDifferences = [
  ]
}
