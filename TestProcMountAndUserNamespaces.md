# Notes for testing nested containers in OCP 4.16

```bash
oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["ProcMountType","UserNamespacesSupport"]}}}'
```

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

```bash
oc adm policy add-scc-to-user podman-scc <non-admin-user>
```

## Log Into The Cluster As <non-admin-user>

```bash
oc new-project podman-demo
```

```bash
cat << EOF | oc apply -f -
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: podman-runner
  namespace: podman-demo
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: podman-runner
  namespace: podman-demo
spec:
  source:
    git:
      uri: https://github.com/cgruver/openshift-nested-containers.git
      ref: main
    contextDir: "podman-image"
  strategy:
    dockerStrategy:
      dockerfilePath: "./podman-runner.Containerfile"
  output:
    to:
      kind: ImageStreamTag
      name: podman-runner:latest
EOF
```

```bash
oc start-build podman-runner -n podman-demo -w -F   
```

```bash
oc adm policy add-scc-to-user podman-scc -z default -n podman-demo
```

```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
 name: nested-podman
 namespace: podman-demo
 annotations:
   io.kubernetes.cri-o.Devices: "/dev/fuse"
spec:
  hostUsers: false
  containers:
  - name: nested-podman
    image: image-registry.openshift-image-registry.svc:5000/podman-demo/podman-runner:latest
    args: ["tail", "-f", "/dev/null"]
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
oc rsh nested-podman
```