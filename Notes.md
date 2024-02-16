# Raw Notes & Scratch Pad

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

```bash
ausearch -m AVC -ts recent
```

```bash
cat << EOF > ~/.config/containers/containers.conf                              
[containers]
netns="none"
volumes=[
  "${HOME}/proc:/proc:rw"
]
default_sysctls = []
EOF
```

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
  name: userns
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

## Reduce Priv Test

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
    # io.kubernetes.cri-o.userns-mode: "auto:size=65536;keep-id=true"
    # io.kubernetes.cri-o.userns-mode: "auto:size=65536;map-to-root=true"
    # io.kubernetes.cri-o.userns-mode: "auto"
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
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

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: podman-localstack-test
  annotations:
    io.kubernetes.cri-o.userns-mode: "auto:size=65536"
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
EOF
```

```bash
oc patch scc container-build --type merge --patch '{"runAsUser":{"type":"RunAsAny"}}'
```

## Needed After Enabling CgroupsV2

```bash
module setest 1.0;

require {
	type devpts_t;
	type sysfs_t;
	type nsfs_t;
	type container_init_t;
	type proc_t;
	type container_t;
	type cgroup_t;
	class filesystem { mount remount unmount };
	class chr_file open;
	class file watch;
}

#============= container_init_t ==============
allow container_init_t cgroup_t:filesystem remount;

#============= container_t ==============

#!!!! This avc can be allowed using the boolean 'container_manage_cgroup'
allow container_t cgroup_t:file watch;
allow container_t cgroup_t:filesystem remount;
allow container_t devpts_t:chr_file open;
allow container_t devpts_t:filesystem remount;
allow container_t nsfs_t:filesystem unmount;
allow container_t proc_t:filesystem mount;
allow container_t sysfs_t:filesystem remount;
```

## OpenShift Operator for SeLinux

```bash
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: operatorhubio
  namespace: openshift-marketplace
spec:
  displayName: Community Operators
  image: quay.io/operator-framework/upstream-community-operators:latest
  publisher: OperatorHub.io
  sourceType: grpc
EOF
```

```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-security-profiles
  namespace: openshift-security-profiles
spec:
  upgradeStrategy: Default
--- 
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: security-profiles-operator
  namespace: openshift-security-profiles
spec:
  channel: release-alpha-rhel-8
  installPlanApproval: Automatic
  name: security-profiles-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

```bash
# Install security profile
oc create namespace openshift-security-profiles
oc apply -f ./security-profiles-operator/operator.yaml


# wait a few seconds


oc patch spod spod -n openshift-security-profiles --type='json' -p='[{"op": "add", "path": "/spec/selinuxOptions/allowedSystemProfiles/-", "value":"net_container"}]'
oc apply -f ./security-profiles-operator/selinux-profile.yaml -n openshift-security-profiles

```

```yaml
apiVersion: security-profiles-operator.x-k8s.io/v1alpha2
kind: SelinuxProfile
metadata:
  name: allow-csi-socket
spec:
  allow:
    var_run_t:
      sock_file:
        - write        
  inherit:
    - name: net_container
    - name: container
  permissive: false
  ```
  
```bash
podman system service --time=0 unix:///tmp/podman.sock
```

## KubeControllerManager

```yaml
  unsupportedConfigOverrides:
    featureGates:
      - ProcMountType=true
```

## KubeAPIServer

```yaml
  unsupportedConfigOverrides:
    apiServerArguments:
      feature-gates:
        - ProcMountType=true
```

##

{"metadata": {"annotations": {"io.kubernetes.cri-o.Devices":"/dev/fuse,/dev/net/tun","io.openshift.podman-fuse":""}},"spec": {"securityContext":{"procMount": "Unmasked"}}}

attributes:
    pod-overrides: {"metadata": {"annotations": {"io.kubernetes.cri-o.Devices":"/dev/fuse,/dev/net/tun","io.openshift.podman-fuse":""}},"spec": {"securityContext":{"procMount": "Unmasked", "seccompProfile": {"type": "Unconfined"}}}}
  container: 

require {
        type cgroup_t;
        type kernel_t;
        type sysfs_t;
        type container_t;
        class system module_request;
        class filesystem { mount remount };
}

