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
  source = "git::https://github.com/logscale-contrib/terraform-azuread-oidc-app.git?ref=v1.4.7"
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
dependency "ns" {
  config_path = "${get_terragrunt_dir()}/../ns/"
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

  name = "${local.host_name}.${local.domain_name}"
  identifier_uris = [
    "https://${local.host_name}.${local.domain_name}/auth/callback"
  ]
  required_resource_access = [{
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access = [{
      id   = "df021288-bdef-4463-88db-98f22de89214" # User.Read.All
      type = "Role"
    }]
  }]
  consent_resource_access = [{
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    resource_access = "df021288-bdef-4463-88db-98f22de89214"
  }]

  web = [{
    homepage_url = "https://${local.host_name}.${local.domain_name}"
    logout_url   = "https://${local.host_name}.${local.domain_name}/auth/logout"
    redirect_uris = [
      "https://${local.host_name}.${local.domain_name}/auth/callback"
    ]
  }]

  public_client = [{
    redirect_uris = ["http://localhost:8085/auth/callback"]
  }]

  secret_name      = "azuread-oidc"
  secret_namespace = dependency.ns.outputs.name
  secret_key       = "oidc.azure.clientSecret"
  secret_labels = {
    "app.kubernetes.io/part-of" = "argocd"
  }

  assigned_groups = [
    {
      #display_name = "consultant",
      group_id = "cd688a6d-cfd7-411e-9e05-18e792f73960"
      # app_role_id  = "00000000-0000-0000-0000-000000000000"
    },
    {
      #display_name = "tech-lead",
      group_id = "d3a25eb5-6990-4eb8-9118-f27dbb6da9ac"
      # app_role_id  = "00000000-0000-0000-0000-000000000000"
    }
  ]
}