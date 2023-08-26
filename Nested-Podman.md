# Notes for Working Demo

```bash
NODE_ROLE=master

cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${NODE_ROLE}
  name: nested-podman-${NODE_ROLE}
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
  - path: /etc/modules-load.d/podman-fuse.conf
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
          class chr_file open;
          class filesystem { mount remount unmount };
        }
        allow container_t tmpfs_t:filesystem mount;
        allow container_t devpts_t:filesystem mount;
        allow container_t devpts_t:filesystem remount;
        allow container_t devpts_t:chr_file open;
        allow container_t nsfs_t:filesystem unmount;
        allow container_t sysfs_t:filesystem mount;
        allow container_t sysfs_t:filesystem remount;
        allow container_t cgroup_t:filesystem remount;
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
cat << EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: FeatureGate
metadata:
  name: cluster 
spec:
  customNoUpgrade:
    enabled:
      - ProcMountType
  featureSet: CustomNoUpgrade
EOF
```

```bash
oc new-project cic
oc adm policy add-scc-to-user container-build -z default -n cic
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: podman-proc-mount
 annotations:
   io.kubernetes.cri-o.Devices: "/dev/fuse,/dev/net/tun"
   io.openshift.podman-fuse: ""
spec:
  containers:
  - name: proc-mount
    image: quay.io/cgruver0/che/che-dev-image:fuse
    command: ["tail", "-f", "/dev/null"]
    securityContext:
      allowPrivilegeEscalation: true
      procMount: Unmasked
      capabilities:
        add:
        - "SETUID"
        - "SETGID"
EOF
```

```bash
/entrypoint.sh
nohup podman system service --time=0 unix:///tmp/podman.sock > podman-sys.log &
export DOCKER_HOST="unix:///tmp/podman.sock"
export TESTCONTAINERS_RYUK_DISABLED=true 
export TESTCONTAINERS_CHECKS_DISABLE=true
git clone https://github.com/cgruver/quarkus-kafka.git
cd quarkus-kafka
mvn clean
mvn test
```
