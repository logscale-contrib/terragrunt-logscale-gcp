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
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}
dependency "sso" {
  config_path = "${get_terragrunt_dir()}/../sso-grafana/"
}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../common/project-ops/"
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


  destination_name = "in-cluster"

  repository = "https://prometheus-community.github.io/helm-charts"

  release          = "ops"
  chart            = "kube-prometheus-stack"
  chart_version    = "45.30.0"
  namespace        = "monitoring"
  create_namespace = true
  project          = "ops"

  server_side_apply = false

  values = yamldecode(<<EOF
grafana:
  service:
    annotations:
      cloud.google.com/neg: '{"ingress": true}' # Creates a NEG after an Ingress is created
  ingress:
    enabled: true
    hosts:
      - grafana.${local.domain_name}
    annotations:
      external-dns.alpha.kubernetes.io/hostname: grafana.${local.domain_name}
      networking.gke.io/managed-certificates: grafana-google-gke-managed-cert
  extraSecretMounts:
    - name: azuread-oidc
      secretName: azuread-oidc
      defaultMode: 0440
      mountPath: /etc/secrets/azuread-oidc
      readOnly: true
  grafana.ini:
    server:
      root_url: https://grafana.${local.domain_name}/
    log.console:
      format: json
    auth:
      login_maximum_inactive_lifetime_duration: 14h
      login_maximum_lifetime_duration: 1d
      disable_login_form: true
    auth.basic:
      enabled: false
    auth.azuread:
      name: Azure AD
      enabled: true
      allow_sign_up: true
      auto_login: false
      client_id: ${dependency.sso.outputs.application_id}
      client_secret: $__file{/etc/secrets/azuread-oidc/client_secret}
      scopes: openid email profile offline_access
      auth_url: https://login.microsoftonline.com/${dependency.sso.outputs.directory_tenant_id}/oauth2/v2.0/authorize
      token_url: https://login.microsoftonline.com/${dependency.sso.outputs.directory_tenant_id}/oauth2/v2.0/token
      role_attribute_strict: false
      allow_assign_grafana_admin: true
      skip_org_role_sync: false

prometheusOperator:
  admissionWebhooks:
    certManager:
      enabled: true
alertmanagerSpec:
  storage:
    storageClassName: standard-rwo
    accessModes: ["ReadWriteOnce"]
    requests:
      storage: 50Gi
prometheusSpec:
  storage:
    storageClassName: standard-rwo
    accessModes: ["ReadWriteOnce"]
    requests:
      storage: 50Gi    

EOF
  )

  ignoreDifferences = [
    {
      "group" : "*"
      "kind" : "Certificate"
      "jsonPointers" : ["/status/conditions"]
    }
  ]
}
