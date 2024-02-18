# Test Repo for enabling podman in Eclipse Che / OpenShift Dev Spaces

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

## Run the Demos

1. Create an Eclipse Che workspace from this git repo: `https://github.com/cgruver/openshift-nested-containers.git`

### Run a container:

1. Open a terminal into the `openshift-nested-containers` project.

1. Run the following:

   ```bash
   podman run -d --rm --name webserver -p 8080:80 quay.io/libpod/banner
   curl http://localhost:8080
   ```

1. Run an interactive container:

   ```bash
   podman run -it --rm registry.access.redhat.com/ubi9/ubi-minimal
   ```

### Demo of Ansible Navigator

1. Clear the `CONTAINER_HOST` environment variable: (We're going to run this without a "remote" podman socket)

   ```bash
   unset CONTAINER_HOST
   ```

1. Open a terminal into the `ansible-demo` project.

1. Run the following command:

   ```bash
   ansible-navigator run helloworld.yaml
   ```

### Demo of AWS SAM CLI with Podman

1. Use the `Task Manager` extension to run the `Start Podman Service` task.

1. Open a terminal in the `sam-cli-demo` project:

   ```bash
   sam init --name sam-py-app --architecture=x86_64 --location="./python3.9/hello" --no-tracing --no-application-insights --no-input
   cd sam-py-app
   sam build
   sam local start-api --debug --docker-network=podman
   ```

1. Open a second terminal to invoke the Lambda function:

   ```bash
   curl http://127.0.0.1:3000/hello
   ```

### Demo of Quarkus Dev Services with Podman

1. Open a terminal in the `quarkus-dev-services-demo` project:

   ```bash
   mvn clean
   mvn test
   ```

## Demo of AWS Dev With Localstack with Podman

1. Use the `Task Manager` extension to run the `Start Localstack Service` task.

1. Open a terminal in the `localstack-demo` project:

   ```bash
   make deploy
   awslocal s3 ls s3://archive-bucket/
   ```
