# Test Repo for enabling podman in an OpenShift Pod

This repo is for my attempts to get full `podman` capabilities working in OpenShift Dev Spaces (Eclipse Che)

The capability is needed for the following non-exclusive list:

* Java test-containers
* AWS development with Localstack
* AWS Lambda development with SAM CLI
* Ansible development

## Early Demo Here - [Eclipse Che / OpenShift Dev Spaces - Podman With Fuse Overlay](https://upstreamwithoutapaddle.com/blog%20post/2023/08/10/Podman-In-Dev-Spaces-With-Fuse-Overlay.html)

## Notes for Fully *Working* Demo

__NOTE:__ *Do not apply these changes to a production or shared instance of OCP.  These changes will put your cluster in a non-upgradable state*

1. Install `butane`:

   [https://coreos.github.io/butane/](https://coreos.github.io/butane/){:target="_blank"}

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

1. Enable the `ProcMountType` Kubernetes feature gate.

   __Note:__ Because this feature gate is still in *Alpha* state, enabling it will render your cluster non-upgradable.

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

1. Edit the Eclipse Che `ClusterServiceVersion` to enable `/proc` unmasking:

   ```bash
   CHE_CSV=$(oc get csv -n openshift-operators -o name | grep "eclipse-che")
   oc edit ${CHE_CSV} -n openshift-operators
   ```

   Find: `CHE_DEFAULT_SPEC_DEVENVIRONMENTS_CONTAINERSECURITYCONTEXT`

   Replace the value with: `'{"allowPrivilegeEscalation": true,"procMount": "Unmasked","capabilities": {"add": ["SETGID", "SETUID"]}}'`

## Demo of AWS SAM CLI

```bash
cd /projects
git clone https://github.com/aws/aws-sam-cli-app-templates.git
sam init --name sam-py-app --architecture=x86_64 --location="aws-sam-cli-app-templates/python3.9/hello" --no-tracing --no-application-insights --no-input
cd sam-py-app
sam build
nohup podman system service --time=0 unix:///tmp/podman.sock > /projects/podman-sys.log &
export DOCKER_HOST="unix:///tmp/podman.sock"
nohup sam local start-api --debug --docker-network=podman > /projects/sam.out &
curl http://127.0.0.1:3000/hello
```

## Demo of Quarkus Dev Services - *Does Not Work Yet*

```bash
cd /projects
nohup podman system service --time=0 unix:///tmp/podman.sock > podman-sys.log &
export DOCKER_HOST="unix:///tmp/podman.sock"
export TESTCONTAINERS_RYUK_DISABLED=true 
export TESTCONTAINERS_CHECKS_DISABLE=true
git clone https://github.com/cgruver/quarkus-kafka.git
cd quarkus-kafka
mvn clean
mvn test
```
