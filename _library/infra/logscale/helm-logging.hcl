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
  source = "git::git@github.com:logscale-contrib/tf-self-managed-logscale-k8s-helm.git?ref=v1.4.4"
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

}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../helm/"
  ]
}
generate "provider" {
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

  repository = "https://kube-logging.github.io/helm-charts"

  release          = local.codename
  chart            = "logging-operator-logging"
  chart_version    = "4.1.0"
  namespace        =  "logscale-ops"
  create_namespace = false
  project          = "common"

  values = yamldecode(<<EOF
nameOverride: logops
controlNamespace: logscale-ops
# errorOutputRef: logscale
# -- EventTailer config
eventTailer: 
  name: ops
  # pvc:
  #   accessModes:
  #     - ReadWriteOnce
  #   volumeMode: Filesystem
  #   storage: 1Gi
  #   storageClassName: standard

# -- HostTailer config
hostTailer:
  name: ops
  systemdTailers:
    - name: host-tailer-systemd-kubelet
      disabled: false
      maxEntries: 200
      systemdFilter: "kubelet.service"
nodeAgents:
  - name: win-agent
    profile: windows
    nodeAgentFluentbit:
      tls:
        enabled: false
  - name: linux-agent
    profile: linux
    nodeAgentFluentbit:
      metrics:
        prometheusAnnotations: true
        serviceMonitor: false
      tls:
        enabled: false 
enableRecreateWorkloadOnImmutableFieldChange: true
clusterFlows:
  - name: k8s-infra-hosts
    spec:
      filters:
        - record_transformer:
            records:
            - cwd.cid: "244466666888888899999999"    
      match:
      - select:
          labels:
            app.kubernetes.io/name: host-tailer
          namespaces:
            - logscale-ops
      globalOutputRefs:
        - logscale-infra-host
  - name: k8s-infra-events
    spec:
      filters:
        - record_transformer:
            records:
            - cwd.cid: "244466666888888899999999"    
      match:
      - select:
          labels:
            app.kubernetes.io/name: event-tailer
          namespaces:
            - logscale-ops
      globalOutputRefs:
        - logscale-infra-event
  - name: k8s-infra-pods
    spec:
      filters:
        - record_transformer:
            records:
            - cwd.cid: "244466666888888899999999"    
      match:
      - select:
          namespaces:
            - argocd
      - select:
          namespaces:
            - cert-manager
      - select:
          namespaces:
            - external-dns
      - select:
          namespaces:
            - k8s-image-swapper
      - select:
          namespaces:
            - kube-node-lease
      - select:
          namespaces:
            - kube-public
      - select:
          namespaces:
            - kube-system
      - select:
          namespaces:
            - logging
      - select:
          namespaces:
            - monitoring
      globalOutputRefs:
        - logscale-infra-pod
  - name: k8s-app-pods
    spec:
      filters:
        - record_transformer:
            records:
            - cwd.cid: "244466666888888899999999"    
      match:
      - exclude:
          namespaces:
            - argocd
      - exclude:
          namespaces:
            - cert-manager
      - exclude:
          namespaces:
            - external-dns
      - exclude:
          namespaces:
            - k8s-image-swapper
      - exclude:
          namespaces:
            - kube-node-lease
      - exclude:
          namespaces:
            - kube-public
      - exclude:
          namespaces:
            - kube-system
      - exclude:
          namespaces:
            - logging
      - exclude:
          namespaces:
            - monitoring
      - exclude:
          labels:
            app.kubernetes.io/name: event-tailer
          namespaces:
            - logscale-ops
      - exclude:
          labels:
            app.kubernetes.io/name: host-tailer
          namespaces:
            - logscale-ops            
      - select: {}
      globalOutputRefs:
        - logscale-app-pod



clusterOutputs:
  - name: logscale-infra-event
    spec:
      splunkHec:
        hec_host: ops-logscale-http-only
        insecure_ssl: true
        protocol: http
        hec_port: 8080
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-infra-kubernetes-cluster-local-event
              key: token
        format:
          type: json
  - name: logscale-infra-host
    spec:
      splunkHec:
        hec_host: ops-logscale-http-only
        insecure_ssl: true
        protocol: http
        hec_port: 8080
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-infra-kubernetes-cluster-local-host
              key: token
        format:
          type: json
  - name: logscale-infra-pod
    spec:
      splunkHec:
        hec_host: ops-logscale-http-only
        insecure_ssl: true
        protocol: http
        hec_port: 8080
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-infra-kubernetes-cluster-local-pod
              key: token
        format:
          type: json          
  - name: logscale-app-pod
    spec:
      splunkHec:
        hec_host: ops-logscale-http-only
        insecure_ssl: true
        protocol: http
        hec_port: 8080
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-apps-kubernetes-cluster-local-pod
              key: token
        format:
          type: json          

fluentbit:
  resources:
    limits:
      cpu: 200m
      memory: 100M
    requests:
      cpu: 100m
      memory: 50M
fluentd:
  resources:
    limits:
      cpu: 1000m
      memory: 400M
    requests:
      cpu: 500m
      memory:  100M  
EOF
  )

  ignoreDifferences = [
  ]
}
