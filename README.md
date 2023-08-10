# Test Repo for enabling podman in an OpenShift Pod

## Experimental - aka not working yet

This repo is for my attempts to get full `podman` capabilities working in OpenShift Dev Spaces (Eclipse Che)

The capability is needed for the following non-exclusive list:

* Java test-containers
* AWS development with Localstack
* Ansible development

## Watch this space for a working demo - hopefully

```bash
cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: nested-podman
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
        allowed_devices=["/dev/fuse"]
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
          class filesystem mount;
        }
        allow container_t tmpfs_t:filesystem mount;
        allow container_t devpts_t:filesystem mount;
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
  type: MustRunAsRange
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

oc adm policy add-scc-to-user -z cic default -n cic
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: podman-userns
 annotations:
   io.kubernetes.cri-o.Devices: "/dev/fuse"
   io.openshift.nested-podman: ""
spec:
  containers:
  - name: userns
    image: quay.io/cgruver0/che/che-dev-image:latest
    command: ["tail", "-f", "/dev/null"]
    securityContext:
      allowPrivilegeEscalation: true
      capabilities:
        add:
        - "MKNOD"
        - "SYS_CHROOT"
        - "SETFCAP"
        - "SETUID"
        - "SETGID"
EOF
```

```bash
if [ ! -d "${HOME}" ]; then
  mkdir -p "${HOME}"
fi

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "${USER_NAME:-user}:x:$(id -u):0:${USER_NAME:-user} user:${HOME}:/bin/bash" >> /etc/passwd
    echo "${USER_NAME:-user}:x:$(id -u):" >> /etc/group
  fi
fi

USER=$(whoami) ; START_ID=$(( $(id -u)+1 )) ; echo "${USER}:${START_ID}:2147483646" > /etc/subuid ; echo "${USER}:${START_ID}:2147483646" > /etc/subgid

rm ~/.config/containers/storage.conf

cat << EOF > ~/.config/containers/containers.conf                              
[containers]
netns="host"
ipcns="host"
default_sysctls = [] # Workaround
EOF

podman system migrate

mkdir ${HOME}/proc
podman run -v ${HOME}/proc:/proc registry.access.redhat.com/ubi9/ubi-minimal echo hello
```

## Below this line is experimenting and may not work

Enable User Namespaces in OpenShift:

```bash
oc patch nodes.config/cluster --type merge --patch '{"spec":{"cgroupMode":"v2"}}'
```

```bash
cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.13.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: nested-podman
storage:
  files:
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
  - path: /etc/crio/crio.conf.d/99-nested-podman
    mode: 0644
    overwrite: true
    contents:
      inline: |
        [crio.runtime.workloads.nested-podman]
        activation_annotation = "io.openshift.nested-podman"
        allowed_annotations = [
          "io.kubernetes.cri-o.userns-mode",
          "io.kubernetes.cri-o.Devices"
        ]
        [crio.runtime]
        allowed_devices=["/dev/fuse"]
EOF
```

```bash
oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"TechPreviewNoUpgrade"}}'
```

__Note:__ This does not enable `UserNamespacesStatelessPodsSupport`

```json
"featureGates": {
    "APIPriorityAndFairness": true,
    "BuildCSIVolumes": true,
    "CSIDriverSharedResource": true,
    "DownwardAPIHugePages": true,
    "DynamicResourceAllocation": true,
    "InsightsConfigAPI": true,
    "MachineAPIProviderOpenStack": true,
    "MatchLabelKeysInPodTopologySpread": true,
    "NodeSwap": true,
    "OpenShiftPodSecurityAdmission": true,
    "PDBUnhealthyPodEvictionPolicy": true,
    "RetroactiveDefaultStorageClass": true,
    "RotateKubeletServerCertificate": true
  },
```

__Note:__ This does not work.  OpenShift does not allow modification to `featureGates`

```bash
cat << EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: enable-userns
spec:
  logLevel: 5
  machineConfigPoolSelector:
    matchLabels:
      pools.operator.machineconfiguration.openshift.io/worker: ""
  kubeletConfig:
    featureGates:
      APIPriorityAndFairness: true
      DownwardAPIHugePages: true
      RetroactiveDefaultStorageClass: false
      RotateKubeletServerCertificate: true
      UserNamespacesStatelessPodsSupport: true
EOF
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: podman-userns
 annotations:
   io.kubernetes.cri-o.userns-mode: "auto:size=65536;keep-id=true"
spec:
  hostUsers: true
  containers:
  - name: userns
    image: quay.io/cgruver0/che/podman-basic:latest
    command: ["tail", "-f", "/dev/null"]
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    resources:
      limits:
        github.com/fuse: 1
EOF
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: podman-userns
 annotations:
   io.kubernetes.cri-o.userns-mode: "auto:size=65536;keep-id=true"
spec:
 containers:
   - name: userns
     image: quay.io/cgruver0/che/podman-basic:latest
     command: ["sleep", "10000"]
     securityContext:
       seccompProfile:
         type: RuntimeDefault
       capabilities:
         add:
           - "SYS_ADMIN"
           - "MKNOD"
           - "SYS_CHROOT"
           - "SETFCAP"
     resources:
       limits:
         github.com/fuse: 1
EOF
```

