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
  source = "tfr:///terraform-google-modules/kubernetes-engine/google?version=25.0.0"
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

}
dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../network/"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # version = "25.0.0"
  release_channel = "RAPID"

  project_id             = local.project_id
  name                   = "${local.name}-${local.env}-${local.codename}"
  regional               = true
  region                 = local.gcp_vars.locals.region
  network                = "${local.name}-${local.env}-${local.codename}"
  subnetwork             = "k8s"
  ip_range_pods          = "pods"
  ip_range_services      = "svc"
  create_service_account = true
  # service_account             = module.service_accounts.email
  enable_cost_allocation      = true
  enable_binary_authorization = false
  skip_provisioners           = false
  node_metadata               = "GKE_METADATA"
  # cluster_autoscaling = {
  #   "auto_repair" : true,
  #   "auto_upgrade" : true,
  #   "autoscaling_profile" : "BALANCED",
  #   "enabled" : false,
  #   "gpu_resources" : [],
  #   "max_cpu_cores" : 64,
  #   "max_memory_gb" : 400,
  #   "min_cpu_cores" : 2,
  #   "min_memory_gb" : 2
  # }

  node_pools = [
    {
      name         = "general"
      machine_type = "n2-standard-2"
      min_count    = 0
      max_count    = 1
      # service_account = format("%s@%s.iam.gserviceaccount.com", local.cluster_sa_name, var.project_id)
      auto_upgrade = true
      auto_repair  = true
      autoscaling  = true
    },
    {
      name         = "compute"
      machine_type = "c2-standard-8"
      min_count    = 1
      max_count    = 3
      # local_ssd_count    = 0
      # disk_size_gb       = 30
      # disk_type          = "pd-standard"
      # accelerator_count  = 1
      # accelerator_type   = "nvidia-tesla-a100"
      # gpu_partition_size = "1g.5gb"
      auto_upgrade = true
      auto_repair  = true
      autoscaling  = true
      # service_account = module.service_accounts.email
    }
    # {
    #   name               = "pool-03"
    #   machine_type       = "n1-standard-2"
    #   node_locations     = "${var.region}-b,${var.region}-c"
    #   autoscaling        = false
    #   node_count         = 2
    #   disk_type          = "pd-standard"
    #   auto_upgrade       = true
    #   service_account    = var.compute_engine_service_account
    #   pod_range          = "test"
    #   sandbox_enabled    = true
    #   cpu_manager_policy = "static"
    #   cpu_cfs_quota      = true
    # },
  ]

  # node_pools_metadata = {
  #   pool-01 = {
  #     shutdown-script = "kubectl --kubeconfig=/var/lib/kubelet/kubeconfig drain --force=true --ignore-daemonsets=true --delete-local-data \"$HOSTNAME\""
  #   }
  # }

  node_pools_labels = {
    all = {}
    general = {
      workloadClass = "general"
    }
    compute = {
      workloadClass = "compute"
    }
  }

  # node_pools_taints = {
  #   all = [
  #     {
  #       key    = "all-pools-example"
  #       value  = true
  #       effect = "PREFER_NO_SCHEDULE"
  #     },
  #   ]
  #   pool-01 = [
  #     {
  #       key    = "pool-01-example"
  #       value  = true
  #       effect = "PREFER_NO_SCHEDULE"
  #     },
  #   ]
  # }

  # node_pools_tags = {
  #   all = [
  #     "all-node-example",
  #   ]
  #   pool-01 = [
  #     "pool-01-example",
  #   ]
  # }

  # node_pools_linux_node_configs_sysctls = {
  #   all = {
  #     "net.core.netdev_max_backlog" = "10000"
  #   }
  #   pool-01 = {
  #     "net.core.rmem_max" = "10000"
  #   }
  #   pool-03 = {
  #     "net.core.netdev_max_backlog" = "20000"
  #   }
  # }  
} 