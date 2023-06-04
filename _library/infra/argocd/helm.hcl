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
  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  host_name = "argocd"

}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}
dependency "sso" {
  config_path = "${get_terragrunt_dir()}/../sso/"
}
dependencies {
  paths = [
    "${get_terragrunt_dir()}/../ns/",
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
    version = "5.34.6"

    wait   = true
    deploy = 1
  }
  values = [<<EOF
fullnameOverride: argocd
createAggregateRoles: true

argo-cd:
  config:
    application.resourceTrackingMethod: annotation+label
redis-ha:
  enabled: true
  topologySpreadConstraints: 
    enabled: true
  redis:
    resources:
      requests:
        cpu: ".5"
        memory: 96Mi
      # limits:
      #   cpu: "2"
      #   memory: 256Mi
  haproxy:
    resources:
      requests:
        cpu: 50m
        memory: 96Mi
      # limits:
      #   cpu: 500m
      #   memory: 128Mi


controller:
  replicas: 2
  pdb: 
    enabled: true
    minAvailable: 1
    maxUnavailable: 1
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    # limits:
    #   cpu: 2
    #   memory: 1Gi
repoServer:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 3
  pdb: 
    enabled: true
    minAvailable: 1
    maxUnavailable: 1
  resources:
    requests:
      cpu: 10m
      memory: 100Mi
    # limits:
    #   cpu: 2
    #   memory: 384Mi

applicationSet:
  replicas: 2
  pdb: 
    enabled: true
    minAvailable: 1
    maxUnavailable: "1"
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    # limits:
    #   cpu: 250m
    #   memory: 100Mi
server:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 3
  pdb: 
    enabled: true
    minAvailable: 1
    maxUnavailable: "1"
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
      networking.gke.io/managed-certificates: ops-argocd-cert-google-gke-managed-cert
  resources:
    requests:
      cpu: 100m
      memory: 64Mi
    # limits:
    #   cpu: 2
    #   memory: 256Mi
dex:
  enabled: false
  pdb: 
    enabled: true
    minAvailable: 0
    maxUnavailable: "100%"
  resources:
    requests:
      cpu: 10m
      memory: 50Mi
    # limits:
    #   cpu: 250m
    #   memory: 128Mi
notifications:
  pdb: 
    enabled: true
    minAvailable: 0
    maxUnavailable: "100%"
  resources:
    requests:
      cpu: 10m
      memory: 30Mi
    # limits:
    #   cpu: 150m
    #   memory: 96Mi
global:
  logging:
    # -- Set the global logging format. Either: `text` or `json`
    format: json
  topologySpreadConstraints: 
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule    
configs:
  cm:
    admin.enabled: false
    url: "https://${local.host_name}.${local.domain_name}"
    oidc.config: |
      name: SSO
      issuer: ${dependency.sso.outputs.issuer}
      clientID: ${dependency.sso.outputs.application_id}
      clientSecret: $azuread-oidc:oidc.azure.clientSecret
      requestedIDTokenClaims:
        groups:
            essential: true
      requestedScopes:
        - openid
        - profile
        - email    
  rbac:
    policy.default: role:readonly
    policy.csv: |
      g, "consultant", role:admin
      g, "tech-lead", role:admin
    scopes: '[groups, email]'      
notifications:
  argocdUrl: "https://${local.host_name}.${local.domain_name}"


EOF 
  ]
}