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
    version = "5.34.1"

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
  topologySpreadConstraints: 
    enabled: true
  redis:
    resources:
      requests:
        cpu: "1"
        memory: 96Mi
      limits:
        cpu: "2"
        memory: 256Mi
  haproxy:
    resources:
      requests:
        cpu: 50m
        memory: 96Mi
      limits:
        cpu: 500m
        memory: 128Mi


controller:
  replicas: 2
  pdb: 
    enabled: true
    minAvailable: 1
    maxUnavailable: 1
  resources:
    requests:
      cpu: 200m
      memory: 400Mi
    limits:
      cpu: 400m
      memory: 768Mi
repoServer:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 4
  pdb: 
    enabled: true
    minAvailable: 1
    maxUnavailable: "1"
  resources:
    requests:
      cpu: 10m
      memory: 100Mi
    limits:
      cpu: 250m
      memory: 256Mi

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
    limits:
      cpu: 250m
      memory: 100Mi
server:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 4
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
      networking.gke.io/managed-certificates: cert-google-gke-managed-cert
  resources:
    requests:
      cpu: 100m
      memory: 64Mi
    limits:
      cpu: 250m
      memory: 96Mi
dex:
  pdb: 
    enabled: true
    minAvailable: 0
    maxUnavailable: "100%"
  resources:
    requests:
      cpu: 10m
      memory: 50Mi
    limits:
      cpu: 250m
      memory: 128Mi
notifications:
  pdb: 
    enabled: true
    minAvailable: 0
    maxUnavailable: "100%"
  resources:
    requests:
      cpu: 10m
      memory: 30Mi
    limits:
      cpu: 150m
      memory: 96Mi
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
    url: "https://${local.host_name}.${local.domain_name}"
    oidc.config: |
      name: SSO
      issuer: https://login.microsoftonline.com/4d40b7e0-fca8-48d9-8fea-3d117a06b2a7/v2.0
      clientID: d11054a3-14df-4f27-91ff-b71422aa7850
      clientSecret: Wbs8Q~mbV~JDpNPKeKNEnYzy~uHanVHy~qfiicrq
      requestedIDTokenClaims:
        groups:
            essential: true
      requestedScopes:
        - openid
        - profile
        - email
    # dex.config: |
    #   logger:
    #     level: debug
    #     format: json
    #   connectors:
    #   - type: saml
    #     id: saml
    #     name: SSO
    #     config:
    #       entityIssuer: https://${local.host_name}.${local.domain_name}/api/dex/callback
    #       ssoURL: 
    #       caData: |
    #           -----BEGIN CERTIFICATE-----
    #           MIIC8DCCAdigAwIBAgIQedTQhao7Ya1DKGOVfz6+HDANBgkqhkiG9w0BAQsFADA0MTIwMAYDVQQD
    #           EylNaWNyb3NvZnQgQXp1cmUgRmVkZXJhdGVkIFNTTyBDZXJ0aWZpY2F0ZTAeFw0yMzA1MTgxNDI4
    #           MTlaFw0yNjA1MTgxNDI4MThaMDQxMjAwBgNVBAMTKU1pY3Jvc29mdCBBenVyZSBGZWRlcmF0ZWQg
    #           U1NPIENlcnRpZmljYXRlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxMroSfx8Abyk
    #           VKyFvpntSq+MSTcuSOV7n28Sb3Ck38ocX3OF6M2K8K17B4x9RnwoX7VTqarwDPMoTTJ5WpKw5CVA
    #           70mlLdhjlz9p5rXQItZHMgiGzfLoU8hCjvmCfZmFBSMOG88tdfOrqQLgkNif+NonlyUsdBHJ0N3j
    #           XD75RBqDA75HukoBlSaVKc8fiKiltBuZQKi8ykUHhw6nqH737N+u0AoKNIJJEgXbppgWxhD7zEuL
    #           eCHsKsn1hYeqWPZ2K2aDPVvGlDUmMd1rrsCNIQ0wL/rtneugsu0mD6QsNFitHnSJr3fxlXHExJAt
    #           0uviO4K2CJSpiIFTBarALDgYCQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQB+Q40nKrGLKrRTstNY
    #           qRUNRQPDtKjIEPl+zWInhwWzpSA06QyEEAyGkfShGTu9wPiFqb4zibpHugH6GnWMOSMsUcZwKV+3
    #           2L7UhXsX/EWYbUtdh2TitUOEE6uiz2iYDT4VaGKgj9ZXytp8Jc4xuIW8yBRzBasL+oR+Bq8hTGN4
    #           FXoKLGpjJUxbYzcJ1XUpxr5EzCC0wJ4VilQQcvJMWL0LnUMOXECD3AkW2ETGSfWGt6z9r+eyjHyk
    #           RkT1BF/UstVzHbm6UdMdy/0f7BxUp1SLis0ONvqXK98zrjmmwqr6vImE2JVYItkCoWzsq28AUxHf
    #           GeGtJgx4Xe2JdubeCLd0
    #           -----END CERTIFICATE-----
    #       redirectURI: https://login.microsoftonline.com/4d40b7e0-fca8-48d9-8fea-3d117a06b2a7/saml2
    #       usernameAttr: email
    #       emailAttr: email
    #       groupsAttr: Group
  rbac:
    policy.default: role:readonly
    policy.csv: |
      g, "d6984f88-0dcc-4ac6-bdbb-8fd8deb99415", role:admin # consultant
      g, "9e9e711b-9028-472f-a966-7ed7e0b704ae", role:admin # tech-lead
notifications:
  argocdUrl: "https://${local.host_name}.${local.domain_name}"


EOF 
  ]
}