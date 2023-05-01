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
  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename

  # Expose the base source URL so different versions of the module can be deployed in different environments. This will
  # be used to construct the terraform block in the child terragrunt configurations.
  module_vars   = read_terragrunt_config(find_in_parent_folders("modules.hcl"))
  source_module = local.module_vars.locals.k8s_helm

  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Automatically load region-level variables
  admin = read_terragrunt_config(find_in_parent_folders("admin.hcl"))

  # Extract the variables we need for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region

  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  humio                    = read_terragrunt_config(find_in_parent_folders("humio.hcl"))
  humio_rootUser           = local.humio.locals.humio_rootUser
  humio_license            = local.humio.locals.humio_license
  humio_sso_idpCertificate = local.humio.locals.humio_sso_idpCertificate
  humio_sso_signOnUrl      = local.humio.locals.humio_sso_signOnUrl
  humio_sso_entityID       = local.humio.locals.humio_sso_entityID
}


dependency "eks" {
  config_path = "${get_terragrunt_dir()}/../../../../eks/"
}
dependency "acm_ui" {
  config_path = "${get_terragrunt_dir()}/../../../../acm-ui/"
}
dependency "bucket" {
  config_path = "${get_terragrunt_dir()}/../bucket/"
}
dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../../../eks-addons/",
    "${get_terragrunt_dir()}/../../../argocd/helm/",
    "${get_terragrunt_dir()}/../../ns/",
    "${get_terragrunt_dir()}/../../project/"
  ]
}
generate "provider" {
  path      = "provider_k8s.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

provider "helm" {
  kubernetes {
    host                   = "${dependency.eks.outputs.eks_endpoint}"
    cluster_ca_certificate = base64decode("${dependency.eks.outputs.eks_cluster_certificate_authority_data}")

    exec {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.eks_cluster_name}"]
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
  uniqueName = "${local.name}-${local.codename}"

  repository = "https://logscale-contrib.github.io/helm-logscale"

  release          = local.codename
  chart            = "logscale"
  chart_version    = "v6.0.0"
  namespace        = "${local.name}-${local.codename}"
  create_namespace = false
  project          = "${local.name}-${local.codename}"


  values = yamldecode(<<EOF
platform: aws
humio:
  # External URI
  fqdn: logscale-${local.codename}.${local.domain_name}
  fqdnInputs: "logscale-${local.codename}-inputs.${local.domain_name}"

  license: ${local.humio_license}
  
  # Signon
  rootUser: ${local.humio_rootUser}

  sso:
    idpCertificate: "${base64encode(local.humio_sso_idpCertificate)}"
    signOnUrl: "${local.humio_sso_signOnUrl}"
    entityID: "${local.humio_sso_entityID}"
  extraENV:
    - name: MAX_SERIES_LIMIT
      value: "1000"
    - name: ENABLE_IOC_SERVICE
      value: "false"

  # Object Storage Settings
  s3mode: aws
  buckets:
    region: ${local.aws_region}
    storage: ${dependency.bucket.outputs.s3_bucket_id}

  #Kafka
  kafka:
    manager: strimzi
    prefixEnable: true
    strimziCluster: "${local.codename}-logscale"
    # externalKafkaHostname: "${local.codename}-logscale-kafka-bootstrap:9092"

  #Image is shared by all node pools
  image:
    # tag: 1.75.0--SNAPSHOT--build-353635--SHA-96e5fc2254e11bf9a10b24b749e4e5b197955607
    # tag: 1.76.0--SNAPSHOT--build-359970--SHA-23a8fb2bc34e2dac49fedc09642a1b41013238f6
    # tag: 1.77.0--SNAPSHOT--build-360968--SHA-2b8b9fb62ade3dbac30c4352716632e7fec92cb0
    # tag: 1.78.0--SNAPSHOT--build-371116--SHA-82be774e353aeebd8e5cbfa88aef55cb8f5960a0
    # tag: 1.79.0--SNAPSHOT--build-381031--SHA-3d907a8c1c8e9f1eab28ada26f6cc0f83b6c80d3
    tag: 1.82.0--SNAPSHOT--build-392060--SHA-3d151632092e4c2a554df0d24147b749219def02
  # Primary Node pool used for digest/storage
  nodeCount: 3
  #In general for these node requests and limits should match
  resources:
    requests:
      memory: 8Gi
      cpu: 2
    limits:
      memory: 8Gi
      cpu: 4

  digestPartitionsCount: 24
  storagePartitionsCount: 6
  targetReplicationFactor: 2

  serviceAccount:
    name: "logscale-${local.codename}"
    annotations:
      "eks.amazonaws.com/role-arn": "${dependency.bucket.outputs.iam_role_arn}"
  tolerations:
    - key: "workloadClass"
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
              - key: "workloadClass"
                operator: "In"
                values: ["compute"]      
          - matchExpressions:
              - key: "kubernetes.io/arch"
                operator: "In"
                values: ["amd64"]
              - key: "kubernetes.io/os"
                operator: "In"
                values: ["linux"]
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/instance
                operator: In
                values: ["${local.codename}-logscale"]
              - key: humio.com/node-pool
                operator: In
                values: ["${local.codename}-logscale"]
          topologyKey: "kubernetes.io/hostname"
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchExpressions:
          - key: humio.com/node-pool
            operator: In
            values:
              - "${local.codename}-logscale"          
  dataVolumePersistentVolumeClaimSpecTemplate:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: "100Gi"
    storageClassName: "premium-rwo"

  ingress:
    ui:
      enabled: true
      tls: false
      annotations:
        "kubernetes.io/ingress.class" : "alb"
        "alb.ingress.kubernetes.io/certificate-arn": "${dependency.acm_ui.outputs.acm_certificate_arn}"
        "alb.ingress.kubernetes.io/listen-ports": '[{"HTTP": 80}, {"HTTPS": 443}]'
        "alb.ingress.kubernetes.io/ssl-redirect": "443"
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
        "alb.ingress.kubernetes.io/target-type": "ip"
        "alb.ingress.kubernetes.io/group.name": "logscale-${local.env}"
        alb.ingress.kubernetes.io/load-balancer-attributes: routing.http2.enabled=true                
        "external-dns.alpha.kubernetes.io/hostname": "logscale-ops.${local.domain_name}"

    inputs:
      enabled: true
      tls: false
      annotations:
          "kubernetes.io/ingress.class" : "alb"
          "alb.ingress.kubernetes.io/certificate-arn" : "${dependency.acm_ui.outputs.acm_certificate_arn}"
          "alb.ingress.kubernetes.io/listen-ports"    : "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
          "alb.ingress.kubernetes.io/ssl-redirect"    : "443"
          "alb.ingress.kubernetes.io/scheme"          : "internet-facing"
          "alb.ingress.kubernetes.io/target-type"     : "ip"
          "alb.ingress.kubernetes.io/group.name"      : "logscale-${local.env}"
          alb.ingress.kubernetes.io/load-balancer-attributes: routing.http2.enabled=true                
          "external-dns.alpha.kubernetes.io/hostname" : "logscale-${local.codename}-inputs.${local.domain_name}"
  nodepools:
    ingest:
      nodeCount: 2
      resources:
        limits:
          cpu: "2"
          memory: 6Gi
        requests:
          cpu: "2"
          memory: 4Gi
      tolerations:
        - key: "workloadClass"
          operator: "Equal"
          value: "compute"
          effect: "NoSchedule"      
        - key: "workloadClass"
          operator: "Equal"
          value: "nvme"
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
                  - key: "workloadClass"
                    operator: "In"
                    values: ["general","compute"]               
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]
                  # - key: "kubernetes.azure.com/agentpool"
                  #   operator: "In"
                  #   values: ["compute"]
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/instance
                    operator: In
                    values: ["${local.codename}-logscale"]
                  - key: humio.com/node-pool
                    operator: In
                    values: ["${local.codename}-logscale-ingest-only"]
              topologyKey: "kubernetes.io/hostname"
      topologySpreadConstraints:
            - maxSkew: 1
              topologyKey: topology.kubernetes.io/zone
              whenUnsatisfiable: DoNotSchedule
              labelSelector:
                matchExpressions:
                  - key: humio.com/node-pool
                    operator: In
                    values:
                      - "${local.codename}-logscale-ingest-only"   
    ui:
      nodeCount: 2
      resources:
        limits:
          cpu: "2"
          memory: 6Gi
        requests:
          cpu: "2"
          memory: 4Gi
      tolerations:
        - key: "workloadClass"
          operator: "Equal"
          value: "compute"
          effect: "NoSchedule"      
        - key: "workloadClass"
          operator: "Equal"
          value: "nvme"
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
                  - key: "workloadClass"
                    operator: "In"
                    values: ["general","compute"]               
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]
                  # - key: "kubernetes.azure.com/agentpool"
                  #   operator: "In"
                  #   values: ["compute"]
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/instance
                    operator: In
                    values: ["${local.codename}-logscale"]
                  - key: humio.com/node-pool
                    operator: In
                    values: ["${local.codename}-logscale-http-only"]
              topologyKey: "kubernetes.io/hostname"
      topologySpreadConstraints:
            - maxSkew: 1
              topologyKey: topology.kubernetes.io/zone
              whenUnsatisfiable: DoNotSchedule
              labelSelector:
                matchExpressions:
                  - key: humio.com/node-pool
                    operator: In
                    values:
                      - "${local.codename}-logscale-http-only"                 
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
              - key: "workloadClass"
                operator: "In"
                values: ["compute"]                 
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: strimzi.io/component-type
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
          - key: strimzi.io/name
            operator: In
            values:
              - "${local.codename}-logscale-kafka"
  tolerations:
    - key: "workloadClass"
      operator: "Equal"
      value: "compute"
      effect: "NoSchedule"      

  # At least 3 replicas are required the number of replicas must be at east 3 and evenly
  # divisible by number of zones
  # The Following Configuration is valid for approximatly 1TB/day
  # ref: https://library.humio.com/humio-server/installation-prep.html#installation-prep-rec
  replicas: 3
  resources:
    requests:
      # Increase the memory as needed to support more than 5/TB day
      memory: 4Gi
      #Note the following resources are expected to support 1-3 TB/Day however
      # storage is sized for 1TB/day increase the storage to match the expected load
      cpu: 2
    limits:
      memory: 4Gi
      cpu: 2
  #(total ingest uncompressed per day / 5 ) * 3 / ReplicaCount
  # ReplicaCount must be odd and greater than 3 should be divisible by AZ
  # Example: 1 TB/Day '1/5*3/3=205' 3 Replcias may not survive a zone failure at peak
  # Example:  1 TB/Day '1/5*3/6=103' 6 ensures at least one node per zone
  # 100 GB should be the smallest disk used for Kafka this may result in some waste
  storage:
    type: persistent-claim
    size: 150Gi
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
              - key: "workloadClass"
                operator: "In"
                values: ["general","compute"]  
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: strimzi.io/component-type
                operator: In
                values:
                  - "kafka"
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchExpressions:
          - key: strimzi.io/name
            operator: In
            values:
              - "${local.codename}-logscale-zookeeper"
  tolerations:
    - key: "workloadClass"
      operator: "Equal"
      value: "compute"
      effect: "NoSchedule"      
  resources:
    requests:
      memory: 1Gi
      cpu: "250m"
    limits:
      memory: 2Gi
      cpu: "1"
  storage:
    deleteClaim: true
    type: persistent-claim
    size: 10Gi
    class: premium-rwo

otel:  
  components:
    inject: true
    otlpURI: http://ops-logscale-app-collector-headless.logscale-ops.svc.cluster.local:4317
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
