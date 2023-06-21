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

  # Automatically load environment-level variables
  infra_vars           = read_terragrunt_config(find_in_parent_folders("infra.hcl"))
  infra_env            = local.infra_vars.locals.environment
  infra_codename       = local.infra_vars.locals.codename
  infra_geo            = local.infra_vars.locals.geo
  active_cluster       = local.infra_vars.locals.active_cluster
  active_bucket        = local.infra_vars.locals.active_bucket
  recover_mode         = local.infra_vars.locals.recover_mode
  recoverFromBucketID  = local.infra_vars.locals.recoverFromBucketID
  recoverFromReplaceID = local.infra_vars.locals.recoverFromReplaceID
  destination_name     = join("-", compact([local.infra_codename, local.infra_env, local.infra_geo, local.active_cluster]))

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename


  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  humio                    = read_terragrunt_config(find_in_parent_folders("humio.hcl"))
  humio_rootUser           = local.humio.locals.humio_rootUser
  humio_license            = local.humio.locals.humio_license
  humio_sso_idpCertificate = local.humio.locals.humio_sso_idpCertificate
  humio_sso_signOnUrl      = local.humio.locals.humio_sso_signOnUrl
  humio_sso_entityID       = local.humio.locals.humio_sso_entityID

  bucket_name                = join("-", compact(["logscale", local.name, local.codename, local.active_bucket]))
  recoverFromBucketID_value  = join("-", compact(["logscale", local.name, local.codename, local.recoverFromBucketID]))
  recoverFromReplaceID_value = "${join("-", compact(["logscale", local.name, local.codename, local.recoverFromReplaceID]))}/${join("-", compact(["logscale", local.name, local.codename, local.recoverFromBucketID]))}"
}
dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../infra/${local.infra_geo}/ops/gke/"
}

