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

  argocd        = read_terragrunt_config(find_in_parent_folders("argocd.hcl"))
  isArgoCluster = local.argocd.locals.isArgoCluster


  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env       = local.environment_vars.locals.environment
  codename  = local.environment_vars.locals.codename
  name_vars = read_terragrunt_config(find_in_parent_folders("name.hcl"))
  name      = local.name_vars.locals.name


  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  fqdn = format("%s.%s", join("-", compact(["logscale", local.codename, "ops", "inputs"])), local.domain_name)

  #ops-logscale-http-only.logscale-ops.svc.cluster.local
  # insecure_ssl: ${local.inputs.insecure_ssl}
  # protocol: ${local.inputs.protocol}
  # hec_port: ${local.inputs.port}

  # inputs_url   = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? "ops-logscale-ingest-only.logscale-ops.svc.cluster.local" : "logscale-ops-inputs.${local.domain_name}"
  # insecure_ssl = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? true : false
  # protocol     = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? "http" : "https"
  # hec_port     = "${local.name}-${local.env}-${local.codename}" == "${local.name}-${local.env}-ops" ? "8080" : "443"
  # isArgoCluster
  inputs_url   = local.isArgoCluster ? "logscale-ingest-only.logscale-ops.svc.cluster.local" : format("%s.%s", join("-", compact(["logscale", local.codename, "ops", "inputs"])), local.domain_name)
  insecure_ssl = local.isArgoCluster ? true : false
  protocol     = local.isArgoCluster ? "http" : "https"
  hec_port     = local.isArgoCluster ? "8080" : "443"


  # inputs_url   =   local.fqdn
  # insecure_ssl = false
  # protocol     = "https"
  # hec_port     = "443" 


}



dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../../ops/gke/"
}
dependency "k8sEdge" {
  config_path = "${get_terragrunt_dir()}/../../../gke/"
}

dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../../../ops/apps/argocd/projects/common/",
    "${get_terragrunt_dir()}/../secrets/"
  ]
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
  destination_name = local.argocd.locals.isArgoCluster ? "in-cluster" : dependency.k8sEdge.outputs.name

  name = "logging-operator-logging"

  repository = "https://kube-logging.github.io/helm-charts"

  release          = dependency.k8sEdge.outputs.name
  chart            = "logging-operator-logging"
  chart_version    = "4.1.0"
  namespace        = "logging"
  create_namespace = true
  project          = "common"

  values = yamldecode(<<EOF
nameOverride: logops
controlNamespace: logging
# errorOutputRef: logscale
# -- EventTailer config
eventTailer: 
  name: ops
  containerOverrides:
    resources:
      requests:
        cpu: 50m
        memory: 50Mi

# -- HostTailer config
hostTailer:
  name: ops
  workloadOverrides:
    tolerations:
      - operator: "Exists"

  systemdTailers:
    - name: host-tailer-systemd-kubelet
      disabled: false
      maxEntries: 200
      systemdFilter: "kubelet.service"
      containerOverrides:
        resources:
          requests:
            cpu: 50m
            memory: 50Mi
# nodeAgents:
#   - name: win-agent
#     profile: windows
#     nodeAgentFluentbit:
#       tls:
#         enabled: false
#   - name: linux-agent
#     profile: linux
#     nodeAgentFluentbit:
#       metrics:
#         prometheusAnnotations: true
#         serviceMonitor: false
#       tls:
#         enabled: false 
enableRecreateWorkloadOnImmutableFieldChange: true
clusterFlows:
  - name: k8s-infra-hosts
    spec:
      filters:
        - record_transformer:
            records:
            - cluster_name: "${dependency.k8sEdge.outputs.name}"
      match:
      - select:
          labels:
            app.kubernetes.io/name: host-tailer
          namespaces:
            - logging
      globalOutputRefs:
        - logscale-infra-host
  - name: k8s-infra-events
    spec:
      filters:
        - record_transformer:
            records:
            - cluster_name: "${dependency.k8sEdge.outputs.name}"
      match:
      - select:
          labels:
            app.kubernetes.io/name: event-tailer
          namespaces:
            - logging
      globalOutputRefs:
        - logscale-infra-event
  - name: k8s-infra-pods
    spec:
      filters:
        - record_transformer:
            records:
            - cluster_name: "${dependency.k8sEdge.outputs.name}"
      match:
      - exclude:
          labels:
            app.kubernetes.io/name: event-tailer
          namespaces:
            - logging
      - exclude:
          labels:
            app.kubernetes.io/name: host-tailer
          namespaces:
            - logging          
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
            - cluster_name: "${dependency.k8sEdge.outputs.name}"
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
        
      - select: {}
      globalOutputRefs:
        - logscale-app-pod



clusterOutputs:
  - name: logscale-infra-event
    spec:
      splunkHec:
        ca_path: 
          value: /etc/ssl/certs/
        hec_host: ${local.inputs_url}
        insecure_ssl: ${local.insecure_ssl}
        protocol: ${local.protocol}
        hec_port: ${local.hec_port}
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-content-infra-kubernetes-cluster-local-event
              key: token
        format:
          type: json
  - name: logscale-infra-host
    spec:
      splunkHec:
        ca_path: 
          value: /etc/ssl/certs/
        hec_host: ${local.inputs_url}
        insecure_ssl: ${local.insecure_ssl}
        protocol: ${local.protocol}
        hec_port: ${local.hec_port}
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-content-infra-kubernetes-cluster-local-host
              key: token
        format:
          type: json
  - name: logscale-infra-pod
    spec:
      splunkHec:
        ca_path: 
          value: /etc/ssl/certs/
        hec_host: ${local.inputs_url}
        insecure_ssl: ${local.insecure_ssl}
        protocol: ${local.protocol}
        hec_port: ${local.hec_port}
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-content-infra-kubernetes-cluster-local-pod
              key: token
        format:
          type: json          
  - name: logscale-app-pod
    spec:
      splunkHec:
        ca_path: 
          value: /etc/ssl/certs/
        hec_host: ${local.inputs_url}
        insecure_ssl: ${local.insecure_ssl}
        protocol: ${local.protocol}
        hec_port: ${local.hec_port}
        hec_token:
          valueFrom:
            secretKeyRef:
              name: ops-logscale-content-apps-kubernetes-cluster-local-pod
              key: token
        format:
          type: json          

fluentbit:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
  tolerations:
    - operator: "Exists"

fluentd:
  scaling:
    replicas: 3
  resources:
    requests:
      cpu: "100m"
      memory:  128Mi
EOF
  )

  ignoreDifferences = [
  ]
}
