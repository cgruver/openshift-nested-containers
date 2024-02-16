# OpenShift Configuration Changes

## Enable `ProcMountType` & `UserNamespacesSupport` feature gate

```yaml
apiVersion: config.openshift.io/v1
kind: FeatureGate
metadata:
  name: cluster
spec:
  customNoUpgrade:
    enabled:
    - ProcMountType
    - UserNamespacesSupport
  featureSet: CustomNoUpgrade
```

## CRI-O Enable `/dev/fuse` & `dev/net/tun`

`/etc/crio/crio.conf.d/99-nested-podman`

```bash
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
```

## Load kernel modules

`/etc/modules-load.d/nested-podman.conf`

```bash
tun
rtnl-link-bridge
ipt_addrtype
```

## SeLinux Changes

`/etc/nested-podman/nested-podman.te`

```bash
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
```

## Enable a Dev Spaces workspace for Nested Containers

```yaml
components:
- name: dev-tools
  attributes:
    pod-overrides: {"metadata": {"annotations": {"io.kubernetes.cri-o.Devices":"/dev/fuse","io.openshift.nested-podman":""}}}
    container-overrides: {"securityContext": {"procMount": "Unmasked"}}
  container: 
    image: quay.io/cgruver0/che/che-dev-image:nested
    # etc...
```