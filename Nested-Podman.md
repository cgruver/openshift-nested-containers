# Notes for Working Demo

```bash
NODE_ROLE=master

cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${NODE_ROLE}
  name: podman-dev-fuse-tun-${NODE_ROLE}
storage:
  files:
  - path: /etc/crio/crio.conf.d/99-podman-fuse
    mode: 0644
    overwrite: true
    contents:
      inline: |
        [crio.runtime.workloads.podman-fuse]
        activation_annotation = "io.openshift.podman-fuse"
        allowed_annotations = [
          "io.kubernetes.cri-o.Devices"
        ]
        [crio.runtime]
        allowed_devices = [
          "/dev/fuse",
          "/dev/net/tun"
        ]
EOF
```

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
  - path: /etc/nested-podman/nested-podman.te
    mode: 0644
    overwrite: true
    contents:
      inline: |
        module nested-podman 1.0;

        require {
          type container_t;
          type devpts_t;
          type tmpfs_t;
          type sysfs_t;
          type nsfs_t;
          type kernel_t;
          class chr_file open;
          class filesystem { mount remount unmount };
          class system module_request;
        }
        allow container_t tmpfs_t:filesystem mount;
        allow container_t devpts_t:filesystem mount;
        allow container_t devpts_t:filesystem remount;
        allow container_t devpts_t:chr_file open;
        allow container_t nsfs_t:filesystem unmount;
        allow container_t sysfs_t:filesystem remount;
        allow container_t kernel_t:system module_request;
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

```bash
podman system service --time=0 unix:///tmp/podman.sock
```

```bash
[containers]
netns="private"
volumes=[
  "/home/user/proc:/proc:rw"
]
default_sysctls = []
[engine]
network_cmd_options=[
  "enable_ipv6=false"
]


[containers]
netns="slirp4netns"
volumes=[
  "/home/user/proc:/proc:rw"
]
default_sysctls = []
[engine]
network_cmd_options=[
  "enable_ipv6=false"
]
[network]
network_backend="cni"
```

sysctls:
    - net.ipv4.conf.tun0.route_localnet=1    # Doesn't work as tun0 doesn't 
                                             # exist yet at container start time
    - net.ipv4.conf.default.route_localnet=1 # Workaround.

require {
        type kernel_t;
        type devpts_t;
        type cgroup_t;
        type sysfs_t;
        type container_t;
        class filesystem { mount remount };
        class system module_request;
}

allow container_t cgroup_t:filesystem remount;
allow container_t devpts_t:filesystem mount;
allow container_t kernel_t:system module_request;
allow container_t sysfs_t:filesystem mount;


[containers]
netns="slirp4netns"
volumes=[
  "/home/user/proc:/proc:rw"
]
default_sysctls = [
  "net.ipv4.conf.podman1.route_localnet=1",
  "net.ipv4.ip_forward=1",
  "net.ipv6.conf.all.autoconf=0"
]
[network]
network_backend="cni"
[engine]
network_cmd_options=[
  "enable_ipv6=false"
]