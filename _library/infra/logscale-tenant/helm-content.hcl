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
  infra_vars     = read_terragrunt_config(find_in_parent_folders("infra.hcl"))
  infra_env      = local.infra_vars.locals.environment
  infra_codename = local.infra_vars.locals.codename
  infra_geo      = local.infra_vars.locals.geo

  infra_name       = local.infra_vars.locals.active == "1" ? "1" : "2"
  destination_name = join("-", compact([local.infra_codename, local.infra_env, local.infra_geo, local.infra_name]))

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

  cluster_vars   = read_terragrunt_config(find_in_parent_folders("cluster.hcl"))
  active_cluster = local.cluster_vars.locals.active


}


dependency "k8s" {
  config_path = "${get_terragrunt_dir()}/../../../infra/${local.infra_geo}/ops/gke/"
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

  destination_name = local.destination_name

  repository = "https://logscale-contrib.github.io/helm-logscale-content"

  release          = join("-", compact(["logscale", local.name, local.codename, "content"]))
  chart            = "logscale-content"
  chart_version    = "1.3.1"
  namespace        = join("-", compact(["logscale", local.name, local.codename]))
  create_namespace = false
  project          = "common"

  values = yamldecode(<<EOF
fullnameOverride: ${join("-", compact(["logscale", local.name, local.codename]))}
managedClusterName: ${join("-", compact(["logscale", local.name, local.codename]))}
repositoryDefault:
  ingestSizeInGB: "1073741824"
  storageSizeInGB: "1073741824"
  timeInDays: "9999"
  allowDataDeletion: false
eso:
  secretStoreRefs:
    - name: ops
      kind: ClusterSecretStore  
repositories:
  - name: iaas-google-cloud
  - name: apps-kubernetes
    parsers:
      - name: kube-logging-pod
        parserScript: |
          parsejson() 
          | case {
              message=/^\{/ |
                    @type:="kube-logging-pod-json" 
                    | @rawstring:=message 
                    | parsejson(field=message,prefix="event.") 
                    | drop(fields=[message])
                    | case {
                        event.msg=* | @rawstring:=rename(event.msg);
                        event.message=* | @rawstring:=rename(event.message);
                        *;
                    }
                    ;
              * | @type:="kube-logging-pod-string"  | @rawstring:=message;
            }
            | kubernetes.labels.app.kubernetes.io_component := rename("kubernetes.labels.app.kubernetes.io/component")
            | kubernetes.labels.app.kubernetes.io_instance := rename("kubernetes.labels.app.kubernetes.io/instance")
            | kubernetes.labels.app.kubernetes.io_managed_by := rename("kubernetes.labels.app.kubernetes.io/managed-by")
            | kubernetes.labels.app.kubernetes.io_name := rename("kubernetes.labels.app.kubernetes.io/name")
            | kubernetes.labels.app.kubernetes.io_part_of := rename("kubernetes.labels.app.kubernetes.io/part-of")
            | case {
                kubernetes.container_name = "humio" |
                    @type:="humio" |
                    @rawstring:=rename(event.message) |
                    class:=rename(event.class) |
                    kind:=rename(event.kind) |
                    loglevel:=rename(event.loglevel) |
                    thread:=rename(event.thread) |
                    vhost:=rename(event.vhost) |
                    @timestamp := rename(event.@timestamp) |
                    kvParse();
                kubernetes.container_name = "humio-operator" |
                    @type:="humio-operator" |
                    @rawstring:=rename(event.msg) | drop(fields=[event.ts]);
                kubernetes.container_name = "event-tailer"  | @type:="k8s-event";
                kubernetes.container_name = "host-tailer*"  | @type:=kubernetes.container_name | @rawstring:=rename(event.MESSAGE);
                event.msg="*" |
                    @type:="kube-logging-json-msg" |
                    @rawstring:=rename(event.msg);
                *;
            }

        testData:
            - |
              {"stream":"stderr","logtag":"F","message":"this is just an event","kubernetes":{"pod_name":"ops-678d8cd7bc-z72r5","namespace_name":"logscale-operator","pod_id":"5fe1b843-01ec-4d29-bfb7-796665c76f97","labels":{"app":"humio-operator","app.kubernetes.io/instance":"ops","app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/name":"humio-operator","helm.sh/chart":"humio-operator-0.18.0","pod-template-hash":"678d8cd7bc"},"annotations":{"productID":"none","productName":"humio-operator","productVersion":"0.18.0"},"host":"gke-logscale-prod-ops-compute-44fb8724-0pzt","container_name":"humio-operator","docker_id":"0e5bae5bd0edc93a1281131aebf3ccaa56926f3cd2b9fd969f104bfb4e549ef8","container_hash":"docker.io/humio/humio-operator@sha256:f78a981d3bdbffddd097a7395f859eb6d2ffebfd0345c96b4385c8b5ec3eab1c","container_image":"docker.io/humio/humio-operator:0.18.0"}}
            - |
              {"stream":"stderr","logtag":"F","message":"{\"level\":\"info\",\"ts\":\"2023-05-08T11:54:36.701998152Z\",\"caller\":\"controllers/humiocluster_pod_status.go:106\",\"func\":\"github.com/humio/humio-operator/controllers.(*HumioClusterReconciler).getPodsStatus\",\"msg\":\"pod status readyCount=3 notReadyCount=0 podsReady=[ops-logscale-core-zvpuwy ops-logscale-core-ndztkg ops-logscale-core-uupmaq] podsNotReady=[]\",\"Operator.Commit\":\"58aaa7326f32e96a85bda10acfce95fb86509bce\",\"Operator.Date\":\"2023-04-06T15:23:58+00:00\",\"Operator.Version\":\"0.18.0\",\"Request.Namespace\":\"logscale-ops\",\"Request.Name\":\"ops-logscale\",\"Request.Type\":\"HumioClusterReconciler\",\"Reconcile.ID\":\"nbluea\"}","kubernetes":{"pod_name":"ops-678d8cd7bc-z72r5","namespace_name":"logscale-operator","pod_id":"5fe1b843-01ec-4d29-bfb7-796665c76f97","labels":{"app":"humio-operator","app.kubernetes.io/instance":"ops","app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/name":"humio-operator","helm.sh/chart":"humio-operator-0.18.0","pod-template-hash":"678d8cd7bc"},"annotations":{"productID":"none","productName":"humio-operator","productVersion":"0.18.0"},"host":"gke-logscale-prod-ops-compute-44fb8724-0pzt","container_name":"humio-operator","docker_id":"0e5bae5bd0edc93a1281131aebf3ccaa56926f3cd2b9fd969f104bfb4e549ef8","container_hash":"docker.io/humio/humio-operator@sha256:f78a981d3bdbffddd097a7395f859eb6d2ffebfd0345c96b4385c8b5ec3eab1c","container_image":"docker.io/humio/humio-operator:0.18.0"}}
        tagFields:
          - "@type"
          - kind
          - vhost
          - cluster_name
          - cwd.cid
          - kubernetes.namespace_name
          - kubernetes.labels.app.kubernetes.io_name
          - kubernetes.labels.app.kubernetes.io_part_of
          - kubernetes.labels.app.kubernetes.io_instance
          - kubernetes.labels.app.kubernetes.io_component      


        testData:
            - |
              {"stream":"stderr","logtag":"F","message":"this is just an event","kubernetes":{"pod_name":"ops-678d8cd7bc-z72r5","namespace_name":"logscale-operator","pod_id":"5fe1b843-01ec-4d29-bfb7-796665c76f97","labels":{"app":"humio-operator","app.kubernetes.io/instance":"ops","app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/name":"humio-operator","helm.sh/chart":"humio-operator-0.18.0","pod-template-hash":"678d8cd7bc"},"annotations":{"productID":"none","productName":"humio-operator","productVersion":"0.18.0"},"host":"gke-logscale-prod-ops-compute-44fb8724-0pzt","container_name":"humio-operator","docker_id":"0e5bae5bd0edc93a1281131aebf3ccaa56926f3cd2b9fd969f104bfb4e549ef8","container_hash":"docker.io/humio/humio-operator@sha256:f78a981d3bdbffddd097a7395f859eb6d2ffebfd0345c96b4385c8b5ec3eab1c","container_image":"docker.io/humio/humio-operator:0.18.0"}}
            - |
              {"stream":"stderr","logtag":"F","message":"{\"level\":\"info\",\"ts\":\"2023-05-08T11:54:36.701998152Z\",\"caller\":\"controllers/humiocluster_pod_status.go:106\",\"func\":\"github.com/humio/humio-operator/controllers.(*HumioClusterReconciler).getPodsStatus\",\"msg\":\"pod status readyCount=3 notReadyCount=0 podsReady=[ops-logscale-core-zvpuwy ops-logscale-core-ndztkg ops-logscale-core-uupmaq] podsNotReady=[]\",\"Operator.Commit\":\"58aaa7326f32e96a85bda10acfce95fb86509bce\",\"Operator.Date\":\"2023-04-06T15:23:58+00:00\",\"Operator.Version\":\"0.18.0\",\"Request.Namespace\":\"logscale-ops\",\"Request.Name\":\"ops-logscale\",\"Request.Type\":\"HumioClusterReconciler\",\"Reconcile.ID\":\"nbluea\"}","kubernetes":{"pod_name":"ops-678d8cd7bc-z72r5","namespace_name":"logscale-operator","pod_id":"5fe1b843-01ec-4d29-bfb7-796665c76f97","labels":{"app":"humio-operator","app.kubernetes.io/instance":"ops","app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/name":"humio-operator","helm.sh/chart":"humio-operator-0.18.0","pod-template-hash":"678d8cd7bc"},"annotations":{"productID":"none","productName":"humio-operator","productVersion":"0.18.0"},"host":"gke-logscale-prod-ops-compute-44fb8724-0pzt","container_name":"humio-operator","docker_id":"0e5bae5bd0edc93a1281131aebf3ccaa56926f3cd2b9fd969f104bfb4e549ef8","container_hash":"docker.io/humio/humio-operator@sha256:f78a981d3bdbffddd097a7395f859eb6d2ffebfd0345c96b4385c8b5ec3eab1c","container_image":"docker.io/humio/humio-operator:0.18.0"}}
    ingestTokens:
      - name: cluster-local-pod
        parserName: kube-logging-pod
        eso:
          push: true        
  - name: infra-kubernetes
    parsers:
      - name: kube-logging-event
        parserScript: |
            | @type:="kube-logging-event"
            | parsejson()
            | parsejson(field=message)
            | @rawstring:=event.message 
            | drop(fields=[message,event.message])            
        testData:
            - |
              {"stream":"stdout","logtag":"F","message":"{\"verb\":\"ADDED\",\"event\":{\"metadata\":{\"name\":\"ops-logscale-setroot-mr4wk.175e203bea844053\",\"namespace\":\"logscale-ops\",\"uid\":\"57544ced-af46-40cc-a38f-893784212f6a\",\"resourceVersion\":\"614008\",\"creationTimestamp\":\"2023-05-11T15:25:52Z\",\"managedFields\":[{\"manager\":\"kubelet\",\"operation\":\"Update\",\"apiVersion\":\"v1\",\"time\":\"2023-05-11T15:25:52Z\"}]},\"involvedObject\":{\"kind\":\"Pod\",\"namespace\":\"logscale-ops\",\"name\":\"ops-logscale-setroot-mr4wk\",\"uid\":\"5f5e47f4-35f0-4136-bf7d-cab6c06009dd\",\"apiVersion\":\"v1\",\"resourceVersion\":\"16970179\",\"fieldPath\":\"spec.containers{humio-set-root}\"},\"reason\":\"Created\",\"message\":\"Created container humio-set-root\",\"source\":{\"component\":\"kubelet\",\"host\":\"gke-logscale-prod-ops-compute-d3b0b3f1-n72x\"},\"firstTimestamp\":\"2023-05-11T15:25:52Z\",\"lastTimestamp\":\"2023-05-11T15:25:52Z\",\"count\":1,\"type\":\"Normal\",\"eventTime\":null,\"reportingComponent\":\"\",\"reportingInstance\":\"\"}}","kubernetes":{"pod_name":"ops-event-tailer-0","namespace_name":"logscale-ops","pod_id":"ff0a3bf6-3392-464b-a34a-065989ed2dda","labels":{"app.kubernetes.io/instance":"ops-event-tailer","app.kubernetes.io/name":"event-tailer","controller-revision-hash":"ops-event-tailer-795565f5fc","statefulset.kubernetes.io/pod-name":"ops-event-tailer-0"},"host":"gke-logscale-prod-ops-compute-44fb8724-6nz5","container_name":"event-tailer","docker_id":"9fc97b0099f1699c7ee5b852951d70e9f8093f38b1557452a9b72de8fedbc12a","container_hash":"us-central1-docker.pkg.dev/logsr-life-production/logscale-prod-ops/docker.io/banzaicloud/eventrouter@sha256:6353d3f961a368d95583758fa05e8f4c0801881c39ed695bd4e8283d373a4262","container_image":"us-central1-docker.pkg.dev/logsr-life-production/logscale-prod-ops/docker.io/banzaicloud/eventrouter:v0.1.0"},"cwd.cid":"244466666888888899999999"}
        tagFields:
          - "@type"
          - cluster_name
          - cwd.cid
          - event.involvedObject.kind
          - event.involvedObject.name
          - event.involvedObject.namespace
      - name: kube-logging-host
        parserScript: |
            | @type:="kube-logging-host"
            | parsejson() 
            | parsejson(field=message) 
            | drop([message])
            | @rawstring:=rename(MESSAGE)
            | @host:=rename(_HOSTNAME)

        testData:
            - |
              {"stream":"stdout","logtag":"F","message":"{\"_BOOT_ID\":\"6d724a8f70c54fd5bba8b550e314e3ed\",\"_MACHINE_ID\":\"b040d879e489ad5beffb070f0fd8b6ca\",\"PRIORITY\":\"6\",\"SYSLOG_FACILITY\":\"3\",\"_UID\":\"0\",\"_GID\":\"0\",\"_SYSTEMD_SLICE\":\"system.slice\",\"_CAP_EFFECTIVE\":\"1ffffffffff\",\"_TRANSPORT\":\"stdout\",\"_HOSTNAME\":\"gke-logscale-prod-ops-compute-d3b0b3f1-n72x\",\"_STREAM_ID\":\"bc3e7816522a4510adad2c72701adad5\",\"SYSLOG_IDENTIFIER\":\"kubelet\",\"_PID\":\"1960\",\"_COMM\":\"kubelet\",\"_EXE\":\"/home/kubernetes/bin/kubelet\",\"_CMDLINE\":\"/home/kubernetes/bin/kubelet --v=2 --cloud-provider=external --experimental-mounter-path=/home/kubernetes/containerized_mounter/mounter --cert-dir=/var/lib/kubelet/pki/ --kubeconfig=/var/lib/kubelet/kubeconfig --max-pods=110 --volume-plugin-dir=/home/kubernetes/flexvolume --node-status-max-images=25 --container-runtime=remote --container-runtime-endpoint=unix:///run/containerd/containerd.sock --runtime-cgroups=/system.slice/containerd.service --registry-qps=10 --registry-burst=20 --config /home/kubernetes/kubelet-config.yaml \\\"--pod-sysctls=net.core.somaxconn=1024,net.ipv4.conf.all.accept_redirects=0,net.ipv4.conf.all.forwarding=1,net.ipv4.conf.all.route_localnet=1,net.ipv4.conf.default.forwarding=1,net.ipv4.ip_forward=1,net.ipv4.tcp_fin_timeout=60,net.ipv4.tcp_keepalive_intvl=60,net.ipv4.tcp_keepalive_probes=5,net.ipv4.tcp_keepalive_time=300,net.ipv4.tcp_rmem=4096 87380 6291456,net.ipv4.tcp_syn_retries=6,net.ipv4.tcp_tw_reuse=0,net.ipv4.tcp_wmem=4096 16384 4194304,net.ipv4.udp_rmem_min=4096,net.ipv4.udp_wmem_min=4096,net.ipv6.conf.all.disable_ipv6=1,net.ipv6.conf.default.accept_ra=0,net.ipv6.conf.default.disable_ipv6=1,net.netfilter.nf_conntrack_generic_timeout=600,net.netfilter.nf_conntrack_tcp_be_liberal=1,net.netfilter.nf_conntrack_tcp_timeout_close_wait=3600,net.netfilter.nf_conntrack_tcp_timeout_established=86400\\\" --cgroup-driver=systemd --pod-infra-container-image=gke.gcr.io/pause:3.8@sha256:880e63f94b145e46f1b1082bb71b85e21f16b99b180b9996407d61240ceb9830\",\"_SYSTEMD_CGROUP\":\"/system.slice/kubelet.service\",\"_SYSTEMD_UNIT\":\"kubelet.service\",\"_SYSTEMD_INVOCATION_ID\":\"79fbddf7297943528e05a11920c1f8e3\",\"MESSAGE\":\"I0511 16:09:55.021129    1960 provider.go:102] Refreshing cache for provider: *credentialprovider.defaultDockerConfigProvider\"}","kubernetes":{"pod_name":"ops-host-tailer-69xwx","namespace_name":"logscale-ops","pod_id":"40f1661b-10a0-45b7-b03d-01e230c90f04","labels":{"app.kubernetes.io/instance":"ops-host-tailer","app.kubernetes.io/name":"host-tailer","controller-revision-hash":"7476d8744f","pod-template-generation":"1"},"host":"gke-logscale-prod-ops-compute-d3b0b3f1-n72x","container_name":"host-tailer-systemd-kubelet","docker_id":"07e22a3c742abfab38b4df9c3131e132180055b796ffff2fa46cc7f58454508e","container_hash":"us-central1-docker.pkg.dev/logsr-life-production/logscale-prod-ops/docker.io/fluent/fluent-bit@sha256:b33d4bf7f7b870777c1f596bc33d6d347167d460bc8cc6aa50fddcbedf7bede5","container_image":"us-central1-docker.pkg.dev/logsr-life-production/logscale-prod-ops/docker.io/fluent/fluent-bit:1.9.10"},"cwd.cid":"244466666888888899999999"}
        tagFields:
          - "@type"
          - "@host"
          - cluster_name
          - cwd.cid
          - "_SYSTEMD_UNIT"
      - name: kube-logging-pod
        parserScript: |
          parsejson() 
          | case {
              message=/^\{/ |
                    @type:="kube-logging-pod-json" 
                    | @rawstring:=message 
                    | parsejson(field=message,prefix="event.") 
                    | drop(fields=[message])
                    | case {
                        event.msg=* | @rawstring:=rename(event.msg);
                        event.message=* | @rawstring:=rename(event.message);
                        *;
                    }
                    ;
              * | @type:="kube-logging-pod-string"  | @rawstring:=message;
            }
            | kubernetes.labels.app.kubernetes.io_component := rename("kubernetes.labels.app.kubernetes.io/component")
            | kubernetes.labels.app.kubernetes.io_instance := rename("kubernetes.labels.app.kubernetes.io/instance")
            | kubernetes.labels.app.kubernetes.io_managed_by := rename("kubernetes.labels.app.kubernetes.io/managed-by")
            | kubernetes.labels.app.kubernetes.io_name := rename("kubernetes.labels.app.kubernetes.io/name")
            | kubernetes.labels.app.kubernetes.io_part_of := rename("kubernetes.labels.app.kubernetes.io/part-of")
        testData:
            - |
              {"stream":"stderr","logtag":"F","message":"this is just an event","kubernetes":{"pod_name":"ops-678d8cd7bc-z72r5","namespace_name":"logscale-operator","pod_id":"5fe1b843-01ec-4d29-bfb7-796665c76f97","labels":{"app":"humio-operator","app.kubernetes.io/instance":"ops","app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/name":"humio-operator","helm.sh/chart":"humio-operator-0.18.0","pod-template-hash":"678d8cd7bc"},"annotations":{"productID":"none","productName":"humio-operator","productVersion":"0.18.0"},"host":"gke-logscale-prod-ops-compute-44fb8724-0pzt","container_name":"humio-operator","docker_id":"0e5bae5bd0edc93a1281131aebf3ccaa56926f3cd2b9fd969f104bfb4e549ef8","container_hash":"docker.io/humio/humio-operator@sha256:f78a981d3bdbffddd097a7395f859eb6d2ffebfd0345c96b4385c8b5ec3eab1c","container_image":"docker.io/humio/humio-operator:0.18.0"}}
            - |
              {"stream":"stderr","logtag":"F","message":"{\"level\":\"info\",\"ts\":\"2023-05-08T11:54:36.701998152Z\",\"caller\":\"controllers/humiocluster_pod_status.go:106\",\"func\":\"github.com/humio/humio-operator/controllers.(*HumioClusterReconciler).getPodsStatus\",\"msg\":\"pod status readyCount=3 notReadyCount=0 podsReady=[ops-logscale-core-zvpuwy ops-logscale-core-ndztkg ops-logscale-core-uupmaq] podsNotReady=[]\",\"Operator.Commit\":\"58aaa7326f32e96a85bda10acfce95fb86509bce\",\"Operator.Date\":\"2023-04-06T15:23:58+00:00\",\"Operator.Version\":\"0.18.0\",\"Request.Namespace\":\"logscale-ops\",\"Request.Name\":\"ops-logscale\",\"Request.Type\":\"HumioClusterReconciler\",\"Reconcile.ID\":\"nbluea\"}","kubernetes":{"pod_name":"ops-678d8cd7bc-z72r5","namespace_name":"logscale-operator","pod_id":"5fe1b843-01ec-4d29-bfb7-796665c76f97","labels":{"app":"humio-operator","app.kubernetes.io/instance":"ops","app.kubernetes.io/managed-by":"Helm","app.kubernetes.io/name":"humio-operator","helm.sh/chart":"humio-operator-0.18.0","pod-template-hash":"678d8cd7bc"},"annotations":{"productID":"none","productName":"humio-operator","productVersion":"0.18.0"},"host":"gke-logscale-prod-ops-compute-44fb8724-0pzt","container_name":"humio-operator","docker_id":"0e5bae5bd0edc93a1281131aebf3ccaa56926f3cd2b9fd969f104bfb4e549ef8","container_hash":"docker.io/humio/humio-operator@sha256:f78a981d3bdbffddd097a7395f859eb6d2ffebfd0345c96b4385c8b5ec3eab1c","container_image":"docker.io/humio/humio-operator:0.18.0"}}
        tagFields:
          - "@type"
          - cluster_name
          - cwd.cid
          - kubernetes.namespace_name
          - kubernetes.labels.app.kubernetes.io_name
          - kubernetes.labels.app.kubernetes.io_part_of
          - kubernetes.labels.app.kubernetes.io_instance
          - kubernetes.labels.app.kubernetes.io_component        
    ingestTokens:
      - name: cluster-local-event
        parserName: kube-logging-event
        eso:
          push: true        
      - name: cluster-local-host
        parserName: kube-logging-host
        eso:
          push: true        
      - name: cluster-local-pod
        parserName: kube-logging-pod
        eso:
          push: true        
  - name: strix
    parsers:
      - name: strix
        parserScript: |
            /^(?<ts>[^ ]*) loglevel=(?<loglevel>[^ ]*) (?<message>.*) testField\d+=(?<testField>\d+) (?<data>.*)/
            | parseTimestamp(field="ts") 
            | drop([ts])
        testData:
            - |
              2023-05-27T14:36:02.693Z loglevel=INFO hello world testField100=91 WzZos2POz7PWo4lZAPAq
        tagFields:
          - "testField"
          - loglevel
    ingestTokens:
      - name: strix-local
        parserName: strix
        eso:
          push: false        
EOF
  )

  ignoreDifferences = [
  ]
}
