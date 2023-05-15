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
  source = "tfr:///terraform-module/release/helm?version=2.8.0"
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


  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  host_name = "argocd"

}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}
dependencies {
  paths = [
    "${get_terragrunt_dir()}/../ns/"
  ]
}
generate "provider_gke" {
  path      = "provider_gke.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

provider "helm" {
  kubernetes {
    host                   = "https://${dependency.k8s.outputs.endpoint}"    
    cluster_ca_certificate = base64decode("${dependency.k8s.outputs.ca_certificate}")
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = []
      command     = "gke-gcloud-auth-plugin"
    }
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
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"

  app = {
    name             = "cw"
    create_namespace = true

    chart   = "argo-cd"
    version = "5.32.1"

    wait   = true
    deploy = 1
  }
  values = [<<EOF
createAggregateRoles: true
argo-cd:
  config:
    application.resourceTrackingMethod: annotation+label
redis-ha:
  enabled: true

controller:
  replicas: 2

repoServer:
  autoscaling:
    enabled: true
    minReplicas: 2

applicationSet:
  replicas: 2

server:
  autoscaling:
    enabled: true
    minReplicas: 2
  extraArgs:
  - --insecure
  service:
    annotations:
      cloud.google.com/neg: '{"ingress": true}' # Creates a NEG after an Ingress is created
  ingress:
    enabled: true
    hosts:
      - ${local.host_name}.${local.domain_name}
    annotations:
      external-dns.alpha.kubernetes.io/hostname: ${local.host_name}.${local.domain_name}
      networking.gke.io/managed-certificates: cert-google-gke-managed-cert
global:
  logging:
    # -- Set the global logging format. Either: `text` or `json`
    format: json
  topologySpreadConstraints: 
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule    
configs:
  url: ${local.host_name}.${local.domain_name}

EOF 
  ]
}