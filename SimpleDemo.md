# Demo for Enabling Nested Containers in OpenShift

1. Install `butane`:

   [https://coreos.github.io/butane/](https://coreos.github.io/butane/)

   We need `butane` to assist with the creation of MachineConfigs.  It's really handy for that.

   __Note:__ If you previously followed one of my blog posts to install your OpenShift cluster, then you should already have `butane` installed.

1. Apply the following MachineConfig: __Note:__ Your cluster will restart the targeted nodes.

   This MachineConfig does 3 things:

   1. Allow Pods with the `io.openshift.nested-podman` access to `/dev/fuse` and `/dev/net/tun`
   1. Load the kernel modules: `tun`, `rtnl-link-bridge`, and `ipt_addrtype`
   1. Apply an `selinux` module.

1. Set a variable for the OpenShift Node role that you are going to apply the changes to:

   If you are using a Single Node cluster or OpenShift Local, then set:

   ```bash
   NODE_ROLE=master
   ```

   If you are using an OpenShift cluster with separate control-plane and compute nodes, then set:

   ```bash
   NODE_ROLE=worker
   ```

1. Apply the MachineConfig:

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

1. Enable the `ProcMountType` Kubernetes feature gate.

   __Note:__ Because this feature gate is still in *Alpha* state, enabling it will render your cluster non-upgradable.

   ```bash
   oc patch FeatureGate cluster --type merge --patch '{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["ProcMountType"]}}}'
   ```

1. Create an SCC for Podman:

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

1. Log into OpenShift as a non-cluster-admin user

1. Create a new Project

   ```bash
   oc new-project podman-demo
   ```

1. As cluster-admin allow the `default` service account in the new Project to use the podman SCC

   ```bash
   oc adm policy add-scc-to-user podman-scc -z default -n nested-containers
   ```

1. Create an `ImageStream` and `BuildConfig` that supports a podman runtime:

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

1. Build the image:

   ```bash
   oc start-build podman-runner -n podman-demo -w -F   
   ```

1. Create a Pod as your non-cluster-admin user

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

1. Open a shell into the Pod:

1. Run the following:

   ```bash
   podman run -d --rm --name webserver -p 8080:80 quay.io/libpod/banner
   curl http://localhost:8080
   ```
