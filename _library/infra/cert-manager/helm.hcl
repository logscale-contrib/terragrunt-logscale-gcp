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

  name = "cert-manager"

  repository = "https://charts.jetstack.io"

  release          = "ops"
  chart            = "cert-manager"
  chart_version    = "1.11.2"
  namespace        = "cert-manager"
  create_namespace = true
  project          = "common"
  skipCrds         = false


  values = yamldecode(<<EOF
fullnameOverride: cert-manager

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
resources:
  requests:
    memory: "48Mi"
    cpu: "10m"
  # limits:
  #   memory: "256Mi"
  #   cpu: 1
installCRDs: true

replicaCount: 2
serviceAccount:
  create: true

admissionWebhooks:
  certManager:
    enabled: true

prometheus:
  enabled: true
  servicemonitor:
    enabled: true

cainjector:
  resources:
    requests:
      memory: "48Mi"
      cpu: "20m"
    # limits:
    #   memory: "384Mi"
    #   cpu: 1
  replicaCount: 2

webhook:
  resources:
    requests:
      memory: "24Mi"
      cpu: "50m"
    # limits:
    #   memory: "128Mi"
    #   cpu: 1
  replicaCount: 2
  securePort: 8443

EOF
  )

  ignoreDifferences = [
  ]
}
