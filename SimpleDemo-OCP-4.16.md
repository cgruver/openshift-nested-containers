# Demo for Enabling Nested Containers in OpenShift

1. Install `butane`:

   [https://coreos.github.io/butane/](https://coreos.github.io/butane/)

   We need `butane` to assist with the creation of MachineConfigs.  It's really handy for that.

   __Note:__ If you previously followed one of my blog posts to install your OpenShift cluster, then you should already have `butane` installed.

1. Apply the following MachineConfig: __Note:__ Your cluster will restart the targeted nodes.

   This MachineConfig does 3 things:

   1. Allow Pods with the `io.openshift.nested-podman` access to `/dev/fuse` and `/dev/net/tun`
   1. Load the kernel modules: `tun`, `rtnl-link-bridge`, and `ipt_addrtype`
   1. Apply an `selinux` module.

1. Set a variable for the OpenShift Node role that you are going to apply the changes to:

   If you are using a Single Node cluster or OpenShift Local, then set:

   ```bash
   NODE_ROLE=master
   ```

   If you are using an OpenShift cluster with separate control-plane and compute nodes, then set:

   ```bash
   NODE_ROLE=worker
   ```

1. Apply the MachineConfig:

   ```bash
   cat << EOF | butane | oc apply -f -
   variant: openshift
   version: 4.13.0
   metadata:
     labels:
       machineconfiguration.openshift.io/role: ${NODE_ROLE}
     name: nested-podman-${NODE_ROLE}
   storage:
     files:
     - path: /etc/crio/crio.conf.d/99-nested-podman
       mode: 0644
       overwrite: true
       contents:
         inline: |
           [crio.runtime.workloads.nested-podman]
           activation_annotation = "io.openshift.nested-podman"
           allowed_annotations = [
             "io.kubernetes.cri-o.Devices"
           ]
           [crio.runtime]
           allowed_devices = [
             "/dev/fuse",
             "/dev/net/tun"
           ]
     - path: /etc/modules-load.d/nested-podman.conf
       mode: 0644
       overwrite: true
       contents:
         inline: |
           tun
           rtnl-link-bridge
           ipt_addrtype
     - path: /etc/nested-podman/nested-podman.te
       mode: 0644
       overwrite: true
       contents:
         inline: |
           module nested-podman 1.0;

           require {
             type container_t;
             type cgroup_t;
             type devpts_t;
             type tmpfs_t;
             type sysfs_t;
             type nsfs_t;
             type devpts_t;
             type proc_t;
             type sysctl_t;
             type sysctl_irq_t;
             type proc_kcore_t;
             class dir mounton;
             class chr_file { setattr open} ;
             class file mounton;
             class filesystem { mount remount unmount };
           }
           allow container_t tmpfs_t:filesystem mount;
           allow container_t devpts_t:filesystem mount;
           allow container_t devpts_t:filesystem remount;
           allow container_t devpts_t:chr_file open;
           allow container_t devpts_t:chr_file setattr;
           allow container_t nsfs_t:filesystem unmount;
           allow container_t sysfs_t:filesystem mount;
           allow container_t sysfs_t:filesystem remount;
           allow container_t cgroup_t:filesystem remount;
           allow container_t proc_kcore_t:file mounton;
           allow container_t proc_t:dir mounton;
           allow container_t proc_t:file mounton;
           allow container_t proc_t:filesystem mount;
           allow container_t sysctl_irq_t:dir mounton;
           allow container_t sysctl_t:dir mounton;
           allow container_t sysctl_t:file mounton;
   systemd:
     units:
     - contents: |
         [Unit]
         Description=Modify SeLinux Type container_t to allow devpts_t and tmpfs_t
         DefaultDependencies=no
         After=kubelet.service

         [Service]
         Type=oneshot
         RemainAfterExit=yes
         ExecStart=bash -c "/bin/checkmodule -M -m -o /tmp/nested-podman.mod /etc/nested-podman/nested-podman.te && /bin/semodule_package -o /tmp/nested-podman.pp -m /tmp/nested-podman.mod && /sbin/semodule -i /tmp/nested-podman.pp"
         TimeoutSec=0

         [Install]
         WantedBy=multi-user.target
       enabled: true
       name: systemd-nested-podman-selinux.service
   EOF
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

  