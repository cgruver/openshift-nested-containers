# OpenShift Configuration Changes

## Enable `ProcMountType` feature gate

```yaml
apiVersion: config.openshift.io/v1
kind: FeatureGate
metadata:
  annotations:
    include.release.openshift.io/ibm-cloud-managed: "true"
    include.release.openshift.io/self-managed-high-availability: "true"
    include.release.openshift.io/single-node-developer: "true"
    release.openshift.io/create-only: "true"
  creationTimestamp: "2023-09-07T21:20:45Z"
  generation: 2
  name: cluster
  ownerReferences:
  - apiVersion: config.openshift.io/v1
    kind: ClusterVersion
    name: version
spec:
  customNoUpgrade:
    enabled:
    - ProcMountType
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

```bash
module setest 1.0;

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

## Enable a Dev Spaces workspace for Nested Containers

```yaml
components:
- name: dev-tools
  attributes:
    pod-overrides: {"metadata": {"annotations": {"io.kubernetes.cri-o.Devices":"/dev/fuse,/dev/net/tun","io.openshift.nested-podman":""}}}
    container-overrides: {"securityContext": {"procMount": "Unmasked"}}
  container: 
    image: quay.io/cgruver0/che/che-dev-image:nested
    # etc...
```