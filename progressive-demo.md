# Progressive Demo for enabling Nested Podman in OpenShift

## SecurityContextConstraint

```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
metadata:
  name: podman-scc
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
  type: MustRunAs
groups: []
kind: SecurityContextConstraints
priority: null
readOnlyRootFilesystem: false
requiredDropCapabilities:
- KILL
- MKNOD
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
  seLinuxOptions:
    type: nested_podman_t
    type: container_t
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

## Limited Podman Run With VFS

```bash
mkdir -p ${HOME}/proc

cat << EOF > ~/.config/containers/containers.conf                              
[containers]
netns="none"
volumes=[
  "${HOME}/proc:/proc:rw"
]
default_sysctls = []
EOF

podman run registry.access.redhat.com/ubi9/ubi-minimal echo hello
```

```bash
cat << EOF > podman-run.te
module podman-run 1.0;

require {
        type sysfs_t;
        type container_t;
        type devpts_t;
        type nsfs_t;
        class filesystem { mount unmount };
}

allow container_t devpts_t:filesystem mount;
allow container_t nsfs_t:filesystem unmount;
allow container_t sysfs_t:filesystem mount;
EOF

checkmodule -M -m -o podman-run.mod podman-run.te && semodule_package -o podman-run.pp -m podman-run.mod && semodule -i podman-run.pp
```

```bash
cat << EOF > podman-run-net.te
module podman-run-net 1.0;

require {
        type devpts_t;
        type container_t;
        type cgroup_t;
        class filesystem { remount };
        class chr_file open;
}

allow container_t cgroup_t:filesystem remount;
allow container_t devpts_t:chr_file open;
EOF

checkmodule -M -m -o podman-run-net.mod podman-run-net.te && semodule_package -o podman-run-net.pp -m podman-run-net.mod && semodule -i podman-run-net.pp
```

podman run -d --rm --name webserver -p 8080:80 quay.io/libpod/banner


## Enable `/dev/fuse` & `/dev/net/tun`

```bash
cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: nested-podman-master
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
EOF
```

```bash
mkdir -p ${HOME}/proc

cat << EOF > ~/.config/containers/containers.conf                              
[containers]
netns="private"
volumes=[
  "${HOME}/proc:/proc:rw"
]
default_sysctls = []
[engine]
network_cmd_options=[
  "enable_ipv6=false"
]
EOF

podman run registry.access.redhat.com/ubi9/ubi-minimal echo hello
podman run -d --rm --name webserver -p 8080:80 quay.io/libpod/banner
curl http://localhost:8080
```

```bash
cat << EOF > podman-run-interactive.te
module podman-run-interactive 1.0;

require {
        type sysfs_t;
        type container_t;
        type devpts_t;
        class filesystem remount;
}

allow container_t devpts_t:filesystem remount;
allow container_t sysfs_t:filesystem remount;
EOF

checkmodule -M -m -o podman-run-interactive.mod podman-run-interactive.te && semodule_package -o podman-run-interactive.pp -m podman-run-interactive.mod && semodule -i podman-run-interactive.pp
```

```bash
cat << EOF > podman-run-proc.te
module podman-run-proc 1.0;

require {
        type proc_t;
        type container_t;
        class filesystem mount;
}

allow container_t proc_t:filesystem mount;
EOF

checkmodule -M -m -o podman-run-proc.mod podman-run-proc.te && semodule_package -o podman-run-proc.pp -m podman-run-proc.mod && semodule -i podman-run-proc.pp
```

```bash
cat << EOF > nested_podman.te
policy_module(nested_podman, 1.0)

type: nested_podman_t;
init_
EOF


```

```bash
cat << EOF > nested-podman.te
module nested-podman 1.0;

require {
  type nested_podman_t;
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
allow nested_podman_t tmpfs_t:filesystem mount;
allow nested_podman_t devpts_t:filesystem mount;
allow nested_podman_t devpts_t:filesystem remount;
allow nested_podman_t devpts_t:chr_file open;
allow nested_podman_t devpts_t:chr_file setattr;
allow nested_podman_t nsfs_t:filesystem unmount;
allow nested_podman_t sysfs_t:filesystem mount;
allow nested_podman_t sysfs_t:filesystem remount;
allow nested_podman_t cgroup_t:filesystem remount;
allow nested_podman_t proc_kcore_t:file mounton;
allow nested_podman_t proc_t:dir mounton;
allow nested_podman_t proc_t:file mounton;
allow nested_podman_t proc_t:filesystem mount;
allow nested_podman_t sysctl_irq_t:dir mounton;
allow nested_podman_t sysctl_t:dir mounton;
allow nested_podman_t sysctl_t:file mounton;
EOF

checkmodule -M -m -o nested-podman.mod nested-podman.te && semodule_package -o nested-podman.pp -m nested-podman.mod && semodule -i nested-podman.pp
```
