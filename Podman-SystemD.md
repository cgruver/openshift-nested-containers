## Podman With Systemd

Enable User Namespaces in OpenShift:

```bash
oc patch nodes.config/cluster --type merge --patch '{"spec":{"cgroupMode":"v2"}}'

cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: userns-podman-fuse
storage:
  files:
  - path: /etc/crio/crio.conf.d/99-userns
    mode: 0644
    overwrite: true
    contents:
      inline: |
        [crio.runtime.workloads.userns]
        activation_annotation = "io.kubernetes.cri-o.userns-mode"
        allowed_annotations = [
          "io.kubernetes.cri-o.userns-mode"
        ]
  - path: /etc/subuid
    mode: 0644
    overwrite: true
    contents:
      inline: |
        core:524288:65536
        containers:600000:268435456
  - path: /etc/subgid
    mode: 0644
    overwrite: true
    contents:
      inline: |
        core:524288:65536
        containers:600000:268435456
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
        allowed_devices=["/dev/fuse"]
  - path: /etc/nested-podman/nested-podman.te
    mode: 0644
    overwrite: true
    contents:
      inline: |
        module nested-podman 1.0;

        require {
          type container_t;
          type container_init_t;
          type cgroup_t;
          type proc_t;
          type devpts_t;
          type tmpfs_t;
          type sysfs_t;
          type nsfs_t;
          class chr_file open;
          class file watch;
          class filesystem { mount remount unmount };
        }
        allow container_t tmpfs_t:filesystem mount;
        allow container_t devpts_t:filesystem mount;
        allow container_t devpts_t:filesystem remount;
        allow container_t devpts_t:chr_file open;
        allow container_t nsfs_t:filesystem unmount;
        allow container_t sysfs_t:filesystem remount;
        allow container_t cgroup_t:file watch;
        allow container_t cgroup_t:filesystem remount;
        allow container_t proc_t:filesystem mount;
        allow container_init_t cgroup_t:filesystem remount;
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

## Working Combo - SCC + POD

```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: cic
priority: null
readOnlyRootFilesystem: false
defaultAddCapabilities:
- "MKNOD"
- "SYS_CHROOT"
- "SETFCAP"
- "SETUID"
- "SETGID"
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
users: []
volumes:
- configMap
- csi
- downwardAPI
- emptyDir
- ephemeral
- persistentVolumeClaim
- projected
- secret
EOF

oc adm policy add-scc-to-user cic -z default -n cic2
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: podman-localstack-test
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536;keep-id=true"
    # io.kubernetes.cri-o.userns-mode: "auto:size=65536;map-to-root=true"
    # io.kubernetes.cri-o.userns-mode: "auto"
    io.kubernetes.cri-o.Devices: "/dev/fuse"
    io.openshift.nested-podman: ""
spec:
  containers:
  - name: userns
    image: quay.io/cgruver0/che/che-dev-image:init
    command: ["/sbin/init"]
    securityContext:
      runAsNonRoot: false
      allowPrivilegeEscalation: true
      readOnlyRootFilesystem: false
      capabilities:
        add:
        - "MKNOD"
        - "SYS_CHROOT"
        - "SETFCAP"
        - "SETUID"
        - "SETGID"
EOF
```