dependency "sso" {
  config_path = "${get_terragrunt_dir()}/../../sso/"
}
dependency "sa" {
  config_path = "${get_terragrunt_dir()}/../../sa/sa-${local.active_cluster}/"
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
  uniqueName = "${local.name}-${local.codename}"

  destination_name = local.destination_name

  repository = "https://logscale-contrib.github.io/helm-logscale"

  release          = join("-", compact(["logscale", local.name, local.codename]))
  chart            = "logscale"
  chart_version    = "v7.0.0-next.103"
  namespace        = join("-", compact(["logscale", local.name, local.codename]))
  create_namespace = true
  project          = "common"

  server_side_apply = false

  values = yamldecode(<<EOF
platform: 
  provider: gcp
humio:
  drMode: "${local.recover_mode}"
  # External URI
  fqdn: ${join("-", compact(["logscale", local.name, local.codename]))}.${local.domain_name}
  fqdnInputs: ${join("-", compact(["logscale", local.name, local.codename, "inputs"]))}.${local.domain_name}

  license: ${local.humio_license}
  
  # Signon

  auth:
    rootUser: ${local.humio_rootUser}
    method: oauth
    # saml:
    #   idpCertificate: "${base64encode(local.humio_sso_idpCertificate)}"
    #   signOnUrl: "${local.humio_sso_signOnUrl}"
    #   entityID: "${local.humio_sso_entityID}"
    oauth:
      provider: ${dependency.sso.outputs.issuer}
      client_id: ${dependency.sso.outputs.application_id}
      client_secret_name: sso-secret-azuread-oidc
      client_secret_key: "oidc.azure.clientSecret"
      # groups_claim: "groups"
      scopes: "openid,email,profile"
  extraENV:
    - name: MAX_SERIES_LIMIT
      value: "1000"
    - name: ENABLE_IOC_SERVICE
      value: "false"

  # Object Storage Settings
  buckets:
    type: gcp
    name: ${local.bucket_name}
    recoverFromBucketID: ${local.recoverFromBucketID_value}
    recoverFromReplace: ${local.recoverFromReplaceID_value}
    downloadConcurrency: 20

  #Kafka
  kafka:
    manager: strimzi
    prefixEnable: true
    strimziCluster: "${join("-", compact(["logscale", local.name, local.codename]))}"
    topicPrefix: ops
    topics:
      ingest:
        retention:
          bytes: 110000000000

  #Image is shared by all node pools
  image:
    # tag: 1.89.0--SNAPSHOT--build-423199--SHA-a5fb8c27a9f860a7d591a8dad518db11522cbb68
    # tag: 1.93.0--SNAPSHOT--build-434317--SHA-a30bd49699d235e342f6c44fe2c85ca561a4a3e2
    tag: 1.94.0--SNAPSHOT--build-441325--SHA-7a190e7592574ff11dc7a4698c61741b9f0ceade
  # Primary Node pool used for digest/storage
  nodeCount: 3
  #In general for these node requests and limits should match
  priorityClassName: logscale-core
  resources:
    requests:
      memory: 16Gi
      cpu: 4
    # limits:
    #   memory: 8Gi
    #   cpu: 2

  digestPartitionsCount: 48
  storagePartitionsCount: 48
  targetReplicationFactor: 1

  serviceAccount:
    name: "logscale"
    annotations:
      "iam.gke.io/gcp-service-account": ${dependency.sa.outputs.gcp_service_account_email}      
  tolerations:
    - key: "computeClass"
      operator: "Equal"
      value: "compute"
      effect: "NoSchedule"
    - key: "storageClass"
      operator: "Equal"
      value: "nvme"
      effect: "NoSchedule"      
    - key: "node.kubernetes.io/disk-pressure"
      operator: "Exists"
      tolerationSeconds: 300
      effect: "NoExecute"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "kubernetes.io/arch"
                operator: "In"
                values: ["amd64"]
              - key: "kubernetes.io/os"
                operator: "In"
                values: ["linux"]  
              - key: "computeClass"
                operator: "In"
                values: ["compute"]      
              - key: "storageClass"
                operator: "In"
                values: ["nvme"]      
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - "kafka"
          topologyKey: kubernetes.io/hostname                  
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - "zookeeper"
          topologyKey: kubernetes.io/hostname

  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchExpressions:
          - key: humio.com/node-pool
            operator: In
            values:
              - "logscale"
  dataVolumePersistentVolumeClaimSpecTemplate:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: "200Gi"
    storageClassName: "lvmpv"
  frontEndDataVolumePersistentVolumeClaimSpecTemplate:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: "10Gi"
    storageClassName: "premium-rwo"
  service:
    ui:
      annotations:
        cloud.google.com/neg: '{"ingress": true}' # Creates a NEG after an Ingress is created
    inputs:
      annotations:
        cloud.google.com/neg: '{"ingress": true}' # Creates a NEG after an Ingress is created

  ingress:
    ui:
      enabled: true
      tls: false
      annotations:
        "external-dns.alpha.kubernetes.io/hostname": "${join("-", compact(["logscale", local.name, local.codename]))}.${local.domain_name}"
        networking.gke.io/managed-certificates: cert-ui

    inputs:
      enabled: true
      tls: false
      annotations:
          "external-dns.alpha.kubernetes.io/hostname" : "${join("-", compact(["logscale", local.name, local.codename, "inputs"]))}.${local.domain_name}"
          networking.gke.io/managed-certificates: cert-inputs
  nodepools:
    ingest:
      nodeCount: 3
      priorityClassName: logscale-inputs
      resources:
        # limits:
        #   cpu: "500m"
        #   memory: 3Gi
        requests:
          cpu: "2000m"
          memory: 5Gi
      tolerations:
        - key: "computeClass"
          operator: "Equal"
          value: "compute"
          effect: "NoSchedule"      
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]  
                  - key: "computeClass"
                    operator: "In"
                    values: ["compute"]                            
                  - key: "storageClass"
                    operator: "DoesNotExist"
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]  
                  - key: "computeClass"
                    operator: "In"
                    values: ["compute"]                       
                  - key: "storageClass"
                    operator: "Exists"

        # podAntiAffinity:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchExpressions:
              - key: humio.com/node-pool
                operator: In
                values:
                  - "${join("-", compact(["logscale", local.name, local.codename]))}-ingest-only"       
    ui:
      nodeCount: 3
      priorityClassName: logscale-ui
      resources:
        # limits:
        #   cpu: "1"
        #   memory: 4Gi
        requests:
          cpu: "2000m"
          memory: 5Gi
      tolerations:
        - key: "computeClass"
          operator: "Equal"
          value: "compute"
          effect: "NoSchedule"      
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]  
                  - key: "computeClass"
                    operator: "In"
                    values: ["compute"]                            
                  - key: "storageClass"
                    operator: "DoesNotExist"
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]  
                  - key: "computeClass"
                    operator: "In"
                    values: ["compute"]                       
                  - key: "storageClass"
                    operator: "Exists"
                   
        # podAntiAffinity:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchExpressions:
              - key: humio.com/node-pool
                operator: In
                values:
                  - "${join("-", compact(["logscale", local.name, local.codename]))}-http-only"                     