```bash
echo "user:x:$(id -u):0:user user:${HOME}:/bin/bash" >> /etc/passwd

cat << EOF > ~/.config/containers/containers.conf                              
[containers]
netns="host"
ipcns="host"
default_sysctls = [] # Workaround
EOF

podman system migrate

mkdir ${HOME}/proc
podman run -v ${HOME}/proc:/proc registry.access.redhat.com/ubi9/ubi-minimal echo hello
```

```bash
[crio.runtime.workloads.openshift-builder]
activation_annotation = "io.openshift.builder"
allowed_annotations = [
  "io.kubernetes.cri-o.userns-mode",
  "io.kubernetes.cri-o.Devices"
]

```

Enable fuse-overlayfs

```bash
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fuse-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: fuse-device-plugin-ds
  template:
    metadata:
      labels:
        name: fuse-device-plugin-ds
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
      hostNetwork: true
      containers:
      - image: quay.io/cgruver0/che/fuse-device-plugin:v1.1
        name: fuse-device-plugin-ctr
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
          - name: device-plugin
            mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
      imagePullSecrets:
        - name: registry-secret
EOF
```

```bash
cat << EOF > /tmp/nested-podman.te
module nested-podman 1.0;
type nested_podman_t;
require {
        type nested_podman_t;
        type devpts_t;
        type tmpfs_t;
        class filesystem mount;
}
allow nested_podman_t tmpfs_t:filesystem mount;
allow nested_podman_t devpts_t:filesystem mount;
EOF
checkmodule -M -m -o /tmp/nested-podman.mod /tmp/nested-podman.te && 
    semodule_package -o /tmp/nested-podman.pp -m /tmp/nested-podman.mod && 
    semodule -i /tmp/nested-podman.pp

cat << EOF > /tmp/nested-podman.te
policy_module(nested_podman, 0.1)
gen_require(`
  type container_t;
  type devpts_t;
  type tmpfs_t;
  class filesystem mount;
 ')
allow container_t tmpfs_t:filesystem mount;
allow container_t devpts_t:filesystem mount;
EOF


cat <<EOF >> /tmp/podman.te
module podman 1.0;

require {
	type container_t;
	type devpts_t;
	type tmpfs_t;
	class filesystem mount;
}

#============= container_t ==============

#!!!! This avc is allowed in the current policy
allow container_t tmpfs_t:filesystem mount;
allow container_t devpts_t:filesystem mount;
EOF

checkmodule -M -m -o /tmp/podman.mod /tmp/podman.te && 
    semodule_package -o /tmp/podman.pp -m /tmp/podman.mod           && 
    semodule -i /tmp/podman.pp
```

```bash
ausearch -m AVC -ts recent
```

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
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
  seLinuxOptions:
    type: devpts_t
    type: container_t
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
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: podman-userns
 annotations:
   io.kubernetes.cri-o.Devices: "/dev/fuse"
   io.kubernetes.cri-o.userns-mode: "auto:size=65536;keep-id=true"
   io.openshift.nested-podman: ""
spec:
  containers:
  - name: userns
    image: quay.io/cgruver0/che/che-dev-image:latest
    command: ["tail", "-f", "/dev/null"]
    securityContext:
      runAsUser: 0
      allowPrivilegeEscalation: true
      capabilities:
        add:
        - "SYS_ADMIN"
        - "MKNOD"
        - "SYS_CHROOT"
        - "SETFCAP"
        - "SETUID"
        - "SETGID"
EOF
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: podman-userns
 annotations:
   io.kubernetes.cri-o.Devices: "/dev/fuse"
   io.kubernetes.cri-o.userns-mode: "auto:size=65536;keep-id=true"
   io.openshift.nested-podman: ""
spec:
 containers:
   - name: userns
     image: quay.io/podman/stable
     command: ["tail", "-f", "/dev/null"]
     securityContext:
       capabilities:
         add:
           - "SYS_ADMIN"
           - "MKNOD"
           - "SYS_CHROOT"
           - "SETFCAP"
EOF
```

```bash
module setest 1.0;

require {
        type sysfs_t;
        type container_t;
        type nsfs_t;
        type tracefs_t;
        type devpts_t;
        type openvswitch_load_module_t;
        class dir search;
        class filesystem { remount unmount };
        class chr_file open;
}

#============= container_t ==============
allow container_t devpts_t:chr_file open;
allow container_t nsfs_t:filesystem unmount;
allow container_t sysfs_t:filesystem remount;

#============= openvswitch_load_module_t ==============
allow openvswitch_load_module_t tracefs_t:dir search;
```

```bash
cat << EOF > /tmp/nested-podman.te
module nested-podman 1.0;

require {
  type container_t;
  type devpts_t;
  type tmpfs_t;
  type sysfs_t;
  type nsfs_t;
  type proc_t;
  class chr_file open;
  class filesystem { mount remount unmount };
}
allow container_t tmpfs_t:filesystem mount;
allow container_t devpts_t:filesystem mount;
allow container_t devpts_t:filesystem remount;
allow container_t devpts_t:chr_file open;
allow container_t nsfs_t:filesystem unmount;
allow container_t sysfs_t:filesystem remount;
allow container_t proc_t:filesystem mount;
EOF
```

```bash
checkmodule -M -m -o /tmp/nested-podman.mod /tmp/nested-podman.te && 
    semodule_package -o /tmp/nested-podman.pp -m /tmp/nested-podman.mod && 
    semodule -i /tmp/nested-podman.pp
```

```bash
audit2allow -a -M setest
```