allow container_t cgroup_t:filesystem remount;
allow container_t kernel_t:system module_request;
allow container_t sysfs_t:filesystem mount;


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

pod-overrides: {"metadata": {"annotations": {"io.kubernetes.cri-o.Devices":"/dev/fuse,/dev/net/tun","io.openshift.podman-fuse":""}},"spec": {"securityContext": {"sysctls": [{"name":"net.ipv4.conf.podman1.route_localnet","value":"1"},{"name":"net.ipv4.conf.podman2.route_localnet","value":"1"}]}}}

```bash
cat << EOF | oc apply -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: tuningnad
  namespace: cgruver-che
spec:
  config: '{
    "cniVersion": "0.4.0",
    "name": "tuningnad",
    "plugins": [{
      "type": "bridge"
      },
      {
      "type": "tuning",
      "sysctl": {
         "net.ipv4.conf.IFNAME.route_localnet": "1"
        }
    }
  ]
}'
EOF
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

## Notes for Working Demo

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
oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["ProcMountType"]}}}'

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
CHE_CSV=$(oc get csv -n openshift-operators -o name | grep "eclipse-che")

cat << EOF | oc patch ${CHE_CSV} -n openshift-operators --patch-file -
spec:
  install:
    spec:
      deployments:
      - name: che-operator
        spec:
          template:
            spec:
              containers:
              - name: che-operator
                env:
                - name: CHE_DEFAULT_SPEC_DEVENVIRONMENTS_CONTAINERSECURITYCONTEXT
                  value: '{"allowPrivilegeEscalation": true,"procMount": "Unmasked","capabilities": {"add": ["SETGID", "SETUID"]}}'
EOF
```

```bash
CHE_CSV=$(oc get csv -n openshift-operators -o name | grep "eclipse-che")
oc edit ${CHE_CSV} -n openshift-operators
```

Find: `CHE_DEFAULT_SPEC_DEVENVIRONMENTS_CONTAINERSECURITYCONTEXT`

Replace the value with: `'{"allowPrivilegeEscalation": true,"procMount": "Unmasked","capabilities": {"add": ["SETGID", "SETUID"]}}'`

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

```bash
git clone https://github.com/aws/aws-sam-cli-app-templates.git
sam init --name sam-py-app --architecture=x86_64 --location="aws-sam-cli-app-templates/python3.9/hello" --no-tracing --no-application-insights --no-input
cd sam-py-app
sam build
# Start podman service in rootless mode (user space)
nohup podman system service --time=0 unix:///tmp/podman.sock > podman-sys.log &
export DOCKER_HOST="unix:///tmp/podman.sock"
nohup sam local start-api --debug --docker-network=podman > sam.out &
curl http://127.0.0.1:3000/hello
```

## Localstack Notes

```bash
cat << EOF > ~/.config/containers/registries.conf
unqualified-search-registries = ["registry.access.redhat.com", "registry.redhat.io", "docker.io"]
short-name-mode = "permissive"
EOF


export DOCKER_SOCK=/tmp/podman.sock
export DOCKER_CMD=podman
DEBUG=1 localstack start

```

```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: container-run
priority: null
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
readOnlyRootFilesystem: false
requiredDropCapabilities:
- KILL
- MKNOD
runAsUser:
  type: MustRunAsRange
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

Add to ClusterRole for port-forward (unrelated to nested containers)
```yaml
- apiGroups:
  - ""
  resources:
  - pods/portforward
  verbs:
  - get
  - list
  - watch
  - create
  - delete
  - deletecollection
  - patch
  - update
```

## Test Without ProcMountType

```bash
cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.14.0
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


```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
metadata:
  name: nested-podman-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: true
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

oc adm policy add-scc-to-user nested-podman-scc cgruver
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: nested-podman
 namespace: podman-demo
 annotations:
   io.kubernetes.cri-o.Devices: "/dev/fuse,/dev/net/tun"
   io.openshift.nested-podman: ""
spec:
  containers:
  - name: nested-podman
    image: image-registry.openshift-image-registry.svc:5000/podman-demo/podman-runner:latest
    args: ["tail", "-f", "/dev/null"]
    securityContext:
      privileged: true
      allowPrivilegeEscalation: true
      procMount: Unmasked
      capabilities:
        add:
        - "SETUID"
        - "SETGID"
EOF
```