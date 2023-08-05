# Test Repo for enabling podman in an OpenShift Pod

## Experimental - aka not working yet

This repo is for my attempts to get full `podman` capabilities working in OpenShift Dev Spaces (Eclipse Che)

The capability is needed for the following non-exclusive list:

* Java test-containers
* AWS development with Localstack
* Ansible development

## Watch this space for a working demo - hopefully

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
    machineconfiguration.openshift.io/role: worker
  name: subuid-subgid
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
  type: MustRunAsNonRoot
seLinuxContext:
  type: MustRunAs
  seLinuxOptions:
    type: spc_t
seccompProfiles:
- runtime/default
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
    resources:
      limits:
        github.com/fuse: 1
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

## Below this line does not work

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


## io.kubernetes.cri-o.Devices: "/dev/fuse"



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
