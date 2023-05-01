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
  source = "${local.source_module.base_url}${local.source_module.version}"
}

# ---------------------------------------------------------------------------------------------------------------------
# Locals are named constants that are reusable within the configuration.
# ---------------------------------------------------------------------------------------------------------------------
locals {
  module_vars   = read_terragrunt_config(find_in_parent_folders("modules.hcl"))
  source_module = local.module_vars.locals.helm_release

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

  host_name = "grafana"


}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../k8s/"
}
dependencies {
  paths = [
    "${get_terragrunt_dir()}/../ns/",
    "${get_terragrunt_dir()}/../../../gke-addons/"
  ]
}
generate "provider" {
  path      = "provider_gke.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

provider "helm" {
  kubernetes {
    host                   = "${dependency.k8s.outputs.kubernetes_endpoint}"
    token = "${dependency.k8s.outputs.client_token}"
    cluster_ca_certificate = base64decode("${dependency.k8s.outputs.ca_certificate}")
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


  repository = "https://prometheus-community.github.io/helm-charts"
  namespace  = "monitoring"
  app = {
    name             = "ops"
    chart            = "kube-prometheus-stack"
    version          = "45.8.*"
    create_namespace = false
    deploy           = 1
  }
  values = [yamlencode({
    prometheusOperator = {
      admissionWebhooks = {
        certManager = {
          enabled = true
        }
      }
    }
    alertmanagerSpec = {
      storage = {
        storageClassName = "standard-rwo"
        accessModes      = ["ReadWriteOnce"]
        resources = {
          requests = {
            storage = "50Gi"
          }
        }
      }
    }
    prometheusSpec = {
      storage = {
        storageClassName = "standard-rwo"
        accessModes      = ["ReadWriteOnce"]
        resources = {
          requests = {
            storage = "50Gi"
          }
        }
      }
      additionalServiceMonitors = [
        {
          name     = "linkerd-federate"
          jobLabel = "app"
          #targetLabels = 
          selector = {
            matchLabels = {
              component = "prometheus"
            }
          }
          namespaceSelector = {
            matchNames = [
              "linkerd-viz"
            ]
          }
          endpoints = [
            {
              interval      = "30s"
              scrapeTimeout = "30s"
              params = {
                "match[]" = [
                  "{job=\"linkerd-proxy\"}",
                  "{job=\"linkerd-controller\"}"
                ]
              }
              path        = "/federate"
              port        = "admin-http"
              honorLabels = true
              relabelings : [
                {
                  action = "keep"
                  regex  = "^prometheus$"
                  sourceLabels = [
                    "__meta_kubernetes_pod_container_name"
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    thanosRulerSpec = {
      storage = {
        storageClassName = "standard-rwo"
        accessModes      = ["ReadWriteOnce"]
        resources = {
          requests = {
            storage = "50Gi"
          }
        }
      }
    }
    "prometheus-node-exporter" = {
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "eks.amazonaws.com/compute-type"
                    operator = "NotIn"
                    values   = ["fargate"]
                  },
                  {
                    key      = "kubernetes.io/os"
                    operator = "In"
                    values   = ["linux"]
                  }
                ]
              }
            ]
          }
        }
      }
    }
  })]
}