kafka:
  allowAutoCreate: false
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "kubernetes.io/arch"
                operator: "In"
                values: ["amd64"]
              - key: "kubernetes.io/os"
                operator: "In"
                values: ["linux"]
              - key: "computeClass"
                operator: "In"
                values: ["compute"]
              - key: "storageClass"
                operator: "DoesNotExist"
          - matchExpressions:
              - key: "kubernetes.io/arch"
                operator: "In"
                values: ["amd64"]
              - key: "kubernetes.io/os"
                operator: "In"
                values: ["linux"]
              - key: "computeClass"
                operator: "In"
                values: ["compute"]
                
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - "zookeeper"
          topologyKey: kubernetes.io/hostname
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - "humio"
              - key: humio.com/node-pool
                operator: In
                values:
                  - "logscale"
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
              - "kafka"
  tolerations:
    - key: "computeClass"
      operator: "Equal"
      value: "compute"
      effect: "NoSchedule"      

  # At least 3 replicas are required the number of replicas must be at east 3 and evenly
  # divisible by number of zones
  # The Following Configuration is valid for approximatly 1TB/day
  # ref: https://library.humio.com/humio-server/installation-prep.html#installation-prep-rec
  replicas: 3
  priorityClassName: logscale-core
  resources:    
    requests:
      # Increase the memory as needed to support more than 5/TB day
      memory: 4500Mi
      #Note the following resources are expected to support 1-3 TB/Day however
      # storage is sized for 1TB/day increase the storage to match the expected load
      cpu: 1250m
    limits:
      cpu: 3
      memory: 5Gi
  #(total ingest uncompressed per day / 5 ) * 3 / ReplicaCount
  # ReplicaCount must be odd and greater than 3 should be divisible by AZ
  # Example: 1 TB/Day '1/5*3/3=205' 3 Replcias may not survive a zone failure at peak
  # Example:  1 TB/Day '1/5*3/6=103' 6 ensures at least one node per zone
  # 100 GB should be the smallest disk used for Kafka this may result in some waste
  storage:
    type: persistent-claim
    size: 300Gi
    deleteClaim: true
    #Must be SSD or NVME like storage IOPs is the primary node constraint
    class: premium-rwo
zookeeper:
  replicas: 3
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "kubernetes.io/arch"
                operator: "In"
                values: ["amd64"]
              - key: "kubernetes.io/os"
                operator: "In"
                values: ["linux"]
              - key: "computeClass"
                operator: "In"
                values: ["compute"]      
                      
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - "kafka"
          topologyKey: kubernetes.io/hostname
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - "humio"
              - key: humio.com/node-pool
                operator: In
                values:
                  - "logscale"
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
              - "zookeeper"
  tolerations:
    - key: "computeClass"
      operator: "Equal"
      value: "compute"
      effect: "NoSchedule"     
  priorityClassName: logscale-core       
  resources:
    requests:
      memory: 350Mi
      cpu: "100m"
    # limits:
    #   memory: 284Mi
    #   cpu: "500m"
  storage:
    deleteClaim: true
    type: persistent-claim
    size: 5Gi
    class: premium-rwo

# otel:  
#   components:
#     inject: true
#     app: true
#     cluster: true
#     nodes: true
#     logScaleConfig: true
#     serviceaccount: true
#   resourcedetectors:
#     - env
#     - gcp
EOF
  )

  ignoreDifferences = [
    {
      group = "kafka.strimzi.io"
      kind  = "KafkaRebalance"
      jsonPointers = [
        "/metadata/annotations/strimzi.io/rebalance"
      ]
    }
  ]
}
