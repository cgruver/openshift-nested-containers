# Demo for Enabling Nested Containers in OpenShift

1. Install `butane`:

   [https://coreos.github.io/butane/](https://coreos.github.io/butane/)

   We need `butane` to assist with the creation of MachineConfigs.  It's really handy for that.

   __Note:__ If you previously followed one of my blog posts to install your OpenShift cluster, then you should already have `butane` installed.

## Patch the kernel

```bash
scp *.rpm core@10.11.12.101:/var/home/core
```

```bash
ssh core@10.11.12.101
```

```bash
rpm-ostree override replace *.rpm
```

## Change the Container Runtime to `crun`

```bash
cat << EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: ContainerRuntimeConfig
metadata:
 name: enable-crun-worker
spec:
 machineConfigPoolSelector:
   matchLabels:
     pools.operator.machineconfiguration.openshift.io/worker: ""
 containerRuntimeConfig:
   defaultRuntime: crun
EOF
```

For SNO:

```bash
cat << EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: ContainerRuntimeConfig
metadata:
 name: enable-crun-master
spec:
 machineConfigPoolSelector:
   matchLabels:
     pools.operator.machineconfiguration.openshift.io/master: ""
 containerRuntimeConfig:
   defaultRuntime: crun
EOF
```

## Enable `ProcMountType` And `UserNamespacesSupport` Feature Gates

__Note:__ Because this feature gate is still in *Alpha* state, enabling it will render your cluster non-upgradable.

```bash
oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["ProcMountType","UserNamespacesSupport"]}}}'
```

## Enable `/dev/fuse` and `/dev/net/tun`

Modify `/etc/crio/crio.conf`

```bash
allowed_devices = [
        "/dev/fuse",
        "/dev/net/tun"
]
```

Create `/etc/modules-load.d/nested-containers.conf`

```bash
tun
rtnl-link-bridge
ipt_addrtype
ipt_MASQUERADE
```

Create `/var/home/core/nested_containers.te`

```bash
module nested_containers 1.0;

require {
	type null_device_t;
	type zero_device_t;
	type urandom_device_t;
	type random_device_t;
	type container_file_t;
	type container_engine_t;
	type devtty_t;
	type setfiles_t;
	class chr_file { mounton read setattr write };
	class sock_file mounton;
}

#============= container_engine_t ==============
allow container_engine_t container_file_t:sock_file mounton;
allow container_engine_t devtty_t:chr_file mounton;
allow container_engine_t null_device_t:chr_file { mounton setattr };
allow container_engine_t random_device_t:chr_file mounton;
allow container_engine_t urandom_device_t:chr_file mounton;
allow container_engine_t zero_device_t:chr_file mounton;
```

```bash
checkmodule -M -m -o nested_containers.mod nested_containers.te && semodule_package -o nested_containers.pp -m nested_containers.mod && semodule -i nested_containers.pp
```

## Create an SCC for nested containers

```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: nested-containers
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities:
- SETUID
- SETGID
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
groups: []
priority: null
readOnlyRootFilesystem: false
requiredDropCapabilities:
- KILL
- MKNOD
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
  seLinuxOptions:
    type: container_engine_t
supplementalGroups:
  type: RunAsAny
users: []
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF
```

## As cluster-admin allow a non-admin user to use the podman SCC

```bash
oc adm policy add-scc-to-user nested-containers <non-admin-user>
```

## Log into OpenShift as a non-admin user

## Create a new Project

```bash
oc new-project podman-demo
```

## Create a Pod as your non-cluster-admin user

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
name: nested-podman
namespace: podman-demo
annotations:
  io.kubernetes.cri-o.Devices: "/dev/fuse,/dev/net/tun"
spec:
  hostUsers: false
  containers:
  - name: nested-podman
    image: quay.io/cgruver0/che/nested:latest
    securityContext:
      allowPrivilegeEscalation: true
      procMount: Unmasked
      capabilities:
        add:
        - "SETUID"
        - "SETGID"
EOF
```

## Open a shell into the Pod:

```bash
oc rsh nested-podman
```

## Run the following container:

```bash
podman run -d --rm --name webserver -p 8080:80 quay.io/libpod/banner
```

## Observe that the container is running and listening on port 8080:

```bash
curl http://localhost:8080
```

## Install the OpenShift Dev Spaces Operator

## Create an instance of Dev Spaces

```bash
cat << EOF | oc apply -f -
apiVersion: v1                      
kind: Namespace                 
metadata:
  name: devspaces
---           
apiVersion: org.eclipse.che/v2 
kind: CheCluster   
metadata:              
  name: devspaces  
  namespace: devspaces
spec:                         
  components:                  
    cheServer:      
      debug: false
      logLevel: INFO
    metrics:                
      enable: true
    pluginRegistry:
      openVSXURL: https://open-vsx.org
  containerRegistry: {}      
  devEnvironments:       
    startTimeoutSeconds: 300
    secondsOfRunBeforeIdling: -1
    maxNumberOfWorkspacesPerUser: -1
    maxNumberOfRunningWorkspacesPerUser: 5
    containerBuildConfiguration:
      openShiftSecurityContextConstraint: nested-containers
    disableContainerBuildCapabilities: false
    defaultComponents:
    - name: dev-tools
      container:
        image: quay.io/cgruver0/che/dev-tools:latest
        memoryLimit: 6Gi
        mountSources: true
    defaultEditor: che-incubator/che-code/latest
    defaultNamespace:
      autoProvision: true
      template: <username>-devspaces
    secondsOfInactivityBeforeIdling: 1800
    storage:
      pvcStrategy: per-workspace
  gitServices: {}
  networking: {}   
EOF
```

