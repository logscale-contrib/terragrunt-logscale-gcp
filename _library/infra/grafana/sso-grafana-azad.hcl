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

  gcp_vars   = read_terragrunt_config(find_in_parent_folders("gcp.hcl"))
  project_id = local.gcp_vars.locals.project_id
  region     = local.gcp_vars.locals.region

  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  host_name = "grafana"

}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
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
    "https://${local.host_name}.${local.domain_name}"
  ]

  app_roles = [
    {
      display_name = "Grafana Org Admin"
      id           = "89A7C9DA-3C3D-4D61-AFB5-825B7F527B14"
      value        = "Admin"
      description  = "Grafana org admin Users"
      enabled      = true
    },
    {
      display_name = "Grafana Viewer"
      id           = "46BA5679-DA99-4345-92AD-19A058F98CEF"
      value        = "User"
      description  = "Grafana read only Users"
      enabled      = true
    },
    {
      display_name = "Grafana Editor"
      id           = "7312F8A6-31D6-46F5-8907-EA6325ABD4D6"
      value        = "Editor"
      description  = "Grafana Editor Users"
      enabled      = true
    },
    {
      display_name = "Grafana Server Admin"
      id           = "A164B082-6C1C-4B05-AE01-294798A29607"
      value        = "GrafanaAdmin"
      description  = "Grafana GrafanaAdmin Users"
      enabled      = true
    }
  ]

  web = [{
    homepage_url = "https://${local.host_name}.${local.domain_name}/"
    logout_url   = "https://${local.host_name}.${local.domain_name}/auth/logout"
    redirect_uris = ["https://${local.host_name}.${local.domain_name}/login/azuread",
    "https://${local.host_name}.${local.domain_name}/"]
  }]

  secret_name      = "azuread-oidc"
  secret_namespace = "monitoring"
  secret_key       = "client_secret"
  # secret_labels = {
  #     "app.kubernetes.io/part-of"= "argocd"
  # }

  assigned_groups = [
    {
      #display_name = "consultant",
      group_id    = "cd688a6d-cfd7-411e-9e05-18e792f73960"
      app_role_id = "89A7C9DA-3C3D-4D61-AFB5-825B7F527B14"
    },
    {
      #display_name = "tech-lead",
      group_id    = "d3a25eb5-6990-4eb8-9118-f27dbb6da9ac"
      app_role_id = "A164B082-6C1C-4B05-AE01-294798A29607"
    }
  ]

}