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
oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"TechPreviewNoUpgrade"}}'

cat << EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: FeatureGate
metadata:
  name: cluster 
spec:
  featureSet: TechPreviewNoUpgrade
EOF
```

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
cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.12.0
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
        core:100000:65536
        containers:200000:268435456
  - path: /etc/subgid
    mode: 0644
    overwrite: true
    contents:
      inline: |
        core:100000:65536
        containers:200000:268435456
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
     image: quay.io/podman/stable
     command: ["sleep", "10000"]
     securityContext:
       allowPrivilegeEscalation: false
       runAsNonRoot: true
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

cat << EOF > containers.conf                              
[containers]
netns="host"
ipcns="host"
default_sysctls = [] # Workaround
EOF

podman system migrate

podman run registry.access.redhat.com/ubi9/ubi-minimal echo hello
```
